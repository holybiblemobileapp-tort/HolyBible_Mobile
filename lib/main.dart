import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'bible_model.dart';
import 'bible_logic.dart';
import 'database_service.dart';
import 'bible_reader_view.dart';
import 'audio_service.dart';
import 'study_hub_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HolyBibleApp());
}

enum AppTheme { defaultBrown, livingWater, goldenGrain, midnight }
enum AppFont { system, crimsonText, roboto, courierPrime }

class HolyBibleApp extends StatefulWidget {
  const HolyBibleApp({super.key});

  @override
  State<HolyBibleApp> createState() => _HolyBibleAppState();
}

class _HolyBibleAppState extends State<HolyBibleApp> {
  AppTheme _selectedTheme = AppTheme.defaultBrown;
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
      _audioQuality = AudioQuality.values[qualityIndex];
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('appTheme', _selectedTheme.index);
    await prefs.setInt('appFont', _selectedFont.index);
    await prefs.setBool('audioEnabled', _isAudioEnabled);
    await prefs.setDouble('fontSize', _fontSize);
    await prefs.setInt('audioQuality', _audioQuality.index);
  }

  ThemeData _buildTheme(Brightness brightness) {
    Color primaryColor;
    Color scaffoldBg;
    Color accentColor = Colors.amberAccent;
    
    switch (_selectedTheme) {
      case AppTheme.livingWater:
        primaryColor = Colors.blueGrey[800]!;
        scaffoldBg = const Color(0xFFE0F2F1);
        break;
      case AppTheme.goldenGrain:
        primaryColor = Colors.orange[900]!;
        scaffoldBg = const Color(0xFFFFF8E1);
        break;
      case AppTheme.midnight:
        primaryColor = Colors.blueGrey[900]!;
        scaffoldBg = const Color(0xFF121212);
        accentColor = Colors.cyanAccent;
        break;
      case AppTheme.defaultBrown:
      default:
        primaryColor = Colors.brown;
        scaffoldBg = const Color(0xFFF5F5DC);
        break;
    }

    final isDark = brightness == Brightness.dark || _selectedTheme == AppTheme.midnight;

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: primaryColor,
      appBarTheme: AppBarTheme(backgroundColor: primaryColor, foregroundColor: Colors.white),
      scaffoldBackgroundColor: isDark ? const Color(0xFF1A1A1A) : scaffoldBg,
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicator: UnderlineTabIndicator(borderSide: BorderSide(color: accentColor, width: 3)),
      ),
      textTheme: _getTextTheme(isDark ? Brightness.dark : Brightness.light),
    );
  }

  TextTheme _getTextTheme(Brightness brightness) {
    TextStyle baseStyle;
    switch (_selectedFont) {
      case AppFont.crimsonText: baseStyle = GoogleFonts.crimsonText(); break;
      case AppFont.roboto: baseStyle = GoogleFonts.roboto(); break;
      case AppFont.courierPrime: baseStyle = GoogleFonts.courierPrime(); break;
      case AppFont.system:
      default: baseStyle = const TextStyle(); break;
    }
    return GoogleFonts.getTextTheme(_selectedFont == AppFont.system ? 'Roboto' : baseStyle.fontFamily!, 
      ThemeData(brightness: brightness).textTheme);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Holy Bible Mobile',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      home: MainNavigation(
        selectedTheme: _selectedTheme,
        selectedFont: _selectedFont,
        isAudioEnabled: _isAudioEnabled,
        fontSize: _fontSize,
        audioQuality: _audioQuality,
        onThemeChanged: (v) { setState(() => _selectedTheme = v); _saveSettings(); },
        onFontChanged: (v) { setState(() => _selectedFont = v); _saveSettings(); },
        onAudioChanged: (v) { setState(() => _isAudioEnabled = v); _saveSettings(); },
        onFontSizeChanged: (v) { setState(() => _fontSize = v); _saveSettings(); },
        onAudioQualityChanged: (v) { setState(() => _audioQuality = v); _saveSettings(); },
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
  
  final DatabaseService _db = DatabaseService();
  final AudioService _audioService = AudioService();
  final TextEditingController _bookFilterController = TextEditingController();

  Map<String, String> _continuityMap = {};
  Map<String, String> _parenthesesMap = {};

  late TabController _bibleTabController;

  @override
  void initState() {
    super.initState();
    _bibleTabController = TabController(length: 5, vsync: this);
    _initData();
  }

  @override
  void dispose() {
    _bibleTabController.dispose();
    _bookFilterController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isDbInitializing = true);
    await _db.initialize();
    final books = await _db.getBooks();
    final daily = await _db.getDailyVerse();
    final cont = await _db.getContinuityMap();
    final par = await _db.getParenthesesMap();
    
    setState(() {
      _books = books;
      _dailyVerse = daily;
      _continuityMap = cont;
      _parenthesesMap = par;
      _isDbInitializing = false;
    });
  }

  Future<void> _onBookSelected(String book) async {
    final chapters = await _db.getChapters(book);
    setState(() {
      _selectedBook = book;
      _chapters = chapters;
      _selectedChapter = null;
      _selectedVerse = null;
    });
    _bibleTabController.animateTo(2);
  }

  Future<void> _onChapterSelected(int chapter) async {
    final verses = await _db.getChapter(_selectedBook!, chapter);
    setState(() {
      _selectedChapter = chapter;
      _chapterVerses = verses;
      _selectedVerse = null;
    });
    _bibleTabController.animateTo(3);
  }

  void _onVerseSelected(int verse) {
    setState(() {
      _selectedVerse = verse;
      _selectedWordIndex = 1;
    });
    _bibleTabController.animateTo(4);
  }

  void _onChapterNavigate(String book, int chapter) async {
    if (chapter < 1) {
      int bookIdx = _books.indexOf(book);
      if (bookIdx > 0) {
        String prevBook = _books[bookIdx - 1];
        final prevChapters = await _db.getChapters(prevBook);
        int lastChapter = prevChapters.last;
        final verses = await _db.getChapter(prevBook, lastChapter);
        setState(() {
          _selectedBook = prevBook;
          _selectedChapter = lastChapter;
          _chapters = prevChapters;
          _chapterVerses = verses;
          _selectedVerse = null;
          _selectedWordIndex = null;
        });
      }
      return;
    }

    final verses = await _db.getChapter(book, chapter);
    if (verses.isEmpty) {
      int bookIdx = _books.indexOf(book);
      if (bookIdx < _books.length - 1) {
        String nextBook = _books[bookIdx + 1];
        final nextChapters = await _db.getChapters(nextBook);
        final nextVerses = await _db.getChapter(nextBook, 1);
        setState(() {
          _selectedBook = nextBook;
          _selectedChapter = 1;
          _chapters = nextChapters;
          _chapterVerses = nextVerses;
          _selectedVerse = null;
          _selectedWordIndex = null;
        });
      }
      return;
    }

    setState(() {
      _selectedChapter = chapter;
      _chapterVerses = verses;
      _selectedVerse = null;
      _selectedWordIndex = null;
    });
  }

  void _jumpToLocation(String loc, {String? highlight}) async {
    final parsed = BibleLogic.parseLocation(loc);
    if (parsed == null) return;
    
    final books = await _db.getBooks();
    final book = books.firstWhere((b) => b.startsWith(parsed.bookAbbr), orElse: () => parsed.bookAbbr);
    final verses = await _db.getChapter(book, parsed.chapter);
    final chapters = await _db.getChapters(book);
    
    setState(() {
      _selectedBook = book;
      _chapters = chapters;
      _selectedChapter = parsed.chapter;
      _chapterVerses = verses;
      _selectedVerse = parsed.verse;
      _selectedWordIndex = parsed.startWord;
      _jumpHighlightPhrase = highlight;
      _selectedIndex = 0;
    });
    _bibleTabController.animateTo(4);
  }

  void _jumpToDetailedLocation(String book, int chapter, int verse, BibleViewStyle style, {int? wordIndex, String? highlight}) async {
    final verses = await _db.getChapter(book, chapter);
    final chapters = await _db.getChapters(book);
    setState(() {
      _selectedBook = book;
      _chapters = chapters;
      _selectedChapter = chapter;
      _chapterVerses = verses;
      _selectedVerse = verse;
      _selectedWordIndex = wordIndex;
      _currentStyle = style;
      _jumpHighlightPhrase = highlight;
      _selectedIndex = 0;
    });
    _bibleTabController.animateTo(4);
  }

  void _showGeneralSearch() async {
    final BibleMatch? result = await showSearch<BibleMatch?>(
      context: context,
      delegate: BibleSearchDelegate(_db),
    );
    if (result != null) {
      _jumpToLocation(result.location, highlight: result.phrase);
    }
  }

  void _showVerseSelector() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const VerseSelectorDialog(),
    );
    if (result != null) {
      final book = result['book'] as String;
      final chapter = result['chapter'] as int;
      final verse = result['verse'] as int;
      final v = await _db.getSpecificVerse(book, chapter, verse);
      if (v != null) setState(() => _dailyVerse = v);
    }
  }

  void _resetToWelcome() {
    _bibleTabController.animateTo(0);
  }

  String _getDynamicStyleName(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard: return "Authorized King James Version 1611 PCE";
      case BibleViewStyle.superscript: return "Superscript KJV";
      case BibleViewStyle.mathematics: return "MathKJVP";
      case BibleViewStyle.mathematics2: return "MathKJVS";
      case BibleViewStyle.mathematicsUnconstraint: return "MathKJVT";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Holy Bible Mobile', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text(_getDynamicStyleName(_currentStyle), style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _showGeneralSearch),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _initData),
          IconButton(icon: const Icon(Icons.home), onPressed: _resetToWelcome),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => _showSettings(context)),
        ],
        bottom: (_selectedIndex == 0) 
          ? TabBar(
              controller: _bibleTabController,
              isScrollable: true,
              tabs: [
                const Tab(icon: Icon(Icons.auto_awesome, size: 18), text: "HOME"),
                Tab(text: "BOOK${(_selectedBook != null) ? ": $_selectedBook" : ""} (HEIGHT)"),
                Tab(text: "CHAPTER${(_selectedChapter != null) ? ": $_selectedChapter" : ""} (DEPTH)"),
                Tab(text: "VERSE${(_selectedVerse != null) ? ": $_selectedVerse" : ""} (LENGTH)"),
                const Tab(text: "BREADTH (READER)"),
              ],
            )
          : null,
      ),
      body: _isDbInitializing 
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SvgPicture.asset('assets/IGoToTheFather.svg', height: 120),
            const SizedBox(height: 20),
            const CircularProgressIndicator(), 
            const SizedBox(height: 20), 
            const Text("Initializing Bible Vector Space...")
          ]))
        : IndexedStack(
            index: _selectedIndex,
            children: [
              _buildBibleTabs(),
              StudyHubView(
                onJumpToLocation: _jumpToLocation,
                currentStyle: _currentStyle,
                continuityMap: _continuityMap,
                parenthesesMap: _parenthesesMap,
                fontSize: widget.fontSize,
                isDarkMode: widget.selectedTheme == AppTheme.midnight,
              ),
              const Center(child: Text('Settings are in the Bottom Sheet')),
            ],
          ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Bible'),
          BottomNavigationBarItem(icon: Icon(Icons.hub), label: 'Study Hub'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildBibleTabs() {
    return TabBarView(
      controller: _bibleTabController,
      children: [
        _buildWelcomePage(_dailyVerse!, _continuityMap, _parenthesesMap),
        _buildBookTab(),
        _buildChapterTab(),
        _buildVerseGridTab(),
        _buildVerseTab(_continuityMap, _parenthesesMap),
      ],
    );
  }

  Widget _buildBookTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8.0), child: TextField(controller: _bookFilterController, decoration: const InputDecoration(hintText: 'Filter Books...', prefixIcon: Icon(Icons.filter_list), border: OutlineInputBorder()), onChanged: (v) => setState(() {}))),
      Expanded(child: ListView.builder(itemCount: _books.length, itemBuilder: (context, index) { if (_bookFilterController.text.isNotEmpty && !_books[index].toLowerCase().contains(_bookFilterController.text.toLowerCase())) return const SizedBox.shrink(); return ListTile(title: Text(_books[index]), selected: _selectedBook == _books[index], onTap: () => _onBookSelected(_books[index])); })),
    ]);
  }

  Widget _buildChapterTab() {
    if (_selectedBook == null) return const Center(child: Text("Select a Book first (HEIGHT)"));
    return GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: _chapters.length, itemBuilder: (context, index) { return InkWell(onTap: () => _onChapterSelected(_chapters[index]), child: Container(decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), alignment: Alignment.center, child: Text('${_chapters[index]}'))); });
  }

  Widget _buildVerseGridTab() {
    if (_selectedChapter == null) return const Center(child: Text("Select a Chapter first (DEPTH)"));
    final verses = _chapterVerses.map((v) => v.verse).toSet().toList()..sort();
    return GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: verses.length, itemBuilder: (context, index) { return InkWell(onTap: () => _onVerseSelected(verses[index]), child: Container(decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), alignment: Alignment.center, child: Text('${verses[index]}'))); });
  }

  Widget _buildVerseTab(Map<String, String> cont, Map<String, String> par) {
    if (_selectedBook == null || _selectedChapter == null) return const Center(child: Text("Navigation required (HEIGHT > DEPTH > LENGTH)"));
    return BibleReaderView(bookName: _selectedBook!, chapter: _selectedChapter!, allVersesOfChapter: _chapterVerses, currentStyle: _currentStyle, continuityMap: cont, parenthesesMap: par, targetVerse: _selectedVerse, targetWordIndex: _selectedWordIndex, audioService: _audioService, isAudioEnabled: widget.isAudioEnabled, fontSize: widget.fontSize, isDarkMode: widget.selectedTheme == AppTheme.midnight, highlightPhrase: _jumpHighlightPhrase, onChapterChange: (ch) => _onChapterNavigate(_selectedBook!, ch));
  }

  Widget _buildWelcomePage(BibleVerse v, Map<String, String> cont, Map<String, String> par) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16.0), child: Column(children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset('assets/IGoToTheFather1B.PNG', height: 80),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Daily Bread', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.edit, size: 20, color: Colors.brown), onPressed: _showVerseSelector, tooltip: "Change Verse"),
                  ],
                ),
                Text('${v.bookAbbreviation}${v.chapter}:${v.verse}:1-${v.wordCount}', style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildWelcomeSection('AKJV 1611 PCE circa 1900', Text(v.text, textAlign: TextAlign.center, style: TextStyle(fontSize: widget.fontSize, fontStyle: FontStyle.italic)), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.standard)),
      _buildWelcomeSection('Superscript KJV', _buildCardContent(v, BibleViewStyle.superscript), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.superscript)),
      _buildWelcomeSection('MathKJVP', _buildMathContent(v, cont, par, BibleViewStyle.mathematics), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematics)),
      _buildWelcomeSection('MathKJVS', _buildMathContent(v, cont, par, BibleViewStyle.mathematics2), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematics2)),
      _buildWelcomeSection('MathKJVT', _buildMathContent(v, cont, par, BibleViewStyle.mathematicsUnconstraint), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematicsUnconstraint)),
    ]));
  }

  Widget _buildCardContent(BibleVerse v, BibleViewStyle style) {
    final bool isDarkTheme = Theme.of(context).brightness == Brightness.dark || widget.selectedTheme == AppTheme.midnight;
    final Color textColor = isDarkTheme ? Colors.white : Colors.black;

    if (style == BibleViewStyle.superscript) {
      return Wrap(alignment: WrapAlignment.center, children: v.styledWords.map((w) => RichText(text: TextSpan(children: [
        TextSpan(text: '${w.text}', style: TextStyle(color: textColor, fontSize: widget.fontSize, fontStyle: w.isItalic ? FontStyle.italic : FontStyle.normal)),
        WidgetSpan(child: Transform.translate(offset: const Offset(0, -10), child: Text('${w.index}', style: TextStyle(fontSize: widget.fontSize * 0.6, color: Colors.blue, fontWeight: FontWeight.bold)))),
        const TextSpan(text: ' '),
      ]))).toList());
    }
    return Text(v.text, style: TextStyle(color: textColor, fontSize: widget.fontSize));
  }

  Widget _buildMathContent(BibleVerse v, Map<String, String> cont, Map<String, String> par, BibleViewStyle style) {
    final words = BibleLogic.applyContinuity(v, cont, parenthesesMap: par, style: style);
    return Container(
      color: Colors.black, padding: const EdgeInsets.all(8.0),
      child: Wrap(alignment: WrapAlignment.center, children: words.map((mw) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: RichText(text: TextSpan(children: [
        if (mw.hasLeadingSpace) const TextSpan(text: ' '),
        ...mw.parts.map((p) => TextSpan(text: p.text, style: TextStyle(color: p.isRed ? Colors.redAccent : Colors.white, fontSize: widget.fontSize, fontWeight: FontWeight.bold, fontFamily: 'Courier', shadows: [Shadow(blurRadius: 2.0, color: p.isRed ? Colors.red : Colors.cyanAccent)])))
      ])))).toList()),
    );
  }

  Widget _buildWelcomeSection(String title, Widget content, VoidCallback onTap) { return Column(children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), InkWell(onTap: onTap, child: Card(elevation: 4, child: Padding(padding: const EdgeInsets.all(16.0), child: content))), const SizedBox(height: 15)]); }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => Container(height: MediaQuery.of(context).size.height * 0.8, decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))), child: Column(children: [Container(margin: const EdgeInsets.symmetric(vertical: 10), height: 4, width: 40, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))), const ListTile(title: Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20))), const Divider(), Expanded(child: ListView(padding: EdgeInsets.symmetric(horizontal: 16), children: [
      const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('Themes', style: TextStyle(fontWeight: FontWeight.bold))),
      Wrap(spacing: 10, children: AppTheme.values.map((t) => ChoiceChip(label: Text(t.name), selected: widget.selectedTheme == t, onSelected: (s) => widget.onThemeChanged(t))).toList()),
      const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text('Fonts', style: TextStyle(fontWeight: FontWeight.bold))),
      Wrap(spacing: 10, children: AppFont.values.map((f) => ChoiceChip(label: Text(f.name), selected: widget.selectedFont == f, onSelected: (s) => widget.onFontChanged(f))).toList()),
      ListTile(title: const Text('View Style'), trailing: DropdownButton<BibleViewStyle>(value: _currentStyle, items: const [
        DropdownMenuItem(value: BibleViewStyle.standard, child: Text('AKJV 1611 PCE')),
        DropdownMenuItem(value: BibleViewStyle.superscript, child: Text('Superscript KJV')),
        DropdownMenuItem(value: BibleViewStyle.mathematics, child: Text('MathKJVP')),
        DropdownMenuItem(value: BibleViewStyle.mathematics2, child: Text('MathKJVS')),
        DropdownMenuItem(value: BibleViewStyle.mathematicsUnconstraint, child: Text('MathKJVT')),
      ], onChanged: (s) { setState(() => _currentStyle = s!); Navigator.pop(context); })),
      SwitchListTile(title: const Text('Enable Voice (Audio)'), value: widget.isAudioEnabled, onChanged: (v) { widget.onAudioChanged(v); Navigator.pop(context); }),
      ListTile(title: const Text('Font Size'), subtitle: Slider(value: widget.fontSize, min: 12, max: 36, divisions: 12, label: widget.fontSize.round().toString(), onChanged: (v) => widget.onFontSizeChanged(v))),
    ]))])));
  }
}

