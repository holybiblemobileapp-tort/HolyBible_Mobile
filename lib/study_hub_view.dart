import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'database_service.dart';
import 'bible_model.dart';
import 'bible_logic.dart';

class StudyHubView extends StatefulWidget {
  final Function(String) onJumpToLocation;
  final BibleViewStyle currentStyle;
  final Map<String, String> continuityMap;
  final Map<String, String> parenthesesMap;
  final double fontSize;
  final bool isDarkMode;

  const StudyHubView({
    super.key, 
    required this.onJumpToLocation,
    required this.currentStyle,
    required this.continuityMap,
    required this.parenthesesMap,
    required this.fontSize,
    required this.isDarkMode,
  });

  @override
  State<StudyHubView> createState() => _StudyHubViewState();
}

enum VectorDirection { before, after, both }
enum ViewMode { limitTable, dictionary }

class _StudyHubViewState extends State<StudyHubView> {
  final DatabaseService _dbService = DatabaseService();
  final TextEditingController _dictController = TextEditingController();
  final TextEditingController _subsetFilterController = TextEditingController();
  
  // Persistent scroll controllers for the GRID view
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();
  
  bool _isInterpreting = false;
  List<VectorSpaceRow> _vectorSpaceRows = [];
  VectorDirection _selectedDirection = VectorDirection.both;
  ViewMode _selectedView = ViewMode.limitTable;
  double _nValue = 3.0;
  
  int? _subsetStart;
  int? _subsetEnd;
  int? _totalRecords;

  final Map<String, Map<String, String>> _selectedDefinitions = {};

  final String _legendText = "WTOTAG: Mat18:20:2-7 | CSTWS: 1Co2:13:20-24 | YEA: 2Co1:19:23-31";

  // Surgical filtering: Filter Grid rows based on Dictionary selections
  List<VectorSpaceRow> get _filteredRows {
    if (_selectedDefinitions.isEmpty) return _vectorSpaceRows;
    
    List<VectorSpaceRow> filtered = [];
    for (var originalRow in _vectorSpaceRows) {
      if (!_selectedDefinitions.containsKey(originalRow.location)) continue;
      
      final selections = _selectedDefinitions[originalRow.location]!;
      final filteredRow = VectorSpaceRow(word: originalRow.word, location: originalRow.location);
      
      for (int i = 0; i < originalRow.spiritualsBefore.length; i++) {
        final def = originalRow.spiritualsBefore[i];
        if (selections.containsKey(def.phrase) && selections[def.phrase] == def.location) {
          if (i < originalRow.witnessesBefore.length) filteredRow.witnessesBefore.add(originalRow.witnessesBefore[i]);
          filteredRow.spiritualsBefore.add(def);
        }
      }
      
      for (int i = 0; i < originalRow.spiritualsAfter.length; i++) {
        final def = originalRow.spiritualsAfter[i];
        if (selections.containsKey(def.phrase) && selections[def.phrase] == def.location) {
          if (i < originalRow.witnessesAfter.length) filteredRow.witnessesAfter.add(originalRow.witnessesAfter[i]);
          filteredRow.spiritualsAfter.add(def);
        }
      }
      
      if (filteredRow.spiritualsBefore.isNotEmpty || filteredRow.spiritualsAfter.isNotEmpty) {
        filtered.add(filteredRow);
      }
    }
    return filtered;
  }

