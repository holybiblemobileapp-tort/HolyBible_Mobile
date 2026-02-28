import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'bible_model.dart';
import 'bible_service.dart';
import 'bible_logic.dart';
import 'audio_service.dart';
import 'database_service.dart';
import 'agreement_service.dart';
import 'bible_reader_view.dart';
import 'study_hub_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const HolyBibleApp());
}

class HolyBibleApp extends StatefulWidget {
  const HolyBibleApp({super.key});
  @override
  State<HolyBibleApp> createState() => _HolyBibleAppState();
}

class _HolyBibleAppState extends State<HolyBibleApp> {
  bool _isDarkMode = false;
  bool _isAudioEnabled = false; 
  double _fontSize = 18.0;
  void _toggleTheme(bool value) => setState(() => _isDarkMode = value);
  void _toggleAudio(bool value) => setState(() => _isAudioEnabled = value);
  void _updateFontSize(double value) => setState(() => _fontSize = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AKJV 1611 PCE circa 1900',
      debugShowCheckedModeBanner: false,
      theme: _isDarkMode ? _buildDarkTheme() : _buildLightTheme(),
      home: MainNavigator(
        isDarkMode: _isDarkMode, 
        isAudioEnabled: _isAudioEnabled,
        fontSize: _fontSize, 
        onThemeChanged: _toggleTheme, 
        onAudioChanged: _toggleAudio,
        onFontSizeChanged: _updateFontSize
      ),
    );
  }

  ThemeData _buildLightTheme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
    useMaterial3: true,
    appBarTheme: AppBarTheme(backgroundColor: Colors.brown[700], foregroundColor: Colors.white, iconTheme: const IconThemeData(color: Colors.white)),
    scaffoldBackgroundColor: Colors.white,
  );

  ThemeData _buildDarkTheme() => ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown, brightness: Brightness.dark),
    useMaterial3: true,
    appBarTheme: AppBarTheme(backgroundColor: Colors.grey[900], foregroundColor: Colors.white, iconTheme: const IconThemeData(color: Colors.white)),
    scaffoldBackgroundColor: Colors.black,
  );
}

class MainNavigator extends StatefulWidget {
  final bool isDarkMode;
  final bool isAudioEnabled;
  final double fontSize;
  final Function(bool) onThemeChanged;
  final Function(bool) onAudioChanged;
  final Function(double) onFontSizeChanged;
  const MainNavigator({super.key, required this.isDarkMode, required this.isAudioEnabled, required this.fontSize, required this.onThemeChanged, required this.onAudioChanged, required this.onFontSizeChanged});
  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _dbService = DatabaseService();
  final BibleService _bibleService = BibleService();
  final AudioService _audioService = AudioService();
  
  late Future<void> _initFuture;
  late Future<List<dynamic>> _dataFuture;
  
