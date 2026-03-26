import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';
import 'bible_model.dart';
import 'bible_logic.dart';
import 'audio_service.dart';
import 'study_hub_view.dart';
import 'bible_reader_view.dart';

enum AppTheme { system, light, dark, midnight }
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
    final scaffoldBg = _selectedTheme == AppTheme.midnight ? Colors.black : (isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFDFCF8));
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown, brightness: isDark ? Brightness.dark : Brightness.light),
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: _getTextTheme(isDark ? Brightness.dark : Brightness.light),
      appBarTheme: AppBarTheme(backgroundColor: isDark ? Colors.black : Colors.brown[50], centerTitle: true),
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
      themeMode: _selectedTheme == AppTheme.light ? ThemeMode.light : (_selectedTheme == AppTheme.dark || _selectedTheme == AppTheme.midnight ? ThemeMode.dark : ThemeMode.system),
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
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isDbInitializing = true);
    await _db.initialize();
    
    // Explicitly clear cache on restart to force verification of new logic
    BibleLogic.clearCache();
    
    final prefs = await SharedPreferences.getInstance();
    final books = await _db.getBooks();
    final daily = await _db.getDailyVerse();
    final cont = await _db.getContinuityMap();
    final par = await _db.getParenthesesMap();
    
    setState(() {
      _books = books;
      _dailyVerse = daily;
      _continuityMap = cont;
      _parenthesesMap = par;
      // Load and persist the mathematical style
      _currentStyle = BibleViewStyle.values[prefs.getInt('bibleStyle') ?? 0];
      _isDbInitializing = false;
    });
  }

  Future<void> _saveStyle(BibleViewStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bibleStyle', style.index);
    setState(() => _currentStyle = style);
  }

  Future<void> _onBookSelected(String book) async {
    final chapters = await _db.getChapters(book);
    setState(() { _selectedBook = book; _chapters = chapters; _selectedChapter = null; _selectedVerse = null; });
    _bibleTabController.animateTo(1);
  }

  Future<void> _onChapterSelected(int chapter, {bool animateToVerseGrid = true}) async {
    final verses = await _db.getChapter(_selectedBook!, chapter);
    setState(() { _selectedChapter = chapter; _chapterVerses = verses; _selectedVerse = null; });
    if (animateToVerseGrid) _bibleTabController.animateTo(2);
  }

  void _onVerseSelected(int verse) {
    setState(() { _selectedVerse = verse; _selectedWordIndex = 1; });
    _bibleTabController.animateTo(3);
  }

  void _onChapterNavigate(int direction) async {
    if (_selectedBook == null || _selectedChapter == null) return;
    int currentIndex = _chapters.indexOf(_selectedChapter!);
    int newIndex = currentIndex + direction;
    if (newIndex >= 0 && newIndex < _chapters.length) {
      _onChapterSelected(_chapters[newIndex], animateToVerseGrid: false);
    }
  }

  void _jumpToLocation(String loc, {String? highlight}) async {
    final bibleLoc = BibleLogic.parseLocation(loc);
    if (bibleLoc == null) return;
    final bookName = _books.firstWhere((b) => b.toLowerCase().startsWith(bibleLoc.bookAbbr.toLowerCase()), orElse: () => _books.first);
    final chapters = await _db.getChapters(bookName);
    final verses = await _db.getChapter(bookName, bibleLoc.chapter);
    setState(() {
      _selectedBook = bookName;
      _chapters = chapters;
      _selectedChapter = bibleLoc.chapter;
      _chapterVerses = verses;
      _selectedVerse = bibleLoc.verse;
      _selectedWordIndex = bibleLoc.startWord;
      _jumpHighlightPhrase = highlight;
      _selectedIndex = 1;
    });
    _bibleTabController.animateTo(3);
  }

  void _showVerseSelector() async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (c) => const VerseSelectorDialog());
    if (result != null) _jumpToLocation("${result['book']} ${result['chapter']}:${result['verse']}");
  }

  @override
  Widget build(BuildContext context) {
    if (_isDbInitializing) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text("Authorized King James Version 1611 Pure Cambridge Edition circa 1900", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            Text("\$Prevailing KJVersion\$", style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: Colors.brown[700])),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search, color: Colors.brown), onPressed: () => showSearch(context: context, delegate: BibleSearchDelegate(_db))),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.brown), onPressed: () => setState(() { _initData(); })),
          DropdownButton<BibleViewStyle>(
            value: _currentStyle,
            underline: const SizedBox(),
            icon: const Icon(Icons.style, color: Colors.brown),
            items: BibleViewStyle.values.map((s) => DropdownMenuItem(value: s, child: Text(BibleLogic.getReadingLabel(s), style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (s) => _saveStyle(s!),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _dailyVerse == null ? const Center(child: Text("Loading...")) : _buildWelcomePage(_dailyVerse!, _continuityMap, _parenthesesMap),
          _buildBibleNavigator(),
          StudyHubView(
            onJumpToLocation: _jumpToLocation,
            currentStyle: _currentStyle,
            continuityMap: _continuityMap,
            parenthesesMap: _parenthesesMap,
            fontSize: widget.fontSize,
            isDarkMode: widget.selectedTheme == AppTheme.midnight,
          ),
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
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildBibleNavigator() {
    return Column(
      children: [
        TabBar(
          controller: _bibleTabController, isScrollable: true, labelColor: Colors.brown, unselectedLabelColor: Colors.grey,
          tabs: [
            const Tab(text: "BOOK (HEIGHT)"),
            Tab(text: "CHAPTER${(_selectedChapter != null) ? ": $_selectedChapter" : ""} (DEPTH)"),
            Tab(text: "VERSE${(_selectedVerse != null) ? ": $_selectedVerse" : ""} (LENGTH)"),
            const Tab(text: "READER"),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _bibleTabController,
            children: [ _buildBookTab(), _buildChapterTab(), _buildVerseGridTab(), _buildVerseTab(_continuityMap, _parenthesesMap) ],
          ),
        ),
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
    return BibleReaderView(
      bookName: _selectedBook!, chapter: _selectedChapter!, allVersesOfChapter: _chapterVerses, currentStyle: _currentStyle, continuityMap: cont, parenthesesMap: par, targetVerse: _selectedVerse, targetWordIndex: _selectedWordIndex, audioService: _audioService, isAudioEnabled: widget.isAudioEnabled, fontSize: widget.fontSize, isDarkMode: widget.selectedTheme == AppTheme.midnight, highlightPhrase: _jumpHighlightPhrase, onChapterChange: (direction) => _onChapterNavigate(direction), onFontSizeChanged: widget.onFontSizeChanged, onAudioChanged: widget.onAudioChanged,
    );
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
      const SizedBox(height: 24),
      InkWell(onTap: () => _jumpToLocation("${v.bookAbbreviation}${v.chapter}:${v.verse}"), child: _buildComparisonView(v, cont, par)),
    ]));
  }

  Widget _buildComparisonView(BibleVerse v, Map<String, String> cont, Map<String, String> par) {
    return Column(
      children: [
        _buildComparisonRow("AKJV 1611 PCE circa 1900", v, cont, par, BibleViewStyle.standard),
        _buildComparisonRow("Superscript KJV", v, cont, par, BibleViewStyle.superscript),
        _buildComparisonRow("MathKJVP", v, cont, par, BibleViewStyle.mathematics),
        _buildComparisonRow("MathKJVS", v, cont, par, BibleViewStyle.mathematics2),
        _buildComparisonRow("MathKJVT", v, cont, par, BibleViewStyle.mathematicsUnconstraint),
      ],
    );
  }

  Widget _buildComparisonRow(String title, BibleVerse v, Map<String, String> cont, Map<String, String> par, BibleViewStyle style) {
    final bool isMath = style != BibleViewStyle.standard && style != BibleViewStyle.superscript;
    return Container(
      width: double.infinity, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: isMath ? Colors.black : Colors.brown[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.brown[100]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isMath ? Colors.white70 : Colors.brown)),
          const SizedBox(height: 8),
          Wrap(children: BibleLogic.applyContinuity(v, cont, parenthesesMap: par, style: style).map((mw) => _renderComparisonWord(v, mw, style)).toList()),
        ],
      ),
    );
  }

  Widget _renderComparisonWord(BibleVerse v, MathWord mw, BibleViewStyle style) {
    final bool isMath = style != BibleViewStyle.standard && style != BibleViewStyle.superscript;
    final bool isSuperscript = style == BibleViewStyle.superscript;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: RichText(text: TextSpan(children: [
        if (mw.hasLeadingSpace) const TextSpan(text: ' '),
        ...mw.parts.map((p) {
          if (isSuperscript && !p.isParenthesis) {
            return TextSpan(children: [
              TextSpan(text: p.text, style: TextStyle(color: Colors.black87, fontSize: widget.fontSize * 0.85, fontStyle: p.isItalic ? FontStyle.italic : FontStyle.normal)),
              WidgetSpan(child: Transform.translate(offset: const Offset(0, -5), child: Text('${mw.original.index}', style: TextStyle(fontSize: widget.fontSize * 0.45, color: Colors.blue, fontWeight: FontWeight.bold)))),
            ]);
          }
          return TextSpan(text: p.text, style: TextStyle(
            color: p.isRed ? Colors.red : (isMath ? Colors.white : Colors.black87), fontSize: widget.fontSize * 0.85, fontWeight: p.isRed ? FontWeight.bold : FontWeight.normal, fontStyle: p.isItalic ? FontStyle.italic : FontStyle.normal, fontFamily: isMath ? 'Courier' : null,
          ));
        })
      ])),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("Appearance", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown)),
        const SizedBox(height: 16),
        ListTile(title: const Text("Theme Mode"), trailing: DropdownButton<AppTheme>(value: widget.selectedTheme, items: AppTheme.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()))).toList(), onChanged: (t) => widget.onThemeChanged(t!))),
        ListTile(title: const Text("App Font"), trailing: DropdownButton<AppFont>(value: widget.selectedFont, items: AppFont.values.map((f) => DropdownMenuItem(value: f, child: Text(f.name.toUpperCase()))).toList(), onChanged: (f) => widget.onFontChanged(f!))),
        const Divider(),
        const Text("Audio Settings", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.brown)),
        SwitchListTile(title: const Text("Enable Audio Sync"), subtitle: const Text("Highlights words during playback"), value: widget.isAudioEnabled, onChanged: widget.onAudioChanged),
        ListTile(title: const Text("Voice Quality"), trailing: DropdownButton<AudioQuality>(value: widget.audioQuality, items: AudioQuality.values.map((q) => DropdownMenuItem(value: q, child: Text(q.name.toUpperCase()))).toList(), onChanged: (q) => widget.onAudioQualityChanged(q!))),
      ],
    );
  }
}

