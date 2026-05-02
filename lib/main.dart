import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'database_service.dart';
import 'bible_model.dart';
import 'bible_logic.dart';
import 'audio_service.dart';
import 'study_hub_view.dart';
import 'bible_reader_view.dart';
import 'verse_selector_dialog.dart';

enum AppTheme { system, light, dark, midnight, warmer }
enum AppFont { system, serif, sansSerif, monospace }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HolyBibleApp());
}

class HolyBibleApp extends StatefulWidget {
  const HolyBibleApp({super.key});
  @override
  State<HolyBibleApp> createState() => _HolyBibleAppState();
}

class _HolyBibleAppState extends State<HolyBibleApp> {
  AppTheme _selectedTheme = AppTheme.system;
  AppFont _selectedFont = AppFont.system;
  bool _isAudioEnabled = true;
  double _fontSize = 18.0;
  AudioQuality _audioQuality = AudioQuality.high;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedTheme = AppTheme.values[prefs.getInt('appTheme') ?? 0];
      _selectedFont = AppFont.values[prefs.getInt('appFont') ?? 0];
      _isAudioEnabled = prefs.getBool('audioEnabled') ?? true;
      _fontSize = prefs.getDouble('fontSize') ?? 18.0;
      final qualityIndex = prefs.getInt('audioQuality') ?? 0;
      _audioQuality = AudioQuality.values[qualityIndex.clamp(0, AudioQuality.values.length - 1)];
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) await prefs.setInt(key, value);
    else if (value is bool) await prefs.setBool(key, value);
    else if (value is double) await prefs.setDouble(key, value);
  }

  ThemeData _getTheme(bool isDark) {
    Color scaffoldBg;
    ColorScheme colorScheme;

    switch (_selectedTheme) {
      case AppTheme.midnight:
        scaffoldBg = Colors.black;
        colorScheme = ColorScheme.fromSeed(seedColor: Colors.brown, brightness: Brightness.dark, background: Colors.black);
        break;
      case AppTheme.warmer:
        scaffoldBg = const Color(0xFFF4ECD8);
        colorScheme = ColorScheme.fromSeed(seedColor: Colors.brown, brightness: Brightness.light, background: const Color(0xFFF4ECD8));
        break;
      case AppTheme.light:
        scaffoldBg = Colors.white;
        colorScheme = ColorScheme.fromSeed(seedColor: Colors.brown, brightness: Brightness.light, background: Colors.white);
        break;
      case AppTheme.dark:
        scaffoldBg = const Color(0xFF1A1A1A);
        colorScheme = ColorScheme.fromSeed(seedColor: Colors.brown, brightness: Brightness.dark);
        break;
      case AppTheme.system:
        scaffoldBg = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFDFCF8);
        colorScheme = ColorScheme.fromSeed(seedColor: Colors.brown, brightness: isDark ? Brightness.dark : Brightness.light);
        break;
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: _getTextTheme(colorScheme.brightness),
      appBarTheme: AppBarTheme(backgroundColor: colorScheme.surfaceVariant.withOpacity(0.5), centerTitle: true),
    );
  }

  TextTheme _getTextTheme(Brightness brightness) {
    final base = brightness == Brightness.dark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final baseStyle = _selectedFont == AppFont.serif ? GoogleFonts.crimsonPro() : (_selectedFont == AppFont.monospace ? GoogleFonts.sourceCodePro() : GoogleFonts.inter());
    return GoogleFonts.getTextTheme(_selectedFont == AppFont.system ? 'Roboto' : baseStyle.fontFamily!, base);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Holy Bible 4-Vector',
      debugShowCheckedModeBanner: false,
      theme: _getTheme(false),
      darkTheme: _getTheme(true),
      themeMode: _selectedTheme == AppTheme.light || _selectedTheme == AppTheme.warmer ? ThemeMode.light : (_selectedTheme == AppTheme.dark || _selectedTheme == AppTheme.midnight ? ThemeMode.dark : ThemeMode.system),
      home: MainNavigation(
        selectedTheme: _selectedTheme,
        selectedFont: _selectedFont,
        isAudioEnabled: _isAudioEnabled,
        fontSize: _fontSize,
        audioQuality: _audioQuality,
        onThemeChanged: (t) { setState(() => _selectedTheme = t); _saveSetting('appTheme', t.index); },
        onFontChanged: (f) { setState(() => _selectedFont = f); _saveSetting('appFont', f.index); },
        onAudioChanged: (v) { setState(() => _isAudioEnabled = v); _saveSetting('audioEnabled', v); },
        onFontSizeChanged: (v) { setState(() => _fontSize = v); _saveSetting('fontSize', v); },
        onAudioQualityChanged: (q) { setState(() => _audioQuality = q); _saveSetting('audioQuality', q.index); },
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final AppTheme selectedTheme;
  final AppFont selectedFont;
  final bool isAudioEnabled;
  final double fontSize;
  final AudioQuality audioQuality;
  final Function(AppTheme) onThemeChanged;
  final Function(AppFont) onFontChanged;
  final Function(bool) onAudioChanged;
  final Function(double) onFontSizeChanged;
  final Function(AudioQuality) onAudioQualityChanged;

  const MainNavigation({
    super.key,
    required this.selectedTheme,
    required this.selectedFont,
    required this.isAudioEnabled,
    required this.fontSize,
    required this.audioQuality,
    required this.onThemeChanged,
    required this.onFontChanged,
    required this.onAudioChanged,
    required this.onFontSizeChanged,
    required this.onAudioQualityChanged,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  String? _selectedBook;
  int? _selectedChapter;
  int? _selectedVerse;
  int? _selectedWordIndex;
  String? _jumpHighlightPhrase;

  List<String> _books = [];
  List<int> _chapters = [];
  List<BibleVerse> _chapterVerses = [];
  BibleViewStyle _currentStyle = BibleViewStyle.standard;
  BibleVerse? _dailyVerse;
  bool _isDbInitializing = true;
  
  // Persistent Search State
  String? _cachedSearchQuery;
  List<BibleMatch>? _cachedSearchResults;
  final TextEditingController _homeFilterController = TextEditingController();
  final ValueNotifier<String> _homeFilterNotifier = ValueNotifier("");

  final DatabaseService _db = DatabaseService();
  final AudioService _audioService = AudioService();
  final TextEditingController _bookFilterController = TextEditingController();

  Map<String, String> _continuityMap = {};
  Map<String, String> _parenthesesMap = {};

  late TabController _bibleTabController;

  @override
  void initState() {
    super.initState();
    _bibleTabController = TabController(length: 4, vsync: this);
    _initData();
  }

  @override
  void dispose() {
    _bibleTabController.dispose();
    _bookFilterController.dispose();
    _homeFilterController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isDbInitializing = true);
    await _db.initialize();
    BibleLogic.clearCache();
    final prefs = await SharedPreferences.getInstance();
    final books = await _db.getBooks();
    final daily = await _db.getDailyVerse();
    final cont = await _db.getContinuityMap();
    final par = await _db.getParenthesesMap();
    
    // Restore Search Cache
    _cachedSearchQuery = prefs.getString('cachedSearchQuery');
    final cachedJson = prefs.getString('cachedSearchResults');
    if (cachedJson != null) {
      try {
        final List<dynamic> list = json.decode(cachedJson);
        _cachedSearchResults = list.map((m) => BibleMatch.fromJson(m)).toList();
      } catch (e) {
        debugPrint("Error restoring search cache: $e");
      }
    }

    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {
      _books = books;
      _dailyVerse = daily;
      _continuityMap = cont;
      _parenthesesMap = par;
      _currentStyle = BibleViewStyle.values[prefs.getInt('bibleStyle') ?? 0];
      _isDbInitializing = false;
    });
  }

  Future<void> _saveStyle(BibleViewStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bibleStyle', style.index);
    setState(() => _currentStyle = style);
  }

  Future<void> _saveSearchCache(String? query, List<BibleMatch>? results) async {
    final prefs = await SharedPreferences.getInstance();
    if (query == null || results == null) {
      await prefs.remove('cachedSearchQuery');
      await prefs.remove('cachedSearchResults');
    } else {
      await prefs.setString('cachedSearchQuery', query);
      await prefs.setString('cachedSearchResults', json.encode(results.map((m) => m.toJson()).toList()));
    }
    setState(() {
      _cachedSearchQuery = query;
      _cachedSearchResults = results;
    });
  }

  Future<void> _onBookSelected(String book) async {
    final chapters = await _db.getChapters(book);
    setState(() { _selectedBook = book; _chapters = chapters; _selectedChapter = null; _selectedVerse = null; });
    _bibleTabController.animateTo(1); // Go to chapters
  }

  Future<void> _onChapterSelected(int chapter, {bool animateToVerseGrid = true}) async {
    final verses = await _db.getChapter(_selectedBook!, chapter);
    setState(() { _selectedChapter = chapter; _chapterVerses = verses; _selectedVerse = null; });
    if (animateToVerseGrid) _bibleTabController.animateTo(2); // Go to verses
  }

  void _onVerseSelected(int verse) {
    setState(() {
      _selectedVerse = verse;
      _dailyVerse = _chapterVerses.firstWhere((v) => v.verse == verse);
    });
    _bibleTabController.animateTo(3); // Go to Read
  }

  void _onChapterNavigate(int direction) async {
    if (_selectedBook == null || _selectedChapter == null) return;
    int currentIndex = _chapters.indexOf(_selectedChapter!);
    int newIndex = currentIndex + direction;
    if (newIndex >= 0 && newIndex < _chapters.length) {
      final nextChapter = _chapters[newIndex];
      final verses = await _db.getChapter(_selectedBook!, nextChapter);
      setState(() { _selectedChapter = nextChapter; _chapterVerses = verses; _selectedVerse = null; _dailyVerse = verses.first; });
    } else {
      int bookIndex = _books.indexOf(_selectedBook!);
      int targetBookIndex = bookIndex + direction;
      if (targetBookIndex >= 0 && targetBookIndex < _books.length) {
        String targetBook = _books[targetBookIndex];
        final targetChapters = await _db.getChapters(targetBook);
        int targetChapter = (direction > 0) ? targetChapters.first : targetChapters.last;
        final verses = await _db.getChapter(targetBook, targetChapter);
        setState(() { _selectedBook = targetBook; _chapters = targetChapters; _selectedChapter = targetChapter; _chapterVerses = verses; _selectedVerse = null; _dailyVerse = verses.first; });
      }
    }
  }

  void _jumpToLocation(String loc, {String? highlight}) async {
    final bibleLoc = BibleLogic.parseLocation(loc);
    if (bibleLoc == null) return;
    final bookName = _books.firstWhere((b) => b.toLowerCase().startsWith(bibleLoc.bookAbbr.toLowerCase()), orElse: () => _books.first);
    final chapters = await _db.getChapters(bookName);
    final verses = await _db.getChapter(bookName, bibleLoc.chapter);
    final newDaily = verses.firstWhere((v) => v.verse == bibleLoc.verse, orElse: () => verses.first);
    
    setState(() {
      _selectedBook = bookName;
      _chapters = chapters;
      _selectedChapter = bibleLoc.chapter;
      _chapterVerses = verses;
      _selectedVerse = bibleLoc.verse;
      _selectedWordIndex = bibleLoc.startWord;
      _jumpHighlightPhrase = highlight;
      _dailyVerse = newDaily;
      _selectedIndex = 1;
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bibleTabController.animateTo(3);
    });
  }

  void _handleSearch() async {
    final result = await showSearch<BibleMatch?>(
      context: context, 
      delegate: BibleSearchDelegate(
        _db, 
        initialQuery: _cachedSearchQuery,
        initialResults: _cachedSearchResults,
        onCacheUpdate: (q, results) => _saveSearchCache(q, results)
      )
    );
    if (result != null) {
      _jumpToLocation(result.location, highlight: result.phrase);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDbInitializing) return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [SvgPicture.asset('assets/IGoToTheFather.svg', width: 220, height: 220), const SizedBox(height: 32), const Text("Initializing Bible Vector Space...", style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.brown)), const SizedBox(height: 16), const CircularProgressIndicator(strokeWidth: 2, color: Colors.brown)])));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Authorized King James Version 1611 Pure Cambridge Edition circa 1900", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Colors.brown), onPressed: _handleSearch),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.brown), onPressed: () => setState(() { _initData(); })),
          DropdownButton<BibleViewStyle>(
            value: _currentStyle, 
            underline: const SizedBox(), 
            icon: const Icon(Icons.style, color: Colors.brown), 
            items: BibleViewStyle.values.map((s) => DropdownMenuItem(value: s, child: Text(BibleLogic.getReadingLabel(s), style: const TextStyle(fontSize: 12)))).toList(), 
            onChanged: (s) => _saveStyle(s!)
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _dailyVerse == null ? const Center(child: Text("Loading...")) : _buildWelcomePage(_dailyVerse!),
          _buildBibleNavigator(),
          StudyHubView(onJumpToLocation: _jumpToLocation, currentStyle: _currentStyle, continuityMap: _continuityMap, parenthesesMap: _parenthesesMap, fontSize: widget.fontSize, isDarkMode: widget.selectedTheme == AppTheme.midnight),
          _buildSettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex, 
        onDestinationSelected: (i) => setState(() => _selectedIndex = i), 
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'), 
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Bible'), 
          NavigationDestination(icon: Icon(Icons.science), label: 'Study Hub'), 
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings')
        ]
      ),
    );
  }

  Widget _buildBibleNavigator() {
    return Column(children: [
      TabBar(
        controller: _bibleTabController, 
        isScrollable: false, 
        labelColor: Colors.brown, 
        unselectedLabelColor: Colors.grey, 
        labelPadding: EdgeInsets.zero,
        tabs: const [
          Tooltip(message: "HEIGHT", child: Tab(text: "BOOK")),
          Tooltip(message: "DEPTH", child: Tab(text: "CHAPTER")),
          Tooltip(message: "LENGTH", child: Tab(text: "VERSE")),
          Tooltip(message: "BREADTH", child: Tab(text: "READ")),
        ]
      ), 
      Expanded(child: TabBarView(controller: _bibleTabController, children: [ _buildBookTab(), _buildChapterTab(), _buildVerseGridTab(), _buildVerseTab() ]))
    ]);
  }

  Widget _buildBookTab() { return Column(children: [Padding(padding: const EdgeInsets.all(8.0), child: TextField(controller: _bookFilterController, decoration: const InputDecoration(hintText: 'Filter Books...', prefixIcon: Icon(Icons.filter_list), border: OutlineInputBorder()), onChanged: (v) => setState(() {}))), Expanded(child: ListView.builder(itemCount: _books.length, itemBuilder: (context, index) { if (_bookFilterController.text.isNotEmpty && !_books[index].toLowerCase().contains(_bookFilterController.text.toLowerCase())) return const SizedBox.shrink(); return ListTile(title: Text(_books[index]), selected: _selectedBook == _books[index], onTap: () => _onBookSelected(_books[index])); }))]); }
  Widget _buildChapterTab() { if (_selectedBook == null) return const Center(child: Text("Select a Book first (HEIGHT)")); return GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: _chapters.length, itemBuilder: (context, index) { return InkWell(onTap: () => _onChapterSelected(_chapters[index]), child: Container(decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), alignment: Alignment.center, child: Text('${_chapters[index]}'))); }); }
  Widget _buildVerseGridTab() { if (_selectedChapter == null) return const Center(child: Text("Select a Chapter first (DEPTH)")); final verses = _chapterVerses.map((v) => v.verse).toSet().toList()..sort(); return GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: verses.length, itemBuilder: (context, index) { return InkWell(onTap: () => _onVerseSelected(verses[index]), child: Container(decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), alignment: Alignment.center, child: Text('${verses[index]}'))); }); }
  Widget _buildVerseTab() { 
    if (_selectedBook == null || _selectedChapter == null) return const Center(child: Text("Navigation required (HEIGHT > DEPTH > LENGTH)")); 
    return BibleReaderView(
      bookName: _selectedBook!, 
      chapter: _selectedChapter!, 
      allVersesOfChapter: _chapterVerses, 
      currentStyle: _currentStyle, 
      continuityMap: _continuityMap, 
      parenthesesMap: _parenthesesMap, 
      targetVerse: _selectedVerse, 
      targetWordIndex: _selectedWordIndex, 
      audioService: _audioService, 
      isAudioEnabled: widget.isAudioEnabled, 
      fontSize: widget.fontSize, 
      isDarkMode: widget.selectedTheme == AppTheme.midnight, 
      highlightPhrase: _jumpHighlightPhrase, 
      onChapterChange: (direction) => _onChapterNavigate(direction), 
      onFontSizeChanged: widget.onFontSizeChanged, 
      onAudioChanged: widget.onAudioChanged,
      onStyleChanged: (s) => _saveStyle(s),
    );
  }

  Widget _buildWelcomePage(BibleVerse v) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16.0), child: Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Image.asset('assets/IGoToTheFather1B.PNG', height: 80), const SizedBox(width: 15), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Daily Bread', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.brown), onPressed: () async { 
        final r = await showDialog<Map<String, dynamic>>(context: context, builder: (c) => const VerseSelectorDialog()); 
        if (r != null) { 
          final specificVerse = await _db.getSpecificVerse(r['book'], r['chapter'], r['verse']);
          if (specificVerse != null) {
            setState(() => _dailyVerse = specificVerse);
          }
        } 
      }, tooltip: "Change Verse")]), Text('${v.bookAbbreviation}${v.chapter}:${v.verse}:1-${v.wordCount}', style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500))]))]),
      const SizedBox(height: 24),
      if (_cachedSearchResults != null) _buildHomeSearchResultsSection(),
      const SizedBox(height: 24),
      const Text("how readest thou?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.brown)),
      const SizedBox(height: 16),
      InkWell(onTap: () => _jumpToLocation("${v.bookAbbreviation}${v.chapter}:${v.verse}"), child: Column(children: [
        _buildComparisonRow(BibleLogic.getReadingLabel(BibleViewStyle.standard), v, _continuityMap, _parenthesesMap, BibleViewStyle.standard),
        _buildComparisonRow(BibleLogic.getReadingLabel(BibleViewStyle.superscript), v, _continuityMap, _parenthesesMap, BibleViewStyle.superscript),
        _buildComparisonRow(BibleLogic.getReadingLabel(BibleViewStyle.mathematics), v, _continuityMap, _parenthesesMap, BibleViewStyle.mathematics),
        _buildComparisonRow(BibleLogic.getReadingLabel(BibleViewStyle.mathematics2), v, _continuityMap, _parenthesesMap, BibleViewStyle.mathematics2),
        _buildComparisonRow(BibleLogic.getReadingLabel(BibleViewStyle.mathematicsUnconstraint), v, _continuityMap, _parenthesesMap, BibleViewStyle.mathematicsUnconstraint),
      ])),
    ]));
  }

  Widget _buildHomeSearchResultsSection() {
    if (_cachedSearchResults == null || _cachedSearchResults!.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<String>(
          valueListenable: _homeFilterNotifier,
          builder: (context, filter, _) {
            final filtered = _cachedSearchResults!.where((m) => 
              m.phrase.toLowerCase().contains(filter.toLowerCase()) || 
              m.location.toLowerCase().contains(filter.toLowerCase())
            ).toList();
            
            final summary = BibleLogic.formatInverseRelation(_cachedSearchQuery ?? "", filtered);

            return Column(
              children: [
                Container(
                  width: double.maxFinite, 
                  padding: const EdgeInsets.all(12), 
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(color: Colors.brown[50], borderRadius: BorderRadius.circular(4)),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(child: SelectableText(summary, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.brown))),
                        IconButton(icon: const Icon(Icons.copy_all, size: 20), onPressed: () {
                          Clipboard.setData(ClipboardData(text: summary));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Inverse Relation copied"), duration: Duration(seconds: 1)));
                        }),
                        IconButton(icon: const Icon(Icons.clear), onPressed: () => _saveSearchCache(null, null)),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _homeFilterController,
                        decoration: const InputDecoration(
                          hintText: "Filter output from Inverse Relation...",
                          isDense: true,
                          prefixIcon: Icon(Icons.filter_list, size: 16),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        style: const TextStyle(fontSize: 12),
                        onChanged: (v) => _homeFilterNotifier.value = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 300, 
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final m = filtered[index];
                      return SearchResultTile(m: m, onJump: (loc, highlight) => _jumpToLocation(loc, highlight: highlight));
                    },
                  ),
                ),
              ],
            );
          }
        ),
      ],
    );
  }

  Widget _buildComparisonRow(String title, BibleVerse v, Map<String, String> cont, Map<String, String> par, BibleViewStyle style) {
    final bool isMath = style != BibleViewStyle.standard && style != BibleViewStyle.superscript;
    return Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isMath ? Colors.black : Colors.brown[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.brown[100]!)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isMath ? Colors.white70 : Colors.brown)), const SizedBox(height: 8), Wrap(children: BibleLogic.applyContinuity(v, cont, parenthesesMap: par, style: style).map((mw) => _renderComparisonWord(v, mw, style)).toList())]));
  }

  Widget _renderComparisonWord(BibleVerse v, MathWord mw, BibleViewStyle style) {
    final bool isMath = style != BibleViewStyle.standard && style != BibleViewStyle.superscript;
    final bool isSuperscript = style == BibleViewStyle.superscript;
    final bool isMidnight = widget.selectedTheme == AppTheme.midnight;
    final symbolColor = BibleLogic.getMathSymbolColor(style);
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: RichText(text: TextSpan(children: [
      if (mw.hasLeadingSpace) const TextSpan(text: ' '),
      ...mw.parts.map((p) {
        if (isSuperscript && !p.isParenthesis) {
          return TextSpan(children: [
            TextSpan(text: p.text, style: TextStyle(color: isMath || isMidnight ? Colors.white : Colors.black87, fontSize: widget.fontSize * 0.85, fontStyle: p.isItalic ? FontStyle.italic : FontStyle.normal)),
            WidgetSpan(child: Transform.translate(offset: const Offset(0, -8), child: Text('${mw.original.index}', style: TextStyle(fontSize: widget.fontSize * 0.35, color: Colors.blue, fontWeight: FontWeight.bold)))),
          ]);
        }
        return TextSpan(text: p.text, style: TextStyle(color: p.isRed ? symbolColor : (isMath || isMidnight ? Colors.white : Colors.black87), fontSize: widget.fontSize * 0.85, fontWeight: p.isRed ? FontWeight.bold : FontWeight.normal, fontStyle: p.isItalic ? FontStyle.italic : FontStyle.normal, fontFamily: isMath ? 'Courier' : null));
      })
    ])));
  }

  Widget _buildSettingsTab() { 
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text("Appearance", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown)),
      const SizedBox(height: 16),
      ListTile(title: const Text("Theme Mode"), trailing: DropdownButton<AppTheme>(value: widget.selectedTheme, items: AppTheme.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()))).toList(), onChanged: (t) => widget.onThemeChanged(t!))),
      ListTile(title: const Text("App Font"), trailing: DropdownButton<AppFont>(value: widget.selectedFont, items: AppFont.values.map((f) => DropdownMenuItem(value: f, child: Text(f.name.toUpperCase()))).toList(), onChanged: (f) => widget.onFontChanged(f!))),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Font Size: ${widget.fontSize.toInt()}", style: const TextStyle(fontWeight: FontWeight.w500)),
            Slider(min: 12, max: 32, divisions: 20, value: widget.fontSize, onChanged: (v) => widget.onFontSizeChanged(v)),
          ],
        ),
      ),
      const Divider(),
      const Text("Audio Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown)),
      SwitchListTile(title: const Text("Enable Audio Sync"), subtitle: const Text("Highlights words during playback"), value: widget.isAudioEnabled, onChanged: widget.onAudioChanged),
      ListTile(title: const Text("Voice Quality"), trailing: DropdownButton<AudioQuality>(value: widget.audioQuality, items: AudioQuality.values.map((q) => DropdownMenuItem(value: q, child: Text(q.name.toUpperCase()))).toList(), onChanged: (q) => widget.onAudioQualityChanged(q!))),
      const Divider(),
      const Text("BVS Analysis Support", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown)),
      const SizedBox(height: 8),
      ListTile(leading: const Icon(Icons.info_outline, color: Colors.brown), title: const Text("Technical Overview"), subtitle: const Text("BVS Pedagogy and Roadmap"), onTap: () => _showMarkdownDialog("Technical Overview", "assets/MANUAL.md")),
      ListTile(leading: const Icon(Icons.menu_book, color: Colors.brown), title: const Text("Instruction Manual"), subtitle: const Text("Understanding the 4-Vector Logic"), onTap: () => _showMarkdownDialog("Instruction Manual", "assets/MANUAL.md")),
      ListTile(leading: const Icon(Icons.gavel, color: Colors.brown), title: const Text("No-Warranty Agreement"), subtitle: const Text("Legal Terms and Conditions"), onTap: () => _showMarkdownDialog("License", "assets/NO_WARRANTY_AGREEMENT.md")),
      ListTile(leading: const Icon(Icons.auto_awesome, color: Colors.brown), title: const Text("About this App"), subtitle: const Text("Charles Eyum Sama | BVS-2024"), onTap: () => _showAssetDialog("About BVS", "assets/HELP.md")),
    ]); 
  }

  void _showAssetDialog(String title, String assetPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Tortpotlord Teaching Assistant", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            const Text("The following is an automated curriculum evaluation generated by the BVS engine.", style: TextStyle(fontSize: 12)),
            const Divider(height: 24),
            SizedBox(
              height: 400,
              width: double.maxFinite,
              child: FutureBuilder<String>(
                future: rootBundle.loadString(assetPath),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  return Markdown(
                    data: snapshot.data!,
                    extensionSet: md.ExtensionSet(
                      md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                      [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexSyntax(), InlineLatexSyntax(), PhraseSyntax()],
                    ),
                    builders: {
                      'latex': LatexBuilder(currentStyle: _currentStyle, continuityMap: _continuityMap, parenthesesMap: _parenthesesMap, isDarkMode: widget.selectedTheme == AppTheme.midnight),
                      'inlineLatex': InlineLatexBuilder(currentStyle: _currentStyle, continuityMap: _continuityMap, parenthesesMap: _parenthesesMap, isDarkMode: widget.selectedTheme == AppTheme.midnight),
                      'phrase': PhraseBuilder(currentStyle: _currentStyle, continuityMap: _continuityMap, parenthesesMap: _parenthesesMap, isDarkMode: widget.selectedTheme == AppTheme.midnight),
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text("All correspondence is handled by the Tortpotlord AI Assistant. Please 'Trust but Verify' all outputs against the Source Text.", style: TextStyle(fontSize: 11, color: Colors.brown)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
      ),
    );
  }

  void _showMarkdownDialog(String title, String assetPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<String>(
            future: rootBundle.loadString(assetPath),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return Markdown(
                data: snapshot.data!,
                physics: const BouncingScrollPhysics(),
                extensionSet: md.ExtensionSet(
                  md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                  [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, LatexSyntax(), InlineLatexSyntax(), PhraseSyntax()],
                ),
                builders: { 
                  'latex': LatexBuilder(currentStyle: _currentStyle, continuityMap: _continuityMap, parenthesesMap: _parenthesesMap, isDarkMode: widget.selectedTheme == AppTheme.midnight),
                  'inlineLatex': InlineLatexBuilder(currentStyle: _currentStyle, continuityMap: _continuityMap, parenthesesMap: _parenthesesMap, isDarkMode: widget.selectedTheme == AppTheme.midnight),
                  'phrase': PhraseBuilder(currentStyle: _currentStyle, continuityMap: _continuityMap, parenthesesMap: _parenthesesMap, isDarkMode: widget.selectedTheme == AppTheme.midnight),
                },
                styleSheet: MarkdownStyleSheet(
                  h1: TextStyle(color: Colors.brown, fontSize: widget.fontSize * 1.2),
                  h2: TextStyle(color: Colors.blueGrey, fontSize: widget.fontSize),
                  p: TextStyle(fontSize: widget.fontSize * 0.8, height: 1.5),
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
      ),
    );
  }
}

class SearchResultTile extends StatelessWidget {
  final BibleMatch m;
  final Function(String, String) onJump;
  const SearchResultTile({super.key, required this.m, required this.onJump});

  @override
  Widget build(BuildContext context) {
    final List<BibleVerse> verses = [m.verse, ...m.extraVerses];
    final String fullCopy = "${m.phrase}(${m.location})";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onJump(m.location, m.phrase),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: verses.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final v = entry.value;
                      final String highlightPart = (m.phraseSegments.length > idx) ? m.phraseSegments[idx] : m.phrase;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 13), children: BibleLogic.highlightText(v.text, highlightPart))),
                            Text("${v.bookAbbreviation}${v.chapter}:${v.verse}:1-${v.wordCount}", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.content_copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: fullCopy));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied: $fullCopy"), duration: const Duration(seconds: 1)));
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class BibleSearchDelegate extends SearchDelegate<BibleMatch?> {
  final DatabaseService db;
  final String? initialQuery;
  final List<BibleMatch>? initialResults;
  final Function(String?, List<BibleMatch>?) onCacheUpdate;
  
  final TextEditingController _localFilterController = TextEditingController();
  final ValueNotifier<String> _filterNotifier = ValueNotifier("");

  BibleSearchDelegate(this.db, {this.initialQuery, this.initialResults, required this.onCacheUpdate}) {
    if (initialQuery != null) query = initialQuery!;
  }

  @override String get searchFieldLabel => "Enter Phrase or Location";
  @override List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () { query = ''; onCacheUpdate(null, null); }),
  ];
  @override Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  
  @override Widget buildResults(BuildContext context) {
    return FutureBuilder<List<BibleMatch>>(
      future: db.search(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No results found."));
        onCacheUpdate(query, snapshot.data);
        return _buildResultList(context, snapshot.data!);
      },
    );
  }

  Widget _buildResultList(BuildContext context, List<BibleMatch> results) {
    return Column(children: [
      ValueListenableBuilder<String>(
        valueListenable: _filterNotifier,
        builder: (context, filter, _) {
          final filtered = results.where((m) => 
            m.phrase.toLowerCase().contains(filter.toLowerCase()) || 
            m.location.toLowerCase().contains(filter.toLowerCase())
          ).toList();
          final summary = BibleLogic.formatInverseRelation(query, filtered);

          return Container(
            width: double.maxFinite, 
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
            color: Colors.brown[50], 
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: SelectableText(summary, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.brown))), 
                  IconButton(icon: const Icon(Icons.copy_all, size: 20), onPressed: () { 
                    Clipboard.setData(ClipboardData(text: summary)); 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Inverse Relation copied"), duration: Duration(seconds: 1)));
                  })
                ]),
                const SizedBox(height: 4),
                TextField(
                  controller: _localFilterController,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Filter results...',
                    prefixIcon: Icon(Icons.filter_list, size: 16),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) => _filterNotifier.value = v,
                ),
              ],
            )
          );
        }
      ),
      Expanded(
        child: ValueListenableBuilder<String>(
          valueListenable: _filterNotifier,
          builder: (context, filter, _) {
            final filteredResults = results.where((m) => 
              m.phrase.toLowerCase().contains(filter.toLowerCase()) || 
              m.location.toLowerCase().contains(filter.toLowerCase())
            ).toList();

            return ListView.builder(
              itemCount: filteredResults.length, 
              itemBuilder: (context, index) {
                final m = filteredResults[index];
                return SearchResultTile(m: m, onJump: (loc, highlight) => close(context, m));
              }
            );
          }
        )
      )
    ]);
  }

  @override Widget buildSuggestions(BuildContext context) { 
    if (query.length < 2) return const Center(child: Text("Search Phrases...")); 
    return buildResults(context); 
  }
}

