import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'bible_model.dart';
import 'bible_logic.dart';
import 'audio_service.dart';
import 'download_service.dart';
import 'neon_visualizer.dart';

class BibleReaderView extends StatefulWidget {
  final String bookName;
  final int chapter;
  final List<BibleVerse> allVersesOfChapter;
  final BibleViewStyle currentStyle;
  final Map<String, String> continuityMap;
  final Map<String, String> parenthesesMap;
  final int? targetVerse;
  final int? targetWordIndex;
  final AudioService audioService;
  final bool isAudioEnabled;
  final double fontSize;
  final bool isDarkMode;
  final String? highlightPhrase;
  final Function(int) onChapterChange;

  const BibleReaderView({
    super.key,
    required this.bookName,
    required this.chapter,
    required this.allVersesOfChapter,
    required this.currentStyle,
    required this.continuityMap,
    required this.parenthesesMap,
    this.targetVerse,
    this.targetWordIndex,
    required this.audioService,
    required this.isAudioEnabled,
    required this.fontSize,
    required this.isDarkMode,
    this.highlightPhrase,
    required this.onChapterChange,
  });

  @override
  State<BibleReaderView> createState() => _BibleReaderViewState();
}

class _BibleReaderViewState extends State<BibleReaderView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _verseKeys = {};
  final ValueNotifier<String?> _activeWordNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<Set<String>> _selectionNotifier = ValueNotifier<Set<String>>({});
  final DownloadService _downloadService = DownloadService();
  StreamSubscription? _audioSubscription;
  String? _anchorWordId;
  String? _lastScrolledId;
  
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _isChapterDownloaded = true;
  int _scrollRetryCount = 0;

  @override
  void initState() {
    super.initState();
    _checkDownloadStatus();
    _rebuildKeys();
    
    _audioSubscription = widget.audioService.currentFragmentIdStream.listen((id) {
      if (mounted && id != _activeWordNotifier.value) {
        _activeWordNotifier.value = id;
        if (id != null) _scrollToId(id);
      }
    });
    
    if (widget.targetVerse != null) {
      _triggerInitialScroll();
    }
  }

  void _rebuildKeys() {
    _verseKeys.clear();
    for (var v in widget.allVersesOfChapter) {
      _verseKeys[v.id] = GlobalKey();
    }
  }

  void _triggerInitialScroll() {
    _scrollRetryCount = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), _attemptScroll);
    });
  }

  void _attemptScroll() {
    if (!mounted || widget.targetVerse == null) return;
    try {
      final verse = widget.allVersesOfChapter.firstWhere((v) => v.verse == widget.targetVerse);
      _scrollToId("${verse.id}:${widget.targetWordIndex ?? 1}", force: true);
    } catch (_) {}
  }

  Future<void> _checkDownloadStatus() async {
    if (widget.allVersesOfChapter.isEmpty) return;
    final bookAbbr = widget.allVersesOfChapter.first.bookAbbreviation;
    final downloaded = await _downloadService.isBookDownloaded(bookAbbr, widget.chapter);
    if (mounted) setState(() => _isChapterDownloaded = downloaded);
  }

  @override
  void didUpdateWidget(BibleReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chapter != oldWidget.chapter || widget.bookName != oldWidget.bookName) {
      _checkDownloadStatus();
      _rebuildKeys();
      _selectionNotifier.value = {};
    }
    if (widget.targetVerse != oldWidget.targetVerse && widget.targetVerse != null) {
      _triggerInitialScroll();
    }
  }

  @override
  void dispose() {
    _audioSubscription?.cancel();
    _activeWordNotifier.dispose();
    _selectionNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToId(String wordId, {bool force = false}) {
    if (!force && _lastScrolledId == wordId) return;
    _lastScrolledId = wordId;
    try {
      final parts = wordId.split(':');
      final verseId = int.tryParse(parts[0]);
      if (verseId != null) {
        final key = _verseKeys[verseId];
        if (key != null && key.currentContext != null) {
          Scrollable.ensureVisible(
            key.currentContext!,
            alignment: 0.3,
            duration: Duration(milliseconds: force ? 500 : 800),
            curve: Curves.easeInOutCubic,
          );
          if (force) _scrollRetryCount = 0;
        } else if (force && _scrollRetryCount < 10) {
          _scrollRetryCount++;
          Future.delayed(Duration(milliseconds: 100 * _scrollRetryCount), _attemptScroll);
        }
      }
    } catch (_) {}
  }

  String _getSelectionText(Set<String> selection) {
    final allIds = widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toList();
    final selectedSorted = allIds.where((id) => selection.contains(id)).toList();
    if (selectedSorted.isEmpty) return "";

    List<String> results = [];
    Map<int, List<int>> spanWords = {};
    for (var id in selectedSorted) {
      final p = id.split(':');
      spanWords.putIfAbsent(int.parse(p[0]), () => []).add(int.parse(p[1]));
    }

    for (var entry in spanWords.entries) {
      final v = widget.allVersesOfChapter.firstWhere((v) => v.id == entry.key);
      final styled = BibleLogic.getStyledPhrase(v, entry.value, widget.currentStyle, widget.continuityMap, widget.parenthesesMap);
      final loc = BibleLogic.formatLocation(v.bookAbbreviation, v.chapter, v.verse, entry.value.first, entry.value.last);
      results.add("$styled($loc)");
    }
    return results.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final bool isPreface = widget.bookName.toLowerCase() == 'preface' || (widget.allVersesOfChapter.isNotEmpty && widget.allVersesOfChapter.first.bookAbbreviation == 'Pre');
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;

    return Column(children: [
      _buildSelectionToolbar(),
      if (!isPreface) _buildHeader(isMath),
      Expanded(
          child: Container(
        color: isMath ? Colors.black : null,
        child: isPreface ? _buildPrefaceView() : _buildCanonicalView(),
      )),
      _buildAudioControls(),
    ]);
  }

  Widget _buildSelectionToolbar() {
    return ValueListenableBuilder<Set<String>>(
        valueListenable: _selectionNotifier,
        builder: (context, selection, _) {
          if (selection.isEmpty) return const SizedBox.shrink();
          return Container(
            color: Colors.blueGrey[100],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text('${selection.length} selected', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.copy, color: Colors.black),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _getSelectionText(selection)));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied Sync Text')));
                    }),
              ],
            ),
          );
        });
  }

  Widget _buildHeader(bool isMath) {
    String label = "KEY";
    String tooltip = "HeightDepth:Length:Breadth";
    Color labelColor = Colors.grey;
    String breadthLabel = "Breadth";

    switch (widget.currentStyle) {
      case BibleViewStyle.superscript:
        label = "ARRAY";
        tooltip = "HeightDepth:Length";
        breadthLabel = "Counting One By One";
        break;
      case BibleViewStyle.mathematics:
        label = "PROPORTION";
        labelColor = Colors.green;
        breadthLabel = "Tongue of the Mathematicians";
        break;
      case BibleViewStyle.mathematics2:
        label = "BALANCE";
        labelColor = Colors.blue;
        breadthLabel = "Tongue of the Mathematicians";
        break;
      case BibleViewStyle.mathematicsUnconstraint:
        label = "JOIN";
        labelColor = const Color(0xFFFF6347); // Tomato
        breadthLabel = "Tongue of the Mathematicians";
        break;
      default:
        break;
    }

    return Container(
      color: isMath ? Colors.grey[900] : Colors.grey[200],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Tooltip(
              message: tooltip,
              child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: labelColor)),
            ),
          ),
          Expanded(
            child: Text(breadthLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildCanonicalView() {
    return ListView.builder(
      controller: _scrollController,
      itemCount: widget.allVersesOfChapter.length,
      itemBuilder: (context, index) {
        final v = widget.allVersesOfChapter[index];
        final bool isVerse0 = v.verse == 0;
        final bool isSuperscript = widget.currentStyle == BibleViewStyle.superscript;
        final locationText = isSuperscript ? '${v.bookAbbreviation}${v.chapter}:${v.verse}' : '${v.bookAbbreviation}${v.chapter}:${v.verse}:1-${v.wordCount}';

        return Container(
          key: _verseKeys[v.id],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!isVerse0) 
              SizedBox(width: 110, child: Text(locationText, style: TextStyle(fontWeight: FontWeight.bold, color: widget.isDarkMode ? Colors.grey[400] : Colors.grey, fontSize: 10)))
            else
              const SizedBox(width: 110),
            Expanded(child: _buildVerseContent(v, isVerse0: isVerse0)),
          ]),
        );
      },
    );
  }

  Widget _buildPrefaceView() {
    final List<Widget> items = [];
    List<BibleVerse> currentParagraph = [];
    final int chapter = widget.chapter;

    for (var v in widget.allVersesOfChapter) {
      if (chapter == 0) {
        // Section 1: Centered
        items.add(_buildParagraph([v], center: true));
      } else if (chapter == 1 || chapter == 2) {
        // Section 2 & 3: Epistle & Translators
        currentParagraph.add(v);
        if (v.text.contains('¶')) {
          items.add(_buildParagraph(currentParagraph));
          currentParagraph = [];
        }
      } else if (chapter == 17) {
        // Section 4: Hybrid
        if (v.verse >= 3 && v.verse <= 5) {
          currentParagraph.add(v);
          if (v.verse == 5) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
        } else {
          // Verses 6-19 remain unchanged
          items.add(_buildParagraph([v]));
        }
      }
    }
    if (currentParagraph.isNotEmpty) {
      items.add(_buildParagraph(currentParagraph));
    }
    return ListView(controller: _scrollController, children: items);
  }

  Widget _buildParagraph(List<BibleVerse> verses, {bool center = false}) {
    List<Widget> wordWidgets = [];
    for (var v in verses) {
      for (var w in v.styledWords) {
        wordWidgets.add(_buildWord(v, w));
      }
      if (v.text.contains('¶')) {
        wordWidgets.add(const Text('¶ ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)));
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Wrap(alignment: center ? WrapAlignment.center : WrapAlignment.start, children: wordWidgets),
    );
  }

  Widget _buildVerseContent(BibleVerse v, {bool isVerse0 = false}) {
    double fontSize = widget.fontSize;
    if (isVerse0) fontSize *= 0.75; // Small font for Author info

    if (widget.currentStyle == BibleViewStyle.standard) {
      return Wrap(children: v.styledWords.map((w) => _buildWord(v, w, customSize: fontSize)).toList());
    }
    if (widget.currentStyle == BibleViewStyle.superscript) {
      return Wrap(children: v.styledWords.map((w) => _buildSuperscriptWord(v, w, customSize: fontSize)).toList());
    }
    final mathWords = BibleLogic.applyContinuity(v, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
    return Wrap(children: mathWords.map((mw) => _buildMathWord(v, mw, customSize: fontSize)).toList());
  }

  Widget _buildWord(BibleVerse v, BibleWord w, {double? customSize}) {
    final wordId = '${v.id}:${w.index}';
    final isTarget = widget.targetVerse == v.verse;
    final isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;

    return ValueListenableBuilder<String?>(
      valueListenable: _activeWordNotifier,
      builder: (context, activeId, _) {
        final isActive = activeId == wordId;
        return ValueListenableBuilder<Set<String>>(
          valueListenable: _selectionNotifier,
          builder: (context, selection, _) {
            final isSelected = selection.contains(wordId);
            return GestureDetector(
              onTap: () => _handleWordTap(wordId),
              onLongPress: () => _handleSelection(wordId, isRange: true),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.3) : (isActive || isTarget ? Colors.amber.withOpacity(0.4) : Colors.transparent),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text('${w.text} ', style: TextStyle(fontSize: customSize ?? widget.fontSize, color: (isMath || widget.isDarkMode) ? Colors.white : Colors.black)),
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildSuperscriptWord(BibleVerse v, BibleWord w, {double? customSize}) {
    final wordId = '${v.id}:${w.index}';
    final isTarget = widget.targetVerse == v.verse;
    return ValueListenableBuilder<String?>(
      valueListenable: _activeWordNotifier,
      builder: (context, activeId, _) {
        final isActive = activeId == wordId;
        return ValueListenableBuilder<Set<String>>(
          valueListenable: _selectionNotifier,
          builder: (context, selection, _) {
            final isSelected = selection.contains(wordId);
            return GestureDetector(
              onTap: () => _handleWordTap(wordId),
              onLongPress: () => _handleSelection(wordId, isRange: true),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.3) : (isActive || isTarget ? Colors.amber.withOpacity(0.4) : Colors.transparent),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: RichText(text: TextSpan(children: [
                  TextSpan(text: '${w.text}', style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black, fontSize: customSize ?? widget.fontSize, fontStyle: w.isItalic ? FontStyle.italic : FontStyle.normal)),
                  WidgetSpan(child: Transform.translate(offset: const Offset(0, -10), child: Text('${w.index}', style: TextStyle(fontSize: (customSize ?? widget.fontSize) * 0.6, color: Colors.blue, fontWeight: FontWeight.bold)))),
                  const TextSpan(text: ' '),
                ])),
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildMathWord(BibleVerse v, MathWord mw, {double? customSize}) {
    final wordId = '${v.id}:${mw.original.index}';
    final isTarget = widget.targetVerse == v.verse;
    
    Color symbolColor = Colors.red;
    if (widget.currentStyle == BibleViewStyle.mathematics2) symbolColor = Colors.orange;
    if (widget.currentStyle == BibleViewStyle.mathematicsUnconstraint) symbolColor = const Color(0xFFFFD700); // Gold

    return ValueListenableBuilder<String?>(
      valueListenable: _activeWordNotifier,
      builder: (context, activeId, _) {
        final isActive = activeId == wordId;
        return ValueListenableBuilder<Set<String>>(
          valueListenable: _selectionNotifier,
          builder: (context, selection, _) {
            final isSelected = selection.contains(wordId);
            return GestureDetector(
              onTap: () => _handleWordTap(wordId),
              onLongPress: () => _handleSelection(wordId, isRange: true),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.3) : (isActive || isTarget ? Colors.amber.withOpacity(0.4) : Colors.transparent),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: RichText(text: TextSpan(children: [
                  if (mw.hasLeadingSpace) const TextSpan(text: ' '),
                  ...mw.parts.map((p) => TextSpan(text: p.text, style: TextStyle(
                    color: p.isRed ? symbolColor : (widget.isDarkMode ? Colors.white : Colors.black),
                    fontSize: customSize ?? widget.fontSize,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                    shadows: [Shadow(blurRadius: 2.0, color: p.isRed ? symbolColor : Colors.cyanAccent)]
                  )))
                ])),
              ),
            );
          }
        );
      }
    );
  }

  void _handleWordTap(String id) {
    if (widget.isAudioEnabled && widget.audioService.isAudioLoaded) widget.audioService.seekToFragment(id);
    _handleSelection(id);
  }

  void _handleSelection(String id, {bool isRange = false}) {
    Set<String> current = Set.from(_selectionNotifier.value);
    if (isRange && _anchorWordId != null) {
      final allIds = widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toList();
      int start = allIds.indexOf(_anchorWordId!);
      int end = allIds.indexOf(id);
      if (start != -1 && end != -1) {
        current.clear();
        for (int i = min(start, end); i <= max(start, end); i++) current.add(allIds[i]);
      }
    } else {
      current.clear(); current.add(id); _anchorWordId = id;
    }
    _selectionNotifier.value = current;
  }

  Widget _buildAudioControls() { return Container(color: Colors.brown[50], padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => widget.onChapterChange(widget.chapter - 1)), IconButton(icon: const Icon(Icons.play_arrow, size: 48), onPressed: () {}), IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => widget.onChapterChange(widget.chapter + 1))])); }
}