  String? _selectedBook;
  int? _selectedChapter;
  int? _selectedVerse;
  int? _selectedWordIndex;
  List<int> _chapters = [];
  List<BibleVerse> _chapterVerses = [];
  BibleViewStyle _currentStyle = BibleViewStyle.standard;
  bool _isSearching = false;
  bool _isLoadingSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _bookFilterController = TextEditingController();
  List<String> _books = [];
  BibleVerse? _dailyVerse;
  String? _jumpHighlightPhrase;
  List<BibleMatch> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: 3);
    _audioService.setEnabled(widget.isAudioEnabled);
    _startInitialization();
    _checkAgreement();
  }

  @override
  void didUpdateWidget(MainNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAudioEnabled != oldWidget.isAudioEnabled) {
      _audioService.setEnabled(widget.isAudioEnabled);
    }
  }

  Future<void> _checkAgreement() async {
    if (!await AgreementService.hasAccepted() && mounted) _showAgreementDialog();
  }

  void _showAgreementDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (context) => PopScope(canPop: false, child: AlertDialog(title: const Text('No-Warranty Agreement'), content: SizedBox(width: double.maxFinite, child: FutureBuilder<String>(future: rootBundle.loadString('assets/NO_WARRANTY_AGREEMENT.md'), builder: (context, snapshot) { if (!snapshot.hasData) return const CircularProgressIndicator(); return SingleChildScrollView(child: Text(snapshot.data!)); })), actions: [TextButton(onPressed: () => exit(0), child: const Text('Decline')), ElevatedButton(onPressed: () async { await AgreementService.accept(); if (mounted) Navigator.pop(context); }, child: const Text('Accept'))])));
  }

  void _startInitialization() {
    _initFuture = _initialize();
    _dataFuture = _loadData();
  }

  Future<List<dynamic>> _loadData() async {
    final data = await Future.wait([_bibleService.loadContinuity(), _bibleService.loadParentheses()]);
    if (data[1] is Map<String, String>) BibleLogic.prepareParentheses(data[1] as Map<String, String>);
    return data;
  }

  Future<void> _initialize() async {
    try {
      await _dbService.initialize();
      _books = await _dbService.getBooks();
      _dailyVerse = await _dbService.getRandomVerse();
      if (mounted) setState(() {});
    } catch (e) { debugPrint("Init Error: $e"); }
  }

  @override
  void dispose() { _audioService.dispose(); _tabController.dispose(); _searchController.dispose(); _bookFilterController.dispose(); super.dispose(); }

  String _getVersionName(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard: return 'AKJV 1611 PCE circa 1900';
      case BibleViewStyle.superscript: return 'Superscript KJV';
      case BibleViewStyle.mathematics: return 'Mathematics KJV 1';
      case BibleViewStyle.mathematics2: return 'Mathematics KJV 2';
      case BibleViewStyle.mathematicsUnconstraint: return 'Mathematics KJV UNCONSTRAINT';
      default: return 'Standard';
    }
  }

  void _handleSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    String? phrase;
    String? locStr;

    final phraseLocRegex = RegExp(r'^(.*?)\s*=\s*\(([^)]+)\)$');
    final inverseRelRegex = RegExp(r'^(.*?)\s*↦\s*\{?([^}]+)\}?$');
    
    final matchPhraseLoc = phraseLocRegex.firstMatch(trimmed);
    final matchInverse = inverseRelRegex.firstMatch(trimmed);

    if (matchPhraseLoc != null) {
      phrase = matchPhraseLoc.group(1)?.trim();
      locStr = matchPhraseLoc.group(2)!.trim();
    } else if (matchInverse != null) {
      phrase = matchInverse.group(1)?.trim();
      locStr = matchInverse.group(2)!.split(',').first.trim();
    } else {
      locStr = trimmed;
    }

    String mainLocStr = locStr ?? '';
    if (mainLocStr.contains('_')) mainLocStr = mainLocStr.split('_').first;

    final loc = BibleLogic.parseLocation(mainLocStr);
    if (loc != null) {
      if (matchPhraseLoc != null || matchInverse != null) {
        final bookName = await _dbService.getBookNameFromAbbr(loc.bookAbbr);
        if (bookName != null) {
          _jumpToLocation(bookName, loc.chapter, loc.verse, _currentStyle, highlightPhrase: phrase, wordIndex: loc.startWord);
          return;
        }
      }
    }

    setState(() { _isLoadingSearch = true; _searchResults = []; _isSearching = true; });
    try {
      final results = await _dbService.search(query);
      if (mounted) setState(() { _searchResults = results; });
    } catch (e) { debugPrint("Search Error: $e"); }
    if (mounted) setState(() { _isLoadingSearch = false; });
  }

  void _onBookSelected(String book) async {
    final chapters = await _dbService.getChapters(book);
    setState(() { _selectedBook = book; _selectedChapter = null; _selectedVerse = null; _chapters = chapters; _bookFilterController.clear(); });
    _tabController.animateTo(1);
  }

  void _onChapterSelected(int chapter) async {
    final versesList = await _dbService.getChapter(_selectedBook!, chapter);
    setState(() { _selectedChapter = chapter; _selectedVerse = null; _chapterVerses = versesList; });
    _tabController.animateTo(2);
  }

  void _onVerseSelected(int verse) {
    setState(() { _selectedVerse = verse; _selectedWordIndex = null; });
    _tabController.animateTo(3);
  }

  void _onChapterNavigate(String book, int ch) async {
    final chaptersList = await _dbService.getChapters(book);
    String? newBook = book; int? newChapter = ch;
    if (ch < (chaptersList.isEmpty ? 1 : chaptersList.first)) {
      int idx = _books.indexOf(book);
      if (idx > 0) { newBook = _books[idx-1]; newChapter = (await _dbService.getChapters(newBook)).last; } else return;
    } else if (ch > (chaptersList.isEmpty ? 0 : chaptersList.last)) {
      int idx = _books.indexOf(book);
      if (idx < _books.length - 1) { newBook = _books[idx+1]; newChapter = 1; } else return;
    }
    final v = await _dbService.getChapter(newBook, newChapter!);
    final newChapters = await _dbService.getChapters(newBook);
    setState(() { _selectedBook = newBook; _chapters = newChapters; _selectedChapter = newChapter; _chapterVerses = v; });
    _tabController.animateTo(3);
  }

  void _jumpToLocation(String book, int ch, int v, BibleViewStyle style, {String? highlightPhrase, int? wordIndex}) async {
    final chapters = await _dbService.getChapters(book);
    final verses = await _dbService.getChapter(book, ch);
    setState(() { 
      _selectedBook = book; 
      _chapters = chapters; 
      _selectedChapter = ch; 
      _chapterVerses = verses; 
      _selectedVerse = v; 
      _selectedWordIndex = wordIndex;
      _currentStyle = style; 
      _isSearching = false; 
      _jumpHighlightPhrase = highlightPhrase; 
    });
    _tabController.animateTo(3);
  }

  void _showVerseSelector() async {
    String? tempBook = _books.first;
    int? tempChapter = 1;
    int? tempVerse = 1;
    List<int> tempChapters = await _dbService.getChapters(tempBook);
    List<BibleVerse> tempVerses = await _dbService.getChapter(tempBook, tempChapter);

    if (!mounted) return;
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Compare Specific Verse'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<String>(value: tempBook, isExpanded: true, items: _books.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(), onChanged: (b) async {
          final chs = await _dbService.getChapters(b!);
          final vrs = await _dbService.getChapter(b, chs.first);
          setDialogState(() { tempBook = b; tempChapters = chs; tempChapter = chs.first; tempVerses = vrs; tempVerse = 1; });
        }),
        DropdownButton<int>(value: tempChapter, isExpanded: true, items: tempChapters.map((c) => DropdownMenuItem(value: c, child: Text('Chapter $c'))).toList(), onChanged: (c) async {
          final vrs = await _dbService.getChapter(tempBook!, c!);
          setDialogState(() { tempChapter = c; tempVerses = vrs; tempVerse = 1; });
        }),
        DropdownButton<int>(value: tempVerse, isExpanded: true, items: tempVerses.map((v) => DropdownMenuItem(value: v.verse, child: Text('Verse ${v.verse}'))).toList(), onChanged: (v) => setDialogState(() => tempVerse = v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () async {
        final selectedVerseObj = tempVerses.firstWhere((v) => v.verse == tempVerse);
        setState(() { _dailyVerse = selectedVerseObj; });
        Navigator.pop(context);
      }, child: const Text('Compare'))],
    )));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([_initFuture, _dataFuture]),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Scaffold(body: Center(child: Text('Init Error: ${snapshot.error}')));
        if (snapshot.connectionState == ConnectionState.waiting || _dailyVerse == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        final dataResults = snapshot.data as List<dynamic>;
        final assetData = dataResults[1] as List<dynamic>;
        final Map<String, String> cont = Map<String, String>.from(assetData[0]);
        final Map<String, String> par = Map<String, String>.from(assetData[1]);

        final bool isMath = _currentStyle != BibleViewStyle.standard && _currentStyle != BibleViewStyle.superscript;

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 100,
            backgroundColor: isMath ? Colors.black : null,
            leading: Padding(padding: const EdgeInsets.all(12.0), child: Image.asset('assets/icon_foreground.png', fit: BoxFit.contain)),
            title: _isSearching 
              ? Row(children: [
                  Expanded(child: TextField(controller: _searchController, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Search Scripture...", border: InputBorder.none, hintStyle: TextStyle(color: Colors.white70)), onSubmitted: _handleSearch)),
                  IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () {
                    final phrase = _searchController.text;
                    final output = BibleLogic.formatInverseRelation(phrase, _searchResults.map((m) => m.location).toList());
                    Clipboard.setData(ClipboardData(text: output));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search relation copied')));
                  }),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Authorized King James Version 1611 PCE circa 1900', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), 
                  Text(_getVersionName(_currentStyle), style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  Text(_selectedBook != null ? "$_selectedBook ${_selectedChapter ?? ""}" : "", style: const TextStyle(fontSize: 10, color: Colors.white70)),
                ]),
            actions: [
              IconButton(icon: const Icon(Icons.home), onPressed: () => setState(() { _selectedBook = null; _selectedChapter = null; _selectedVerse = null; _isSearching = false; _tabController.animateTo(3); })),
              IconButton(icon: Icon(_isSearching ? Icons.close : Icons.search), onPressed: () => setState(() => _isSearching = !_isSearching)),
              IconButton(icon: const Icon(Icons.settings), onPressed: () => _showSettings(context)),
            ],
            bottom: TabBar(
              controller: _tabController, 
              isScrollable: true,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.amberAccent,
              indicatorWeight: 4,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
              tabs: [
                Tooltip(message: 'HEIGHT', child: Tab(text: _selectedBook ?? 'BOOK')), 
                Tooltip(message: 'DEPTH', child: Tab(text: _selectedChapter != null ? 'CH $_selectedChapter' : 'CHAPTER')), 
                Tooltip(message: 'LENGTH', child: Tab(text: _selectedVerse != null ? 'V $_selectedVerse' : 'VERSE')), 
                const Tooltip(message: 'BREADTH', child: Tab(text: 'BREADTH')),
                const Tab(text: 'STUDY HUB')
              ],
            ),
          ),
          body: _isSearching ? _buildSearchResults() : TabBarView(
            controller: _tabController,
            children: [
              _buildBookTab(),
              _selectedBook == null ? const Center(child: Text('Select Book')) : _buildChapterTab(),
              _selectedChapter == null ? const Center(child: Text('Select Chapter')) : _buildVerseGridTab(),
              _buildVerseTab(cont, par),
              StudyHubView(onJumpToLocation: (loc) => _handleSearch(loc)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_isLoadingSearch) return const Center(child: CircularProgressIndicator());
    if (_searchResults.isEmpty) return const Center(child: Text('No results found'));
    
    String headerText = BibleLogic.formatInverseRelation(_searchController.text, _searchResults.map((m) => m.location).toList());

    return Column(children: [
      Container(
        color: Colors.brown[50],
        padding: const EdgeInsets.all(8.0),
        child: Row(children: [
          Expanded(child: Text(headerText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black), overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.copy, size: 20, color: Colors.black), onPressed: () {
            Clipboard.setData(ClipboardData(text: headerText));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relation copied')));
          }),
        ]),
      ),
      Expanded(child: ListView.builder(
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final m = _searchResults[index];
          final query = _searchController.text.toLowerCase();
          
          return ListTile(
            title: Text(BibleLogic.formatInverseRelation(m.phrase, [m.location]), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: _buildHighlightedText(m.phrase, query),
            onTap: () {
              int? wordIdx;
              final locParts = m.location.split(':');
              if (locParts.length > 2) {
                final lastPart = locParts.last;
                wordIdx = int.tryParse(lastPart.split('-').first);
              }
              _jumpToLocation(m.verse.book, m.verse.chapter, m.verse.verse, _currentStyle, highlightPhrase: query, wordIndex: wordIdx);
            },
            trailing: IconButton(icon: const Icon(Icons.copy, size: 20), onPressed: () {
              final output = BibleLogic.formatPhraseFunction(m.phrase, m.location);
              Clipboard.setData(ClipboardData(text: output));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selection copied')));
            }),
          );
        },
      )),
    ]);
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) return Text(text);
    final List<TextSpan> spans = [];
    final lowerText = text.toLowerCase();
    
    int indexOfMatch = lowerText.indexOf(query.toLowerCase());
    if (indexOfMatch != -1) {
      if (indexOfMatch > 0) spans.add(TextSpan(text: text.substring(0, indexOfMatch)));
      spans.add(TextSpan(text: text.substring(indexOfMatch, indexOfMatch + query.length), style: const TextStyle(backgroundColor: Colors.orange, color: Colors.black, fontWeight: FontWeight.bold)));
      if (indexOfMatch + query.length < text.length) spans.add(TextSpan(text: text.substring(indexOfMatch + query.length)));
    } else {
      return Text(text);
    }

    return RichText(text: TextSpan(style: const TextStyle(color: Colors.grey), children: spans));
  }

  Widget _buildBookTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8.0), child: TextField(controller: _bookFilterController, decoration: const InputDecoration(hintText: 'Filter Books...', prefixIcon: Icon(Icons.filter_list), border: OutlineInputBorder()), onChanged: (v) => setState(() {}))),
      Expanded(child: ListView.builder(itemCount: _books.length, itemBuilder: (context, index) { if (_bookFilterController.text.isNotEmpty && !_books[index].toLowerCase().contains(_bookFilterController.text.toLowerCase())) return const SizedBox.shrink(); return ListTile(title: Text(_books[index]), selected: _selectedBook == _books[index], onTap: () => _onBookSelected(_books[index])); })),
    ]);
  }

  Widget _buildChapterTab() {
    return GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: _chapters.length, itemBuilder: (context, index) { return InkWell(onTap: () => _onChapterSelected(_chapters[index]), child: Container(decoration: BoxDecoration(color: _selectedChapter == _chapters[index] ? Colors.brown[300] : Colors.brown[100], borderRadius: BorderRadius.circular(4)), alignment: Alignment.center, child: Text('${_chapters[index]}'))); });
  }

  Widget _buildVerseGridTab() {
    final verses = _chapterVerses.map((v) => v.verse).toSet().toList()..sort();
    return GridView.builder(
      padding: const EdgeInsets.all(16), 
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 8, mainAxisSpacing: 8), 
      itemCount: verses.length, 
      itemBuilder: (context, index) { 
        return InkWell(
          onTap: () => _onVerseSelected(verses[index]), 
          child: Container(
            decoration: BoxDecoration(color: _selectedVerse == verses[index] ? Colors.brown[300] : Colors.brown[100], borderRadius: BorderRadius.circular(4)), 
            alignment: Alignment.center, 
            child: Text('${verses[index]}')
          )
        ); 
      }
    );
  }

  Widget _buildVerseTab(Map<String, String> cont, Map<String, String> par) {
    if (_selectedBook == null || _selectedChapter == null) return _buildWelcomePage(_dailyVerse!, cont, par);
    return BibleReaderView(bookName: _selectedBook!, chapter: _selectedChapter!, allVersesOfChapter: _chapterVerses, currentStyle: _currentStyle, continuityMap: cont, parenthesesMap: par, targetVerse: _selectedVerse, targetWordIndex: _selectedWordIndex, audioService: _audioService, isAudioEnabled: widget.isAudioEnabled, fontSize: widget.fontSize, isDarkMode: widget.isDarkMode, highlightPhrase: _jumpHighlightPhrase, onChapterChange: (ch) => _onChapterNavigate(_selectedBook!, ch));
  }

  Widget _buildWelcomePage(BibleVerse v, Map<String, String> cont, Map<String, String> par) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16.0), child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daily Bread', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.brown)),
            Text('${v.bookAbbreviation}${v.chapter}:${v.verse}:1-${v.wordCount}', 
                 style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
          ],
        ),
        ElevatedButton.icon(icon: const Icon(Icons.edit), label: const Text('Change Verse'), onPressed: _showVerseSelector),
      ]),
      const SizedBox(height: 20),
      _buildWelcomeSection('AKJV 1611 PCE circa 1900', Text(v.text, textAlign: TextAlign.center, style: TextStyle(fontSize: widget.fontSize, fontStyle: FontStyle.italic)), () => _jumpToLocation(v.book, v.chapter, v.verse, BibleViewStyle.standard)),
      _buildWelcomeSection('Superscript KJV', _buildArrayContent(v), () => _jumpToLocation(v.book, v.chapter, v.verse, BibleViewStyle.superscript)),
      _buildWelcomeSection('Mathematics KJV 1', _buildMathContent(v, cont, par, BibleViewStyle.mathematics), () => _jumpToLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematics)),
      _buildWelcomeSection('Mathematics KJV 2', _buildMathContent(v, cont, par, BibleViewStyle.mathematics2), () => _jumpToLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematics2)),
      _buildWelcomeSection('Mathematics KJV UNCONSTRAINT', _buildMathContent(v, cont, par, BibleViewStyle.mathematicsUnconstraint), () => _jumpToLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematicsUnconstraint)),
    ]));
  }

  Widget _buildMathContent(BibleVerse v, Map<String, String> cont, Map<String, String> par, BibleViewStyle style) {
    final words = BibleLogic.applyContinuity(v, cont, parenthesesMap: par, style: style);
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(8.0),
      child: Wrap(alignment: WrapAlignment.center, children: words.map((mw) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: RichText(text: TextSpan(children: [
        if (mw.hasLeadingSpace) const TextSpan(text: ' '),
        ...mw.parts.map((p) => TextSpan(text: p.text, style: TextStyle(
          color: p.isRed ? Colors.redAccent : Colors.white, 
          fontSize: widget.fontSize, 
          fontWeight: FontWeight.bold,
          fontFamily: 'Roboto',
          shadows: [
            Shadow(
              blurRadius: 2.0,
              color: p.isRed ? Colors.red : Colors.blueAccent,
              offset: const Offset(0, 0),
            ),
            Shadow(
              blurRadius: 10.0,
              color: p.isRed ? Colors.red : Colors.blueAccent,
              offset: const Offset(0, 0),
            ),
            Shadow(
              blurRadius: 25.0,
              color: p.isRed ? Colors.red.withOpacity(0.5) : Colors.blueAccent.withOpacity(0.5),
              offset: const Offset(0, 0),
            ),
          ],
        )))
      ])))).toList()),
    );
  }

  Widget _buildArrayContent(BibleVerse v) {
    return Wrap(alignment: WrapAlignment.center, children: v.styledWords.map((w) => RichText(text: TextSpan(children: [
      TextSpan(text: '${w.text}', style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black, fontSize: widget.fontSize, fontStyle: w.isItalic ? FontStyle.italic : FontStyle.normal)),
      WidgetSpan(child: Transform.translate(offset: const Offset(0, -10), child: Text('${w.index}', style: TextStyle(fontSize: widget.fontSize * 0.6, color: Colors.blue, fontWeight: FontWeight.bold)))),
      const TextSpan(text: ' '),
    ]))).toList());
  }

  Widget _buildWelcomeSection(String title, Widget content, VoidCallback onTap) { return Column(children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), InkWell(onTap: onTap, child: Card(elevation: 4, child: Padding(padding: const EdgeInsets.all(16.0), child: content))), const SizedBox(height: 15)]); }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              height: 4,
              width: 40,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const ListTile(title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20))),
            const Divider(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    title: const Text('View Style'),
                    trailing: DropdownButton<BibleViewStyle>(
                      value: _currentStyle,
                      items: const [
                        DropdownMenuItem(value: BibleViewStyle.standard, child: Text('AKJV 1611 PCE')),
                        DropdownMenuItem(value: BibleViewStyle.superscript, child: Text('Superscript KJV')),
                        DropdownMenuItem(value: BibleViewStyle.mathematics, child: Text('Mathematics KJV 1')),
                        DropdownMenuItem(value: BibleViewStyle.mathematics2, child: Text('Mathematics KJV 2')),
                        DropdownMenuItem(value: BibleViewStyle.mathematicsUnconstraint, child: Text('Math KJV UNCONSTRAINT')),
                      ],
                      onChanged: (s) { setState(() => _currentStyle = s!); Navigator.pop(context); }
                    ),
                  ),
                  SwitchListTile(title: const Text('Night Theme'), value: widget.isDarkMode, onChanged: (v) { widget.onThemeChanged(v); Navigator.pop(context); }),
                  SwitchListTile(title: const Text('Enable Voice (Audio)'), value: widget.isAudioEnabled, onChanged: (v) { widget.onAudioChanged(v); Navigator.pop(context); }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        const Text('Font Size'),
                        Expanded(
                          child: Slider(
                            value: widget.fontSize,
                            min: 12,
                            max: 40,
                            divisions: 28,
                            label: widget.fontSize.round().toString(),
                            onChanged: (v) => widget.onFontSizeChanged(v),
                          ),
                        ),
                        Text(widget.fontSize.round().toString()),
                      ],
                    ),
                  ),
                  const Divider(),
                  ListTile(leading: const Icon(Icons.code), title: const Text('Technical Overview'), onTap: () => _showDocDialog(context, 'Technical Overview', 'README.md')),
                  ListTile(leading: const Icon(Icons.menu_book), title: const Text('User Guide'), onTap: () => _showDocDialog(context, 'User Guide', 'assets/MANUAL.md')),
                  ListTile(leading: const Icon(Icons.help_outline), title: const Text('Instruction Manual'), onTap: () => _showDocDialog(context, 'Instruction Manual', 'assets/HELP.md')),
                  ListTile(leading: const Icon(Icons.gavel), title: const Text('No-Warranty Agreement'), onTap: () => _showDocDialog(context, 'No-Warranty Agreement', 'assets/NO_WARRANTY_AGREEMENT.md')),
                  ListTile(leading: const Icon(Icons.info_outline), title: const Text('About'), onTap: () => _showAboutDialog(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDocDialog(BuildContext context, String title, String assetPath) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: FutureBuilder<String>(
          future: rootBundle.loadString(assetPath),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            return SingleChildScrollView(child: Text(snapshot.data!));
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text('About'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Authors: Carrille Dione and Charles Eyum Sama', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Email: holybiblemobileapp@gmail.com'),
          SizedBox(height: 16),
          Text('License: © No Rights Reserved', style: TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }
}