class BibleSearchDelegate extends SearchDelegate<BibleMatch?> {
  final DatabaseService db;
  BibleSearchDelegate(this.db);

  @override
  String get searchFieldLabel => "Enter Phrase or Location (separate ranges with a comma)";

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  }

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List<BibleMatch>>(
      future: db.search(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No results found."));
        final results = snapshot.data!;
        final summary = query.contains(':') ? "$query ↦" : "$query ↦ {${results.map((m) => m.location).join(', ')}}";

        return Column(
          children: [
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(12),
              color: Colors.brown[50],
              child: Row(
                children: [
                  Expanded(child: Text(summary, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.brown))),
                  IconButton(
                    icon: const Icon(Icons.copy_all, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: summary));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Summary copied to clipboard")));
                    },
                  )
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final m = results[index];
                  return ListTile(
                    title: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black, fontSize: 14),
                        children: _highlightVerseText(m.verse.text, m.phrase),
                      ),
                    ),
                    subtitle: Text(m.location, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: "${m.phrase}(${m.location})"));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phrase(Location) copied")));
                      },
                    ),
                    onTap: () => close(context, m),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  List<TextSpan> _highlightVerseText(String verseText, String query) {
    if (query.isEmpty) return [TextSpan(text: verseText)];
    List<TextSpan> spans = [];
    final lowerVerse = verseText.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int start = 0;
    int indexOfMatch;
    while ((indexOfMatch = lowerVerse.indexOf(lowerQuery, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: verseText.substring(start, indexOfMatch)));
      }
      spans.add(TextSpan(
        text: verseText.substring(indexOfMatch, indexOfMatch + query.length),
        style: const TextStyle(fontWeight: FontWeight.bold, backgroundColor: Colors.yellow),
      ));
      start = indexOfMatch + query.length;
    }
    if (start < verseText.length) {
      spans.add(TextSpan(text: verseText.substring(start)));
    }
    return spans;
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.length < 2) return const Center(child: Text("Enter at least 2 characters to search..."));
    return buildResults(context);
  }
}

