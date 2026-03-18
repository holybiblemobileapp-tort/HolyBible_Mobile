import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class HolyBibleApp extends StatefulWidget {
  const HolyBibleApp({super.key});

  @override
  State<HolyBibleApp> createState() => _HolyBibleAppState();
}

class _HolyBibleAppState extends State<HolyBibleApp> {
  bool _isDarkMode = false;
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
      _isDarkMode = prefs.getBool('darkMode') ?? false;
      _isAudioEnabled = prefs.getBool('audioEnabled') ?? true;
      _fontSize = prefs.getDouble('fontSize') ?? 18.0;
      final qualityIndex = prefs.getInt('audioQuality') ?? 0;
      _audioQuality = AudioQuality.values[qualityIndex];
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('darkMode', _isDarkMode);
    await prefs.setBool('audioEnabled', _isAudioEnabled);
    await prefs.setDouble('fontSize', _fontSize);
    await prefs.setInt('audioQuality', _audioQuality.index);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Holy Bible Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.brown,
        scaffoldBackgroundColor: const Color(0xFFF5F5DC),
        cardTheme: const CardThemeData(color: Colors.white, elevation: 2),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.brown,
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: MainNavigation(
        isDarkMode: _isDarkMode,
        isAudioEnabled: _isAudioEnabled,
        fontSize: _fontSize,
        audioQuality: _audioQuality,
        onThemeChanged: (v) { setState(() => _isDarkMode = v); _saveSettings(); },
        onAudioChanged: (v) { setState(() => _isAudioEnabled = v); _saveSettings(); },
        onFontSizeChanged: (v) { setState(() => _fontSize = v); _saveSettings(); },
        onAudioQualityChanged: (v) { setState(() => _audioQuality = v); _saveSettings(); },
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final bool isDarkMode;
  final bool isAudioEnabled;
  final double fontSize;
  final AudioQuality audioQuality;
  final Function(bool) onThemeChanged;
  final Function(bool) onAudioChanged;
  final Function(double) onFontSizeChanged;
  final Function(AudioQuality) onAudioQualityChanged;

  const MainNavigation({
    super.key,
    required this.isDarkMode,
    required this.isAudioEnabled,
    required this.fontSize,
    required this.audioQuality,
    required this.onThemeChanged,
    required this.onAudioChanged,
    required this.onFontSizeChanged,
    required this.onAudioQualityChanged,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
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

  @override
  void initState() {
    super.initState();
    _initData();
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
  }

  Future<void> _onChapterSelected(int chapter) async {
    final verses = await _db.getChapter(_selectedBook!, chapter);
    setState(() {
      _selectedChapter = chapter;
      _chapterVerses = verses;
      _selectedVerse = null;
    });
  }

  void _onVerseSelected(int verse) {
    setState(() {
      _selectedVerse = verse;
      _selectedWordIndex = 1;
    });
  }

  void _onChapterNavigate(String book, int chapter) async {
    if (chapter < 1) return;
    final verses = await _db.getChapter(book, chapter);
    if (verses.isEmpty) return;
    setState(() {
      _selectedChapter = chapter;
      _chapterVerses = verses;
      _selectedVerse = null;
      _selectedWordIndex = null;
    });
  }

  void _jumpToLocation(String loc) async {
    final parsed = BibleLogic.parseLocation(loc);
    if (parsed == null) return;
    
    final books = await _db.getBooks();
    final book = books.firstWhere((b) => b.startsWith(parsed.bookAbbr), orElse: () => parsed.bookAbbr);
    final verses = await _db.getChapter(book, parsed.chapter);
    
    setState(() {
      _selectedBook = book;
      _selectedChapter = parsed.chapter;
      _chapterVerses = verses;
      _selectedVerse = parsed.verse;
      _selectedWordIndex = parsed.startWord;
      _selectedIndex = 0;
    });
  }

  void _jumpToDetailedLocation(String book, int chapter, int verse, BibleViewStyle style, {int? wordIndex, String? highlight}) async {
    final verses = await _db.getChapter(book, chapter);
    setState(() {
      _selectedBook = book;
      _selectedChapter = chapter;
      _chapterVerses = verses;
      _selectedVerse = verse;
      _selectedWordIndex = wordIndex;
      _currentStyle = style;
      _jumpHighlightPhrase = highlight;
      _selectedIndex = 0;
    });
  }

  void _showVerseSelector() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const VerseSelectorDialog(),
    );
    if (result != null) {
      if (_selectedBook == null) {
        final newVerse = await _db.getSpecificVerse(result['book'], result['chapter'], result['verse']);
        if (newVerse != null) {
          setState(() => _dailyVerse = newVerse);
        }
      } else {
        _jumpToDetailedLocation(result['book'], result['chapter'], result['verse'], BibleViewStyle.standard);
      }
    }
  }

  void _resetToWelcome() {
    setState(() {
      _selectedBook = null;
      _selectedChapter = null;
      _selectedVerse = null;
      _selectedWordIndex = null;
      _jumpHighlightPhrase = null;
      _selectedIndex = 0;
    });
  }

  String _getDynamicStyleName(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard: return "Authorized King James Version 1611 PCE";
      case BibleViewStyle.superscript: return "Superscript KJV";
      case BibleViewStyle.mathematics: return "Mathematics KJV 1";
      case BibleViewStyle.mathematics2: return "Mathematics KJV 2";
      case BibleViewStyle.mathematicsUnconstraint: return "Mathematics KJV UNCONSTRAINT";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Authorized King James Version 1611 PCE circa 1900', style: TextStyle(fontSize: 14)),
        leading: _selectedIndex == 0 && _selectedBook != null 
          ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
              if (_selectedVerse != null) setState(() => _selectedVerse = null);
              else if (_selectedChapter != null) setState(() => _selectedChapter = null);
              else setState(() => _selectedBook = null);
            })
          : null,
        actions: [
          if (_selectedIndex == 0) IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _selectedIndex = 1)),
          if (_selectedIndex == 0) IconButton(icon: const Icon(Icons.refresh), onPressed: _initData),
          if (_selectedIndex == 0) IconButton(icon: const Icon(Icons.home), onPressed: _resetToWelcome),
          if (_selectedIndex == 0) IconButton(icon: const Icon(Icons.settings), onPressed: () => _showSettings(context)),
        ],
      ),
      body: _isDbInitializing 
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 20), Text("Initializing Bible Vector Space...")] ))
        : IndexedStack(
            index: _selectedIndex,
            children: [
              _buildReaderView(),
              StudyHubView(
                onJumpToLocation: _jumpToLocation,
                currentStyle: _currentStyle,
                continuityMap: _continuityMap,
                parenthesesMap: _parenthesesMap,
                fontSize: widget.fontSize,
                isDarkMode: widget.isDarkMode,
              ),
              const Center(child: Text('Settings are in the Bottom Sheet')),
            ],
          ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == 0 && _selectedIndex == 0) {
            _resetToWelcome();
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Bible'),
          BottomNavigationBarItem(icon: Icon(Icons.hub), label: 'Study Hub'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildReaderView() {
    if (_selectedBook == null) {
      return _buildVerseTab(_continuityMap, _parenthesesMap);
    }
    if (_selectedBook == "") {
      return _buildBookTab();
    }
    if (_selectedChapter == null) return _buildChapterTab();
    if (_selectedVerse == null && _chapterVerses.isNotEmpty) return _buildVerseGridTab();
    return _buildVerseTab(_continuityMap, _parenthesesMap);
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
    if (_selectedBook == null || _selectedChapter == null) {
      if (_dailyVerse == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildWelcomePage(_dailyVerse!, cont, par);
    }
    return BibleReaderView(bookName: _selectedBook!, chapter: _selectedChapter!, allVersesOfChapter: _chapterVerses, currentStyle: _currentStyle, continuityMap: cont, parenthesesMap: par, targetVerse: _selectedVerse, targetWordIndex: _selectedWordIndex, audioService: _audioService, isAudioEnabled: widget.isAudioEnabled, fontSize: widget.fontSize, isDarkMode: widget.isDarkMode, highlightPhrase: _jumpHighlightPhrase, onChapterChange: (ch) => _onChapterNavigate(_selectedBook!, ch));
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
                const Text('Daily Bread', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.brown)),
                Text('${v.bookAbbreviation}${v.chapter}:${v.verse}:1-${v.wordCount}', 
                     style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
                Text(_getDynamicStyleName(_currentStyle), style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          ElevatedButton.icon(icon: const Icon(Icons.edit, size: 18), label: const Text('Change'), onPressed: _showVerseSelector),
        ],
      ),
      const SizedBox(height: 20),
      _buildWelcomeSection('AKJV 1611 PCE circa 1900', Text(v.text, textAlign: TextAlign.center, style: TextStyle(fontSize: widget.fontSize, fontStyle: FontStyle.italic)), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.standard)),
      _buildWelcomeSection('Superscript KJV', _buildArrayContent(v), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.superscript)),
      _buildWelcomeSection('Mathematics KJV 1', _buildMathContent(v, cont, par, BibleViewStyle.mathematics), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematics)),
      _buildWelcomeSection('Mathematics KJV 2', _buildMathContent(v, cont, par, BibleViewStyle.mathematics2), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematics2)),
      _buildWelcomeSection('Mathematics KJV UNCONSTRAINT', _buildMathContent(v, cont, par, BibleViewStyle.mathematicsUnconstraint), () => _jumpToDetailedLocation(v.book, v.chapter, v.verse, BibleViewStyle.mathematicsUnconstraint)),
      const SizedBox(height: 20),
      const Text("OR SELECT FROM LIBRARY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
      const SizedBox(height: 10),
      ElevatedButton.icon(onPressed: () => setState(() => _selectedBook = ""), icon: const Icon(Icons.library_books), label: const Text("BROWSE ALL BOOKS")),
    ]));
  }

  Widget _buildMathContent(BibleVerse v, Map<String, String> cont, Map<String, String> par, BibleViewStyle style) {
    final words = BibleLogic.applyContinuity(v, cont, parenthesesMap: par, style: style);
    
    final Color baseColor = Colors.white;
    final Color functionColor = Colors.redAccent;
    final Color glowColor = Colors.cyanAccent;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(8.0),
      child: Wrap(alignment: WrapAlignment.center, children: words.map((mw) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: RichText(text: TextSpan(children: [
        if (mw.hasLeadingSpace) const TextSpan(text: ' '),
        ...mw.parts.map((p) {
          final Color partColor = p.isRed ? functionColor : baseColor;
          final Color partGlow = p.isRed ? Colors.red : glowColor;
          
          return TextSpan(text: p.text, style: TextStyle(
            color: partColor, 
            fontSize: widget.fontSize, 
            fontWeight: FontWeight.bold,
            fontFamily: 'Courier', 
            shadows: [
              Shadow(blurRadius: 2.0, color: partGlow, offset: const Offset(0, 0)),
              Shadow(blurRadius: 12.0, color: partGlow.withOpacity(0.8), offset: const Offset(0, 0)),
              Shadow(blurRadius: 25.0, color: partGlow.withOpacity(0.6), offset: const Offset(0, 0)),
            ],
          ));
        })
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
        height: MediaQuery.of(context).size.height * 0.8,
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
                  ListTile(
                    title: const Text('Audio Quality'),
                    trailing: DropdownButton<AudioQuality>(
                      value: widget.audioQuality,
                      items: const [
                        DropdownMenuItem(value: AudioQuality.high, child: Text('High (Piper)')),
                        DropdownMenuItem(value: AudioQuality.medium, child: Text('Medium (Piper)')),
                        DropdownMenuItem(value: AudioQuality.low, child: Text('Low (Piper)')),
                      ],
                      onChanged: (q) { widget.onAudioQualityChanged(q!); Navigator.pop(context); }
                    ),
                  ),
                  ListTile(
                    title: const Text('Font Size'),
                    subtitle: Slider(
                      value: widget.fontSize,
                      min: 12, max: 36, divisions: 12,
                      label: widget.fontSize.round().toString(),
                      onChanged: (v) => widget.onFontSizeChanged(v),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