class BibleSearchDelegate extends SearchDelegate<BibleMatch?> {
  final DatabaseService db;
  BibleSearchDelegate(this.db);
  @override String get searchFieldLabel => "Enter Phrase or Location (separate ranges with a comma)";
  @override List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];
  @override Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  @override Widget buildResults(BuildContext context) {
    return FutureBuilder<List<BibleMatch>>(
      future: db.search(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No results found."));
        final results = snapshot.data!;
        final summary = query.contains(':') ? "$query ↦" : "$query ↦ {${results.map((m) => m.location).join(', ')}}";
        return Column(
          children: [
            Container(width: double.maxFinite, padding: const EdgeInsets.all(12), color: Colors.brown[50], child: Row(children: [Expanded(child: Text(summary, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.brown))), IconButton(icon: const Icon(Icons.copy_all, size: 20), onPressed: () { Clipboard.setData(ClipboardData(text: summary)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Summary copied to clipboard"))); })])),
            Expanded(child: ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
              final m = results[index];
              return ListTile(title: RichText(text: TextSpan(style: const TextStyle(color: Colors.black, fontSize: 14), children: _highlightVerseText(m.verse.text, m.phrase))), subtitle: Text(m.location, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)), trailing: IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () { Clipboard.setData(ClipboardData(text: "${m.phrase}(${m.location})")); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phrase(Location) copied"))); }), onTap: () => close(context, m));
            })),
          ],
        );
      },
    );
  }
  List<TextSpan> _highlightVerseText(String verseText, String query) {
    if (query.isEmpty) return [TextSpan(text: verseText)];
    List<TextSpan> spans = []; final lowerVerse = verseText.toLowerCase(); final lowerQuery = query.toLowerCase(); int start = 0; int indexOfMatch;
    while ((indexOfMatch = lowerVerse.indexOf(lowerQuery, start)) != -1) {
      if (indexOfMatch > start) spans.add(TextSpan(text: verseText.substring(start, indexOfMatch)));
      spans.add(TextSpan(text: verseText.substring(indexOfMatch, indexOfMatch + query.length), style: const TextStyle(fontWeight: FontWeight.bold, backgroundColor: Colors.yellow)));
      start = indexOfMatch + query.length;
    }
    if (start < verseText.length) spans.add(TextSpan(text: verseText.substring(start)));
    return spans;
  }
  @override Widget buildSuggestions(BuildContext context) { if (query.length < 2) return const Center(child: Text("Enter at least 2 characters to search...")); return buildResults(context); }
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
    setState(() { _books = books; _chapters = chapters; _verses = verses; });
  }
  @override Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Jump to Verse'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButton<String>(value: _selectedBook, isExpanded: true, items: _books.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(), onChanged: (b) async { final chapters = await _db.getChapters(b!); setState(() { _selectedBook = b; _chapters = chapters; _selectedChapter = 1; }); final verses = await _db.getVerseNumbers(b, 1); setState(() { _verses = verses; _selectedVerse = 1; }); }),
        Row(children: [
          Expanded(child: DropdownButton<int>(value: _selectedChapter, isExpanded: true, items: _chapters.map((c) => DropdownMenuItem(value: c, child: Text('Ch $c'))).toList(), onChanged: (c) async { final verses = await _db.getVerseNumbers(_selectedBook, c!); setState(() { _selectedChapter = c; _verses = verses; _selectedVerse = 1; }); })),
          const SizedBox(width: 10),
          Expanded(child: DropdownButton<int>(value: _selectedVerse, isExpanded: true, items: _verses.map((v) => DropdownMenuItem(value: v, child: Text('V $v'))).toList(), onChanged: (v) => setState(() => _selectedVerse = v!))),
        ]),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, {'book': _selectedBook, 'chapter': _selectedChapter, 'verse': _selectedVerse}), child: const Text('Jump'))],
    );
  }
}