class VerseSelectorDialog extends StatefulWidget {
  const VerseSelectorDialog({super.key});
  @override
  State<VerseSelectorDialog> createState() => _VerseSelectorDialogState();
}

class _VerseSelectorDialogState extends State<VerseSelectorDialog> {
  String _selectedBook = 'Genesis';
  int _selectedChapter = 1;
  int _selectedVerse = 1;
  final DatabaseService _db = DatabaseService();
  List<String> _books = [];
  List<int> _chapters = [];
  List<int> _verses = [];
  @override
  void initState() {
    super.initState();
    _loadData();
  }
  Future<void> _loadData() async {
    final books = await _db.getBooks();
    final chapters = await _db.getChapters(_selectedBook);
    final verses = await _db.getVerseNumbers(_selectedBook, _selectedChapter);
    setState(() {
      _books = books;
      _chapters = chapters;
      _verses = verses;
    });
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Jump to Verse'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<String>(
            value: _selectedBook,
            isExpanded: true,
            items: _books.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (b) async {
              final chapters = await _db.getChapters(b!);
              setState(() { _selectedBook = b; _chapters = chapters; _selectedChapter = 1; });
              final verses = await _db.getVerseNumbers(b, 1);
              setState(() { _verses = verses; _selectedVerse = 1; });
            },
          ),
          Row(
            children: [
              Expanded(child: DropdownButton<int>(
                value: _selectedChapter,
                isExpanded: true,
                items: _chapters.map((c) => DropdownMenuItem(value: c, child: Text('Ch $c'))).toList(),
                onChanged: (c) async {
                  final verses = await _db.getVerseNumbers(_selectedBook, c!);
                  setState(() { _selectedChapter = c; _verses = verses; _selectedVerse = 1; });
                },
              )),
              const SizedBox(width: 10),
              Expanded(child: DropdownButton<int>(
                value: _selectedVerse,
                isExpanded: true,
                items: _verses.map((v) => DropdownMenuItem(value: v, child: Text('V $v'))).toList(),
                onChanged: (v) => setState(() => _selectedVerse = v!),
              )),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, {'book': _selectedBook, 'chapter': _selectedChapter, 'verse': _selectedVerse}), child: const Text('Jump')),
      ],
    );
  }
}