  @override
  void dispose() {
    _dictController.dispose();
    _subsetFilterController.dispose();
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  void _checkCount() async {
    final query = _dictController.text.trim();
    if (query.isEmpty) return;
    final count = await _dbService.countSearchMatches(query);
    setState(() => _totalRecords = count);
  }

  void _runInterpretation() async {
    final query = _dictController.text.trim();
    if (query.isEmpty) return;
    _applySubsetFilter(_subsetFilterController.text);
    setState(() {
      _isInterpreting = true;
      _selectedDefinitions.clear();
    });
    try {
      int? limit;
      int? offset;
      if (_subsetStart != null && _subsetEnd != null) {
        offset = (_subsetStart! - 1).clamp(0, 100000);
        limit = (_subsetEnd! - offset).clamp(1, 100000);
      }
      final results = await _dbService.getVectorSpaceGrid(
        query, 
        n: _nValue.toInt(),
        includeBefore: _selectedDirection == VectorDirection.before || _selectedDirection == VectorDirection.both,
        includeAfter: _selectedDirection == VectorDirection.after || _selectedDirection == VectorDirection.both,
        limit: limit,
        offset: offset,
      );
      results.sort((a, b) => a.bookOrder.compareTo(b.bookOrder));
      if (mounted) setState(() { _vectorSpaceRows = results; _isInterpreting = false; });
    } catch (e) {
      if (mounted) { setState(() => _isInterpreting = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"))); }
    }
  }

  void _applySubsetFilter(String value) {
    if (value.isEmpty) { _subsetStart = null; _subsetEnd = null; return; }
    final range = value.split('-');
    if (range.length == 2) {
      _subsetStart = int.tryParse(range[0].trim());
      _subsetEnd = int.tryParse(range[1].trim());
    } else {
      final single = int.tryParse(value.trim());
      if (single != null) { _subsetStart = single; _subsetEnd = single; }
    }
  }

  String _getStyleLabel() {
    switch (widget.currentStyle) {
      case BibleViewStyle.standard: return "AKJV 1611 PCE";
      case BibleViewStyle.superscript: return "Superscript KJV";
      case BibleViewStyle.mathematics: return "MathKJVP";
      case BibleViewStyle.mathematics2: return "MathKJVS";
      case BibleViewStyle.mathematicsUnconstraint: return "MathKJVT";
    }
  }

  Widget _buildStyledPhrase(BibleMatch m, {bool isBullet = false}) {
    final double fs = widget.fontSize * 0.7;
    final locationStyle = TextStyle(fontSize: fs * 0.7, color: widget.isDarkMode ? Colors.amber[200] : Colors.grey[700], fontFamily: 'Courier');
    final bulletStr = isBullet ? "◦ " : "";
    
    if (widget.currentStyle == BibleViewStyle.standard) {
      return Text("$bulletStr${m.phrase}(${m.location})", 
        style: TextStyle(fontSize: fs, color: widget.isDarkMode ? Colors.white70 : Colors.black87));
    }
    
    if (widget.currentStyle == BibleViewStyle.superscript) {
      return RichText(
        text: TextSpan(
          children: [
            if (isBullet) TextSpan(text: "◦ ", style: TextStyle(fontSize: fs, color: Colors.grey)),
            ...m.verse.styledWords.sublist(m.startWord - 1, m.endWord).expand((w) => [
              TextSpan(text: w.text, style: TextStyle(color: widget.isDarkMode ? Colors.white70 : Colors.black, fontSize: fs, fontStyle: w.isItalic ? FontStyle.italic : FontStyle.normal)),
              WidgetSpan(child: Transform.translate(offset: const Offset(0, -5), child: Text('${w.index}', style: TextStyle(fontSize: fs * 0.6, color: Colors.blue)))),
              const TextSpan(text: ' '),
            ]),
            TextSpan(text: "(${m.location})", style: locationStyle),
          ],
        ),
      );
    }

    final words = BibleLogic.applyContinuity(m.verse, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
    final selectedWords = words.where((mw) => mw.original.index >= m.startWord && mw.original.index <= m.endWord).toList();

    return RichText(
      text: TextSpan(
        children: [
          if (isBullet) TextSpan(text: "◦ ", style: TextStyle(fontSize: fs, color: Colors.grey)),
          ...selectedWords.expand((mw) => [
            if (mw.hasLeadingSpace) const TextSpan(text: ' '),
            ...mw.parts.map((p) => TextSpan(text: p.text, style: TextStyle(
              color: p.isRed ? Colors.redAccent : (widget.isDarkMode || widget.currentStyle != BibleViewStyle.standard ? Colors.white : Colors.black),
              fontSize: fs,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
              shadows: [Shadow(blurRadius: 2.0, color: p.isRed ? Colors.red : Colors.cyanAccent)],
            )))
          ]),
          TextSpan(text: "(${m.location})", style: locationStyle),
        ],
      ),
    );
  }

  Future<void> _handleChoiceExport() async {
    bool? includeLimitTable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Export Choices"),
        content: Text(_selectedDefinitions.isNotEmpty 
          ? "Export ONLY the ${_selectedDefinitions.length} selected related records from the Limit Table?" 
          : "Include the full Limit Table Grid (WYSIWYG) in the export?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No, Dict only")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Include Grid")),
        ],
      ),
    );
    if (includeLimitTable == null) return;
    StringBuffer sb = StringBuffer();
    sb.writeln("Title: Limit Table for \"${_dictController.text}\" in the ${_getStyleLabel()}");
    sb.writeln(_legendText);
    sb.writeln("-" * 60 + "\n");
    
    if (includeLimitTable) {
      String header = "BIBLEWORD | LOCATION";
      if (_selectedDirection != VectorDirection.after) header += " | WTOTAG_BEFORE | CSTWS_BEFORE";
      if (_selectedDirection != VectorDirection.before) header += " | WTOTAG_AFTER | CSTWS_AFTER";
      sb.writeln(header);
      
      final rowsToExport = _filteredRows;
      for (var row in rowsToExport) {
        int totalSubRows = max(max(row.witnessesBefore.length, row.spiritualsBefore.length), max(row.witnessesAfter.length, row.spiritualsAfter.length));
        if (totalSubRows == 0) totalSubRows = 1;
        for (int i = 0; i < totalSubRows; i++) {
          String line = "${row.word} | ${row.location}";
          if (_selectedDirection != VectorDirection.after) {
            String wb = i < row.witnessesBefore.length ? "${row.witnessesBefore[i].phrase}(${row.witnessesBefore[i].location})" : "";
            String sbCol = i < row.spiritualsBefore.length ? "${row.spiritualsBefore[i].phrase}(${row.spiritualsBefore[i].location})" : "";
            line += " | $wb | $sbCol";
          }
          if (_selectedDirection != VectorDirection.before) {
            String wa = i < row.witnessesAfter.length ? "${row.witnessesAfter[i].phrase}(${row.witnessesAfter[i].location})" : "";
            String sa = i < row.spiritualsAfter.length ? "${row.spiritualsAfter[i].phrase}(${row.spiritualsAfter[i].location})" : "";
            line += " | $wa | $sa";
          }
          sb.writeln(line);
        }
      }
      sb.writeln("\n");
    }
    
    if (_selectedDefinitions.isNotEmpty) {
      sb.writeln("--- DICTIONARY ENTRIES ---");
      for (var entry in _selectedDefinitions.entries) {
        final row = _vectorSpaceRows.firstWhere((r) => r.location == entry.key);
        for (var def in entry.value.entries) sb.writeln("${row.word}(${entry.key}) = ${def.key}(${def.value})");
      }
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exported Selection to Clipboard")));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Container(
            width: double.infinity, color: Colors.brown[50], padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text("Study to shew thyself approved unto God,", textAlign: TextAlign.center, style: TextStyle(fontStyle: FontStyle.italic, color: Colors.brown, fontSize: widget.fontSize * 0.6, fontWeight: FontWeight.bold)),
          ),
          TabBar(
            isScrollable: true, labelColor: Colors.brown, unselectedLabelColor: Colors.grey, indicatorColor: Colors.brown,
            tabs: const [
              Tab(icon: Icon(Icons.grid_on, size: 18), text: "Wholesome Words"),
              Tab(icon: Icon(Icons.functions, size: 18), text: "Your Strong Reasons"),
              Tab(icon: Icon(Icons.library_books, size: 18), text: "Audio Books"),
              Tab(icon: Icon(Icons.note, size: 18), text: "Study Notes"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAnalysisTab(),
                _buildStrongReasonsTab(),
                _buildBooksList(),
                _buildNotesList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisTab() {
    final double fs = widget.fontSize * 0.7;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: TextField(controller: _dictController, style: TextStyle(fontSize: fs), decoration: InputDecoration(hintText: "Phrase (e.g. charity)", isDense: true, border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.info_outline, size: 18), onPressed: _checkCount)))),
                  const SizedBox(width: 8),
                  SizedBox(width: 80, child: TextField(controller: _subsetFilterController, style: TextStyle(fontSize: fs), decoration: const InputDecoration(hintText: "1-10", labelText: "Range", isDense: true, border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _isInterpreting ? null : _runInterpretation, child: const Text("GENERATE")),
                ],
              ),
              ExpansionTile(
                title: Text(_totalRecords != null ? "Total: $_totalRecords word instances found. Filter Active: ${_selectedDefinitions.isNotEmpty}" : "Analysis Controls", style: TextStyle(fontSize: fs * 0.8, fontWeight: FontWeight.bold, color: Colors.blue)),
                dense: true, visualDensity: VisualDensity.compact,
                children: [
                  Row(
                    children: [
                      Text(" N: ", style: TextStyle(fontSize: fs * 0.8)),
                      Expanded(child: Slider(value: _nValue, min: 2, max: 10, divisions: 8, onChanged: (v) => setState(() => _nValue = v))),
                      SegmentedButton<VectorDirection>(
                        segments: const [ButtonSegment(value: VectorDirection.before, label: Text("BEF", style: TextStyle(fontSize: 9))), ButtonSegment(value: VectorDirection.after, label: Text("AFT", style: TextStyle(fontSize: 9))), ButtonSegment(value: VectorDirection.both, label: Text("BOTH", style: TextStyle(fontSize: 9)))],
                        selected: {_selectedDirection}, onSelectionChanged: (s) => setState(() => _selectedDirection = s.first),
                      ),
                      const SizedBox(width: 8),
                      SegmentedButton<ViewMode>(
                        segments: const [ButtonSegment(value: ViewMode.limitTable, label: Text("GRID", style: TextStyle(fontSize: 9))), ButtonSegment(value: ViewMode.dictionary, label: Text("DICT", style: TextStyle(fontSize: 9)))],
                        selected: {_selectedView}, onSelectionChanged: (s) => setState(() => _selectedView = s.first),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_isInterpreting) const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_vectorSpaceRows.isNotEmpty) Expanded(
          flex: 4, 
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Expanded(child: Text(_legendText, style: TextStyle(fontSize: fs * 0.6, color: Colors.grey))),
                    if (_selectedDefinitions.isNotEmpty) 
                      Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: const Text("Clear Filter", style: TextStyle(fontSize: 9)), onPressed: () => setState(() => _selectedDefinitions.clear()))),
                    ElevatedButton.icon(onPressed: _handleChoiceExport, icon: const Icon(Icons.copy, size: 14), label: const Text("Export", style: TextStyle(fontSize: 11))),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Container(
                  color: (widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript) ? Colors.black : null,
                  child: _selectedView == ViewMode.limitTable ? _buildLimitTable(_filteredRows) : _buildDictionaryTable(_vectorSpaceRows),
                ),
              ),
            ],
          ),
        )
        else const Expanded(child: Center(child: Text("BIBLE VECTOR SPACE Analysis.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))),
      ],
    );
  }

  Widget _buildStrongReasonsTab() {
    return FutureBuilder<String>(
      future: rootBundle.loadString('assets/YOUR_STRONG_REASONS.md'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return Markdown(data: snapshot.data!, styleSheet: MarkdownStyleSheet(h1: const TextStyle(color: Colors.brown), h2: const TextStyle(color: Colors.blueGrey)));
      },
    );
  }

  Widget _buildLimitTable(List<VectorSpaceRow> rows) {
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
                  DataColumn(label: Text('WTOTAG_BEF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                  DataColumn(label: Text('CSTWS_BEF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                ],
                if (_selectedDirection != VectorDirection.before) ...[
                  DataColumn(label: Text('WTOTAG_AFT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                  DataColumn(label: Text('CSTWS_AFT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: fs * 0.8, color: Colors.red))),
                ],
              ],
              rows: rows.map((row) => DataRow(
                cells: [
                  DataCell(Text(row.word, style: TextStyle(fontSize: fs, fontFamily: 'Courier'))),
                  DataCell(InkWell(child: Text(row.location, style: TextStyle(fontSize: fs, color: Colors.blue, fontFamily: 'Courier')), onTap: () => widget.onJumpToLocation(row.location))),
                  if (_selectedDirection != VectorDirection.after) ...[
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.witnessesBefore.map((w) => _buildStyledPhrase(w)).toList())),
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.spiritualsBefore.map((s) => _buildStyledPhrase(s, isBullet: true)).toList())),
                  ],
                  if (_selectedDirection != VectorDirection.before) ...[
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.witnessesAfter.map((w) => _buildStyledPhrase(w)).toList())),
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.spiritualsAfter.map((s) => _buildStyledPhrase(s, isBullet: true)).toList())),
                  ],
                ],
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDictionaryTable(List<VectorSpaceRow> rows) {
    final double fs = widget.fontSize * 0.7;
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final List<BibleMatch> definitions = [...row.spiritualsBefore, ...row.spiritualsAfter];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: double.maxFinite, color: Colors.grey[900], padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Text("${row.word} (${row.location})", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fs))),
            ...definitions.map((def) => ListTile(
              dense: true, visualDensity: VisualDensity.compact, title: _buildStyledPhrase(def),
              trailing: Checkbox(value: _selectedDefinitions[row.location]?.containsKey(def.phrase) ?? false, onChanged: (v) {
                setState(() { if (v!) { _selectedDefinitions.putIfAbsent(row.location, () => {})[def.phrase] = def.location; } else { _selectedDefinitions[row.location]?.remove(def.phrase); } });
              }),
            )),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  Widget _buildBooksList() {
    return FutureBuilder<List<String>>(future: _dbService.getBooks(), builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) => ListTile(title: Text(snapshot.data![index]), onTap: () => widget.onJumpToLocation(snapshot.data![index])));
    });
  }

  Widget _buildNotesList() {
    return FutureBuilder<List<Map<String, dynamic>>>(future: _dbService.getNotes(), builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return ListView.builder(itemCount: snapshot.data!.length, itemBuilder: (context, index) => ListTile(title: Text(snapshot.data![index]['title'] ?? 'No Title'), subtitle: Text(snapshot.data![index]['location'] ?? ''), onTap: () => widget.onJumpToLocation(snapshot.data![index]['location'])));
    });
  }
}
