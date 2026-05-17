import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'database_service.dart';
import 'bible_model.dart';
import 'bible_logic.dart';
import 'markdown_extensions.dart';

enum VectorDirection { before, after, both }
enum ViewMode { limitTable, dictionary }

class StudyHubView extends StatefulWidget {
  final double fontSize;
  final Function(String, {String? highlight}) onJumpToLocation;
  final BibleViewStyle currentStyle;
  final Map<String, String> continuityMap;
  final Map<String, String> parenthesesMap;
  final bool isDarkMode;

  const StudyHubView({
    super.key,
    required this.fontSize,
    required this.onJumpToLocation,
    required this.currentStyle,
    required this.continuityMap,
    required this.parenthesesMap,
    required this.isDarkMode,
  });

  @override
  State<StudyHubView> createState() => _StudyHubViewState();
}

class _StudyHubViewState extends State<StudyHubView> with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  final TextEditingController _dictController = TextEditingController();
  final TextEditingController _rangeController = TextEditingController();
  
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();
  
  bool _isInterpreting = false;
  List<VectorSpaceRow> _vectorSpaceRows = [];
  VectorDirection _selectedDirection = VectorDirection.both;
  ViewMode _selectedView = ViewMode.limitTable;
  double _nValue = 3.0;
  
  int _currentPage = 0;
  final int _pageSize = 100;
  int _totalRecords = 0;

  final Map<String, Set<String>> _selectedDefinitions = {};
  late Future<String> _strongReasonsFuture;

  final String _legendText = "↦ BEFORE | ↤ AFTER | ↦ ↤ BOTH | WTOTAG: Mat18:20:2-7";

  @override
  void initState() {
    super.initState();
    _strongReasonsFuture = rootBundle.loadString('assets/YOUR_STRONG_REASONS.md');
  }

  @override
  void dispose() {
    _dictController.dispose();
    _rangeController.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  void _runInterpretation({bool resetPage = true}) async {
    final query = _dictController.text.trim();
    if (query.isEmpty) return;
    
    int? subsetLimit;
    int? subsetOffset;
    
    final rangeText = _rangeController.text.trim();
    if (rangeText.isNotEmpty) {
      final parts = rangeText.split('-');
      if (parts.length == 2) {
        int start = int.tryParse(parts[0]) ?? 1;
        int end = int.tryParse(parts[1]) ?? start;
        subsetOffset = (start - 1).clamp(0, 1000000);
        subsetLimit = (end - start + 1).clamp(1, 1000);
      }
    }

    if (resetPage) _currentPage = 0;
    setState(() { _isInterpreting = true; _selectedDefinitions.clear(); });
    
    try {
      final count = await _dbService.countSearchMatches(query);
      final result = await _dbService.getVectorSpaceGrid(
        query, 
        n: _nValue.toInt(),
        includeBefore: _selectedDirection == VectorDirection.before || _selectedDirection == VectorDirection.both,
        includeAfter: _selectedDirection == VectorDirection.after || _selectedDirection == VectorDirection.both,
        limit: subsetLimit ?? _pageSize, 
        offset: subsetOffset ?? (_currentPage * _pageSize),
      );
      if (mounted) setState(() { _totalRecords = count; _vectorSpaceRows = result.rows; _isInterpreting = false; });
    } catch (e) {
      if (mounted) { setState(() => _isInterpreting = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
    }
  }

  void _toggleSelectAll(bool? selectAll) {
    if (selectAll == null) return;
    setState(() {
      if (selectAll) {
        for (var row in _vectorSpaceRows) {
          final defs = _selectedDefinitions.putIfAbsent(row.location, () => {});
          for (var p in row.witnessesBefore) defs.add(p.spiritual.phrase);
          for (var p in row.witnessesAfter) defs.add(p.spiritual.phrase);
        }
      } else {
        _selectedDefinitions.clear();
      }
    });
  }

  void _toggleSelection(String location, String phrase, bool selected) {
    setState(() {
      if (selected) {
        _selectedDefinitions.putIfAbsent(location, () => {}).add(phrase);
      } else {
        _selectedDefinitions[location]?.remove(phrase);
        if (_selectedDefinitions[location]?.isEmpty ?? false) _selectedDefinitions.remove(location);
      }
    });
  }

  void _nextPage() { if ((_currentPage + 1) * _pageSize < _totalRecords) { _currentPage++; _runInterpretation(resetPage: false); } }
  void _prevPage() { if (_currentPage > 0) { _currentPage--; _runInterpretation(resetPage: false); } }

  void _copyDictOutput() {
    if (_selectedDefinitions.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln("PHRASE: ${_dictController.text}");
    _selectedDefinitions.forEach((loc, witnesses) {
      buffer.writeln("$loc: ${witnesses.join(' ')}");
    });
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dictionary output copied to clipboard")));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4, 
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Container(
            color: Theme.of(context).appBarTheme.backgroundColor,
            child: TabBar(
              isScrollable: true, 
              labelColor: Colors.brown, 
              unselectedLabelColor: Colors.grey, 
              indicatorColor: Colors.brown,
              tabs: const [
                Tab(icon: Icon(Icons.grid_on, size: 18), text: "Wholesome Words", height: 60), 
                Tab(icon: Icon(Icons.functions, size: 18), text: "Your Strong Reasons", height: 60), 
                Tab(icon: Icon(Icons.note, size: 18), text: "Study Notes", height: 60),
                Tab(icon: Icon(Icons.library_books, size: 18), text: "Audio Book", height: 60), 
              ]
            ),
          ),
        ),
        body: Column(
          children: [
            Container(width: double.infinity, color: Colors.brown[50], padding: const EdgeInsets.symmetric(vertical: 4), child: Text("Study to shew thyself approved unto God,", textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic, color: Colors.brown, fontSize: widget.fontSize * 0.6, fontWeight: FontWeight.bold))),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(), 
                children: [
                  _buildAnalysisTab(), 
                  _buildStrongReasonsTab(), 
                  _buildNotesList(),
                  _buildBooksList(), 
                ]
              )
            ),
          ],
        ),
      )
    );
  }

  Widget _buildAnalysisTab() {
    final double fs = widget.fontSize * 0.7;
    final int startRange = (_currentPage * _pageSize) + 1;
    final int endRange = min((_currentPage + 1) * _pageSize, _totalRecords);
    bool allSelected = _vectorSpaceRows.isNotEmpty && _vectorSpaceRows.every((r) {
      final selectedCount = _selectedDefinitions[r.location]?.length ?? 0;
      final totalCount = r.witnessesBefore.length + r.witnessesAfter.length;
      return totalCount > 0 && selectedCount == totalCount;
    });

    return Column(children: [
      Padding(padding: const EdgeInsets.all(8.0), child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: _dictController, style: TextStyle(fontSize: fs), decoration: const InputDecoration(hintText: "Phrase (e.g. charity)", isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: TextField(controller: _rangeController, style: TextStyle(fontSize: fs), decoration: const InputDecoration(hintText: "1-10", labelText: "Range", isDense: true, border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _isInterpreting ? null : () => _runInterpretation(resetPage: true), child: const Text("GENERATE")),
        ]),
        ExpansionTile(
          title: Text(_totalRecords > 0 ? "Results: $startRange - $endRange of $_totalRecords" : "Analysis Controls", style: TextStyle(fontSize: fs * 0.8, fontWeight: FontWeight.bold, color: Colors.blue)), 
          visualDensity: VisualDensity.compact,
          children: [
            Row(children: [
              Text(" N: ${_nValue.toInt()}", style: TextStyle(fontSize: fs * 0.8, fontWeight: FontWeight.bold)),
              Expanded(child: Slider(value: _nValue, min: 2, max: 6, divisions: 4, label: _nValue.toInt().toString(), onChanged: (v) => setState(() => _nValue = v))),
              SegmentedButton<VectorDirection>(segments: const [ButtonSegment(value: VectorDirection.before, label: Text("BEF", style: TextStyle(fontSize: 9))), ButtonSegment(value: VectorDirection.after, label: Text("AFT", style: TextStyle(fontSize: 9))), ButtonSegment(value: VectorDirection.both, label: Text("BOTH", style: TextStyle(fontSize: 9)))], selected: {_selectedDirection}, onSelectionChanged: (s) => setState(() => _selectedDirection = s.first)),
              const SizedBox(width: 8),
              SegmentedButton<ViewMode>(segments: const [ButtonSegment(value: ViewMode.limitTable, label: Text("GRID", style: TextStyle(fontSize: 9))), ButtonSegment(value: ViewMode.dictionary, label: Text("DICT", style: TextStyle(fontSize: 9)))], selected: {_selectedView}, onSelectionChanged: (s) => setState(() => _selectedView = s.first)),
            ]),
          ],
        ),
      ])),
      if (_totalRecords > _pageSize) Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), color: Colors.grey[200], child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16), onPressed: _currentPage > 0 && !_isInterpreting ? _prevPage : null), Text("Page ${_currentPage + 1} ($startRange - $endRange)", style: TextStyle(fontSize: fs * 0.8, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 16), onPressed: endRange < _totalRecords && !_isInterpreting ? _nextPage : null)])),
      if (_isInterpreting) const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_vectorSpaceRows.isNotEmpty) Expanded(child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0), child: Row(children: [
          Expanded(child: Text(_legendText, style: TextStyle(fontSize: fs * 0.6, color: Colors.grey))),
          if (_selectedDefinitions.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: const Text("Clear Filter", style: TextStyle(fontSize: 9)), onPressed: () => setState(() => _selectedDefinitions.clear()))),
          IconButton(onPressed: _copyDictOutput, icon: const Icon(Icons.copy, size: 18), tooltip: "Export Selection"),
          const SizedBox(width: 12),
          Column(mainAxisSize: min(4, _vectorSpaceRows.length).toDouble() > 0 ? MainAxisSize.min : MainAxisSize.max, children: [
            const Text("Select All", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
            Checkbox(visualDensity: VisualDensity.compact, value: allSelected, onChanged: _toggleSelectAll),
          ]),
        ])),
        const Divider(height: 1),
        Expanded(child: Container(color: (widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript) ? Colors.black : null, child: _selectedView == ViewMode.limitTable ? _buildLimitTable() : _buildDictionaryTable())),
      ]))
      else const Expanded(child: Center(child: Text("BIBLE VECTOR SPACE Analysis.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))),
    ]);
  }

  Widget _buildStrongReasonsTab() => FutureBuilder<String>(
    future: _strongReasonsFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return Markdown(
        data: snapshot.data!,
        physics: const BouncingScrollPhysics(),
        extensionSet: md.ExtensionSet(
          [...md.ExtensionSet.gitHubFlavored.blockSyntaxes, LatexSyntax()],
          [...md.ExtensionSet.gitHubFlavored.inlineSyntaxes, InlineLatexSyntax(), PhraseSyntax()],
        ),
        builders: {
          'latex': LatexBuilder(currentStyle: widget.currentStyle, continuityMap: widget.continuityMap, parenthesesMap: widget.parenthesesMap, isDarkMode: widget.isDarkMode),
          'inlineLatex': InlineLatexBuilder(currentStyle: widget.currentStyle, continuityMap: widget.continuityMap, parenthesesMap: widget.parenthesesMap, isDarkMode: widget.isDarkMode),
          'phrase': PhraseBuilder(currentStyle: widget.currentStyle, continuityMap: widget.continuityMap, parenthesesMap: widget.parenthesesMap, isDarkMode: widget.isDarkMode),
        },
        styleSheet: MarkdownStyleSheet(
          h1: TextStyle(color: Colors.brown, fontSize: widget.fontSize * 1.2),
          h2: TextStyle(color: Colors.blueGrey, fontSize: widget.fontSize),
          p: TextStyle(fontSize: widget.fontSize * 0.8, height: 1.5),
          listBullet: TextStyle(fontSize: widget.fontSize * 0.8),
          tableBody: TextStyle(fontSize: widget.fontSize * 0.7),
          tableCellsPadding: const EdgeInsets.all(4),
        ),
      );
    },
  );

  Widget _buildLimitTable() {
    final double fs = widget.fontSize * 0.7;
    return Scrollbar(
      controller: _verticalScroll, thumbVisibility: true,
      child: Scrollbar(
        controller: _horizontalScroll, thumbVisibility: true,
        notificationPredicate: (notif) => notif.depth == 1,
        child: SingleChildScrollView(
          controller: _verticalScroll,
          child: SingleChildScrollView(
            controller: _horizontalScroll, scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 15, dataRowMaxHeight: double.infinity, headingRowHeight: 30,
              headingRowColor: MaterialStateProperty.all(Colors.red[50]!),
              border: TableBorder.all(color: Colors.grey[300]!),
              columns: [
                DataColumn(label: Text('BIBLEWORD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                DataColumn(label: Text('LOCATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                if (_selectedDirection != VectorDirection.after) ...[
                  DataColumn(label: Text('WTOTAG_BEF ↦', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                  DataColumn(label: Text('CSTWS_BEF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                ],
                if (_selectedDirection != VectorDirection.before) ...[
                  DataColumn(label: Text('↤ WTOTAG_AFT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                  DataColumn(label: Text('CSTWS_AFT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                ],
              ],
              rows: _vectorSpaceRows.map((row) => DataRow(
                cells: [
                  DataCell(Text(row.word, style: TextStyle(fontSize: fs, fontFamily: 'Courier', color: widget.isDarkMode ? Colors.white : Colors.black))),
                  DataCell(InkWell(child: Text(row.location, style: TextStyle(fontSize: fs, color: Colors.blue, fontFamily: 'Courier')), onTap: () => widget.onJumpToLocation(row.location))),
                  if (_selectedDirection != VectorDirection.after) ...[
                    DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 250), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.witnessesBefore.map((p) => _buildStyledPhrase(p.witness)).toList()))),
                    DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 250), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.witnessesBefore.map((p) => _buildStyledPhrase(p.spiritual, isBullet: true)).toList()))),
                  ],
                  if (_selectedDirection != VectorDirection.before) ...[
                    DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 250), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.witnessesAfter.map((p) => _buildStyledPhrase(p.witness)).toList()))),
                    DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 250), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.witnessesAfter.map((p) => _buildStyledPhrase(p.spiritual, isBullet: true)).toList()))),
                  ],
                ],
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDictionaryTable() {
    final double fs = widget.fontSize * 0.7;
    return ListView.builder(itemCount: _vectorSpaceRows.length, itemBuilder: (context, index) {
      final row = _vectorSpaceRows[index]; final List<BibleMatch> definitions = [...row.witnessesBefore.map((p) => p.spiritual), ...row.witnessesAfter.map((p) => p.spiritual)];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.maxFinite, color: Colors.grey[900], padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: InkWell(onTap: () => widget.onJumpToLocation(row.location), child: Text("${row.word} (${row.location})", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fs)))),
        ...definitions.map((def) => ListTile(dense: true, visualDensity: VisualDensity.compact, title: _buildStyledPhrase(def), trailing: Checkbox(value: _selectedDefinitions[row.location]?.contains(def.phrase) ?? false, onChanged: (v) => _toggleSelection(row.location, def.phrase, v!)))),
        const Divider(height: 1),
      ]);
    });
  }

  Widget _buildStyledPhrase(BibleMatch m, {bool isBullet = false}) {
    final double fs = widget.fontSize * 0.7;
    final locationStyle = TextStyle(fontSize: fs * 0.7, color: widget.isDarkMode ? Colors.amber[200] : Colors.grey[700], fontFamily: 'Courier');
    final bulletStr = isBullet ? "◦ " : "";
    final String styledText = m.phrase;
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;

    if (widget.currentStyle == BibleViewStyle.standard) {
      return Text("$bulletStr$styledText(${m.location})", style: TextStyle(fontSize: fs, color: widget.isDarkMode ? Colors.white70 : Colors.black87));
    }
    return RichText(text: TextSpan(children: [
      if (isBullet) TextSpan(text: "◦ ", style: TextStyle(fontSize: fs, color: Colors.grey)),
      TextSpan(text: styledText, style: TextStyle(color: isMath ? Colors.white : (widget.isDarkMode ? Colors.white70 : Colors.black), fontSize: fs, fontFamily: isMath ? 'Courier' : null, fontWeight: isMath ? FontWeight.bold : FontWeight.normal, shadows: isMath ? [const Shadow(blurRadius: 2.0, color: Colors.cyanAccent)] : null)),
      TextSpan(text: " (${m.location})", style: locationStyle),
    ]));
  }

  Widget _buildBooksList() => FutureBuilder<List<String>>(future: _dbService.getBooks(), builder: (context, snapshot) { if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) => ListTile(title: Text(snapshot.data![index]), onTap: () => widget.onJumpToLocation(snapshot.data![index]))); });
  Widget _buildNotesList() => FutureBuilder<List<Map<String, dynamic>>>(future: _dbService.getNotes(), builder: (context, snapshot) { if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) => ListTile(title: Text(snapshot.data![index]['title'] ?? 'No Title'), subtitle: Text(snapshot.data![index]['location'] ?? ''), onTap: () => widget.onJumpToLocation(snapshot.data![index]['location']))); });
}