class VerseSelectorDialog extends StatefulWidget {
  const VerseSelectorDialog({super.key});
  @override State<VerseSelectorDialog> createState() => _VerseSelectorDialogState();
}

class _VerseSelectorDialogState extends State<VerseSelectorDialog> {
  String _selectedBook = 'Genesis'; int _selectedChapter = 1; int _selectedVerse = 1; final DatabaseService _db = DatabaseService(); List<String> _books = []; List<int> _chapters = []; List<int> _verses = [];
  @override void initState() { super.initState(); _loadData(); }
  Future<void> _loadData() async {
    final books = await _db.getBooks(); final chapters = await _db.getChapters(_selectedBook); final verses = await _db.getVerseNumbers(_selectedBook, _selectedChapter);
    setState(() { _books = books; _chapters = chapters; _selectedChapter = 1; _verses = verses; _selectedVerse = 1; });
  }
  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Verse'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<String>(value: _selectedBook, isExpanded: true, items: _books.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(), onChanged: (b) async { final chapters = await _db.getChapters(b!); setState(() { _selectedBook = b; _chapters = chapters; _selectedChapter = 1; }); final verses = await _db.getVerseNumbers(b, 1); setState(() { _verses = verses; _selectedVerse = 1; }); }),
        Row(children: [
          Expanded(child: DropdownButton<int>(value: _selectedChapter, isExpanded: true, items: _chapters.map((c) => DropdownMenuItem(value: c, child: Text('Ch $c'))).toList(), onChanged: (c) async { final verses = await _db.getVerseNumbers(_selectedBook, c!); setState(() { _selectedChapter = c; _verses = verses; _selectedVerse = 1; }); })),
          const SizedBox(width: 10),
          Expanded(child: DropdownButton<int>(value: _selectedVerse, isExpanded: true, items: _verses.map((v) => DropdownMenuItem(value: v, child: Text('V $v'))).toList(), onChanged: (v) => setState(() => _selectedVerse = v!))),
        ]),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, {'book': _selectedBook, 'chapter': _selectedChapter, 'verse': _selectedVerse}), child: const Text('Compare'))],
    );
  }
}
