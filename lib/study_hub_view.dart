import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database_service.dart';
import 'download_service.dart';
import 'bible_service.dart';
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
  final DownloadService _downloadService = DownloadService();
  final BibleService _bibleService = BibleService();

  final Map<String, double> _downloadProgress = {};
  final TextEditingController _dictController = TextEditingController();
  final TextEditingController _subsetFilterController = TextEditingController();
  
  bool _isInterpreting = false;
  List<VectorSpaceRow> _vectorSpaceRows = [];
  VectorDirection _selectedDirection = VectorDirection.both;
  ViewMode _selectedView = ViewMode.limitTable;
  double _nValue = 3.0;
  bool _buildAsBook = false;
  
  int? _subsetStart;
  int? _subsetEnd;
  int? _totalRecords;

  // Selected definitions: Map<LocationOfWord, Map<DefinitionPhrase, DefinitionLocation>>
  final Map<String, Map<String, String>> _selectedDefinitions = {};

  final String _legendText = """LEGEND:
 WTOTAG:where two or three are gathered(Mat18:20:2-7)
 CSTWS: comparing spiritual things with spiritual.(1Co2:13:20-24)
 not yea and nay, but in him = yea.(2Co1:19:23-31)""";

  @override
  void dispose() {
    _dictController.dispose();
    _subsetFilterController.dispose();
    super.dispose();
  }

  void _checkCount() async {
    final query = _dictController.text.trim();
    if (query.isEmpty) return;
    
    final count = await _dbService.countSearchMatches(query);
    setState(() {
      _totalRecords = count;
    });
  }

  void _runInterpretation() async {
    final query = _dictController.text.trim();
    if (query.isEmpty) return;

    _applySubsetFilter(_subsetFilterController.text);

    setState(() {
      _isInterpreting = true;
      _vectorSpaceRows = [];
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

      if (mounted) {
        setState(() {
          _vectorSpaceRows = results;
          _isInterpreting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isInterpreting = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  void _applySubsetFilter(String value) {
    if (value.isEmpty) { 
      _subsetStart = null; 
      _subsetEnd = null; 
      return; 
    }
    final range = value.split('-');
    if (range.length == 2) {
      _subsetStart = int.tryParse(range[0].trim());
      _subsetEnd = int.tryParse(range[1].trim());
    } else {
      final single = int.tryParse(value.trim());
      if (single != null) {
        _subsetStart = single;
        _subsetEnd = single;
      }
    }
  }

  List<VectorSpaceRow> get _filteredRows => _vectorSpaceRows;

  String _getStyleLabel() {
    switch (widget.currentStyle) {
      case BibleViewStyle.standard: return "AKJV 1611 PCE";
      case BibleViewStyle.superscript: return "Superscript KJV";
      case BibleViewStyle.mathematics: return "Mathematics KJV 1";
      case BibleViewStyle.mathematics2: return "Mathematics KJV 2";
      case BibleViewStyle.mathematicsUnconstraint: return "Mathematics KJV UNCONSTRAINT";
    }
  }

  Widget _buildStyledPhrase(BibleMatch m, {bool isBullet = false}) {
    final locationStyle = TextStyle(fontSize: 8, color: widget.isDarkMode ? Colors.amber[200] : Colors.grey[700], fontFamily: 'Courier');
    final bulletStr = isBullet ? "◦ " : "";
    
    if (widget.currentStyle == BibleViewStyle.standard) {
      return Text("$bulletStr${m.phrase}(${m.location})", 
        style: TextStyle(fontSize: 10, color: widget.isDarkMode ? Colors.white70 : Colors.black87));
    }
    
    if (widget.currentStyle == BibleViewStyle.superscript) {
      return RichText(
        text: TextSpan(
          children: [
            if (isBullet) const TextSpan(text: "◦ ", style: TextStyle(fontSize: 10, color: Colors.grey)),
            ...m.verse.styledWords.sublist(m.startWord - 1, m.endWord).expand((w) => [
              TextSpan(text: w.text, style: TextStyle(color: widget.isDarkMode ? Colors.white70 : Colors.black, fontSize: 10, fontStyle: w.isItalic ? FontStyle.italic : FontStyle.normal)),
              WidgetSpan(child: Transform.translate(offset: const Offset(0, -5), child: Text('${w.index}', style: const TextStyle(fontSize: 7, color: Colors.blue)))),
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
          if (isBullet) const TextSpan(text: "◦ ", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ...selectedWords.expand((mw) => [
            if (mw.hasLeadingSpace) const TextSpan(text: ' '),
            ...mw.parts.map((p) => TextSpan(text: p.text, style: TextStyle(
              color: p.isRed ? Colors.redAccent : Colors.white,
              fontSize: 10,
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
        content: const Text("Include the Limit Table Grid (WYSIWYG) in the export?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No, Dict only")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Include Grid")),
        ],
      ),
    );

    if (includeLimitTable == null) return;

    StringBuffer sb = StringBuffer();
    final String viewTypeLabel = _selectedView == ViewMode.limitTable ? "Limit Table" : "Use";
    final title = "Title: $viewTypeLabel for \"${_dictController.text}\" in the ${_getStyleLabel()}";
    
    sb.writeln(title);
    sb.writeln(_legendText);
    sb.writeln("-" * 60);
    sb.writeln("");

    if (includeLimitTable) {
      String header = "BIBLEWORD | LOCATION";
      if (_selectedDirection == VectorDirection.before || _selectedDirection == VectorDirection.both) {
        header += " | WTOTAG_BEFORE(⟼) | CSTWS_BEFORE(⟼)";
      }
      if (_selectedDirection == VectorDirection.after || _selectedDirection == VectorDirection.both) {
        header += " | WTOTAG_AFTER(⟻) | CSTWS_AFTER(⟻)";
      }
      sb.writeln(header);
      sb.writeln("-" * header.length);

      for (var row in _filteredRows) {
        // WYSIWYG logic: iterate through all possible match indices
        int maxBefore = max(row.witnessesBefore.length, row.spiritualsBefore.length);
        int maxAfter = max(row.witnessesAfter.length, row.spiritualsAfter.length);
        int totalSubRows = max(maxBefore, maxAfter);
        if (totalSubRows == 0) totalSubRows = 1;

        for (int i = 0; i < totalSubRows; i++) {
          String line = "${row.word} | ${row.location}";
          
          if (_selectedDirection == VectorDirection.before || _selectedDirection == VectorDirection.both) {
            String wb = i < row.witnessesBefore.length ? "${row.witnessesBefore[i].phrase}(${row.witnessesBefore[i].location})" : "";
            String sbCol = i < row.spiritualsBefore.length ? "${row.spiritualsBefore[i].phrase}(${row.spiritualsBefore[i].location})" : "";
            line += " | $wb | $sbCol";
          }
          if (_selectedDirection == VectorDirection.after || _selectedDirection == VectorDirection.both) {
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
        final locationOfWord = entry.key;
        final wordText = _vectorSpaceRows.firstWhere((r) => r.location == locationOfWord).word;
        for (var def in entry.value.entries) {
          final defPhrase = def.key;
          final defLocation = def.value;
          sb.writeln("$wordText($locationOfWord) = $defPhrase($defLocation)");
        }
      }
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Exported to Clipboard (WYSIWYG Paired Rows)")));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.grid_on), text: "Wholesome Words"),
              Tab(icon: Icon(Icons.functions), text: "Your Strong Reasons"),
              Tab(icon: Icon(Icons.library_books), text: "Audio Books"),
              Tab(icon: Icon(Icons.note), text: "Study Notes"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAnalysisTab(),
                _buildConstantsGallery(),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dictController,
                      decoration: InputDecoration(
                        hintText: "Enter Phrase (e.g. charity)",
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.info_outline, color: Colors.blue),
                          onPressed: _checkCount,
                          tooltip: "Check Total Occurrences",
                        ),
                      ),
                      onSubmitted: (_) => _runInterpretation(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _subsetFilterController,
                      decoration: const InputDecoration(
                        hintText: "e.g. 1-10",
                        labelText: "Range",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isInterpreting ? null : _runInterpretation,
                    icon: const Icon(Icons.calculate),
                    label: const Text("GENERATE"),
                  ),
                ],
              ),
              if (_totalRecords != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    children: [
                      Text(
                        "Total Instances Found: $_totalRecords. Select a Range (e.g. 1-10) and click GENERATE.",
                        style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        "*Using smaller ranges results in smoother and faster App performance.",
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Tooltip(message: "ε>0", child: Text("Precision (N): ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(
                    child: Slider(
                      value: _nValue, min: 2, max: 10, divisions: 8,
                      label: _nValue.toInt().toString(),
                      onChanged: (val) => setState(() { _nValue = val; }),
                      onChangeEnd: (val) { if (_dictController.text.isNotEmpty) _runInterpretation(); },
                    ),
                  ),
                  Text(_nValue.toInt().toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 20),
                  const Text("Build Book", style: TextStyle(fontSize: 12)),
                  Checkbox(value: _buildAsBook, onChanged: (v) => setState(() => _buildAsBook = v!)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SegmentedButton<VectorDirection>(
                    segments: const [
                      ButtonSegment(value: VectorDirection.before, label: Text("BEFORE", style: TextStyle(fontSize: 10))),
                      ButtonSegment(value: VectorDirection.after, label: Text("AFTER", style: TextStyle(fontSize: 10))),
                      ButtonSegment(value: VectorDirection.both, label: Text("BOTH", style: TextStyle(fontSize: 10))),
                    ],
                    selected: {_selectedDirection},
                    onSelectionChanged: (newSelection) {
                      setState(() { _selectedDirection = newSelection.first; });
                      if (_dictController.text.isNotEmpty) _runInterpretation();
                    },
                  ),
                  SegmentedButton<ViewMode>(
                    segments: const [
                      ButtonSegment(value: ViewMode.limitTable, label: Text("GRID", style: TextStyle(fontSize: 10))),
                      ButtonSegment(value: ViewMode.dictionary, label: Text("DICT", style: TextStyle(fontSize: 10))),
                    ],
                    selected: {_selectedView},
                    onSelectionChanged: (newSelection) => setState(() { _selectedView = newSelection.first; }),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_isInterpreting)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_vectorSpaceRows.isNotEmpty)
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text("Showing instances ${_subsetStart ?? 1} to ${_subsetEnd ?? (_subsetStart ?? 1) + _vectorSpaceRows.length - 1} of $_totalRecords", style: const TextStyle(fontSize: 10, color: Colors.black54)),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _handleChoiceExport,
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text("Export Choice", style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(
                          _selectedView == ViewMode.limitTable 
                            ? 'Limit Table for "${_dictController.text}" in the ${_getStyleLabel()}'
                            : 'Use of "${_dictController.text}" in the ${_getStyleLabel()}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown),
                        ),
                      ),
                      if (_selectedView == ViewMode.limitTable) ...[
                        const Text("LEGEND:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        Text(_legendText.replaceFirst("LEGEND:\n", ""), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: (widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript) ? Colors.black : null,
                    child: _selectedView == ViewMode.limitTable ? _buildLimitTable(_filteredRows) : _buildDictionaryTable(_filteredRows),
                  ),
                ),
              ],
            ),
          )
        else
          const Expanded(child: Center(child: Text("BIBLE VECTOR SPACE Analysis.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))),
      ],
    );
  }

  Widget _buildLimitTable(List<VectorSpaceRow> rows) {
    final ScrollController horizontalScroll = ScrollController();
    return Scrollbar(
      controller: horizontalScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          controller: horizontalScroll,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            dataRowMaxHeight: double.infinity,
            headingRowColor: MaterialStateProperty.all(Colors.red[50]!),
            border: TableBorder.all(color: Colors.grey[300]!),
            columns: [
              const DataColumn(label: Text('BIBLEWORD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.red))),
              const DataColumn(label: Text('LOCATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.red))),
              if (_selectedDirection == VectorDirection.before || _selectedDirection == VectorDirection.both) ...[
                const DataColumn(label: Text('WTOTAG_BEFORE(⟼)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.red))),
                const DataColumn(label: Text('CSTWS_BEFORE(⟼)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.red))),
              ],
              if (_selectedDirection == VectorDirection.after || _selectedDirection == VectorDirection.both) ...[
                const DataColumn(label: Text('WTOTAG_AFTER(⟻)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.red))),
                const DataColumn(label: Text('CSTWS_AFTER(⟻)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.red))),
              ],
            ],
            rows: rows.map((row) {
              return DataRow(
                cells: [
                  DataCell(Text(row.word, style: const TextStyle(fontSize: 11, fontFamily: 'Courier'))),
                  DataCell(InkWell(child: Text(row.location, style: const TextStyle(fontSize: 11, color: Colors.blue, fontFamily: 'Courier')), onTap: () => widget.onJumpToLocation(row.location))),
                  if (_selectedDirection == VectorDirection.before || _selectedDirection == VectorDirection.both) ...[
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.witnessesBefore.map((w) => _buildStyledPhrase(w)).toList())),
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.spiritualsBefore.map((s) => _buildStyledPhrase(s, isBullet: true)).toList())),
                  ],
                  if (_selectedDirection == VectorDirection.after || _selectedDirection == VectorDirection.both) ...[
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.witnessesAfter.map((w) => _buildStyledPhrase(w)).toList())),
                    DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: row.spiritualsAfter.map((s) => _buildStyledPhrase(s, isBullet: true)).toList())),
                  ],
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildDictionaryTable(List<VectorSpaceRow> rows) {
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final List<BibleMatch> definitions = [...row.spiritualsBefore, ...row.spiritualsAfter];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.maxFinite, color: Colors.grey[900],
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text("${row.word} (${row.location})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: Colors.blue, size: 16),
                    onPressed: () => widget.onJumpToLocation(row.location),
                  ),
                ],
              ),
            ),
            ...definitions.map((def) {
              final isSelected = _selectedDefinitions[row.location]?.containsKey(def.phrase) ?? false;
              return ListTile(
                dense: true,
                title: _buildStyledPhrase(def),
                trailing: Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val!) {
                        _selectedDefinitions.putIfAbsent(row.location, () => {})[def.phrase] = def.location;
                      } else {
                        _selectedDefinitions[row.location]?.remove(def.phrase);
                      }
                    });
                  },
                ),
              );
            }),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  Widget _buildConstantsGallery() {
    return FutureBuilder<List<String>>(
      future: _dbService.getConstants(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final constants = snapshot.data!;
        return ListView.builder(
          itemCount: constants.length,
          itemBuilder: (context, index) {
            final c = constants[index];
            return ListTile(
              title: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  await _dbService.deleteConstant(c);
                  setState(() {});
                },
              ),
              onTap: () {
                _dictController.text = c;
                _runInterpretation();
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBooksList() {
    return FutureBuilder<List<String>>(
      future: _dbService.getBooks(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(snapshot.data![index]),
            onTap: () => widget.onJumpToLocation(snapshot.data![index]),
          ),
        );
      },
    );
  }

  Widget _buildNotesList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dbService.getNotes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final n = snapshot.data![index];
            return ListTile(
              title: Text(n['title'] ?? 'No Title'),
              subtitle: Text(n['location'] ?? ''),
              onTap: () => widget.onJumpToLocation(n['location']),
            );
          },
        );
      },
    );
  }
}
