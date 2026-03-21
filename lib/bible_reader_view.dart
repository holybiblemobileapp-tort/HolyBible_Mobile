import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'bible_model.dart';
import 'bible_logic.dart';
import 'audio_service.dart';
import 'download_service.dart';

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
  StreamSubscription? _audioSubscription;
  String? _anchorWordId;
  String? _lastScrolledId;
  int _scrollRetryCount = 0;

  @override
  void initState() {
    super.initState();
    _rebuildKeys();
    _audioSubscription = widget.audioService.currentFragmentIdStream.listen((id) {
      if (mounted && id != _activeWordNotifier.value) {
        _activeWordNotifier.value = id;
        if (id != null) _scrollToId(id);
      }
    });
    if (widget.targetVerse != null) _triggerInitialScroll();
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

  @override
  void didUpdateWidget(BibleReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chapter != oldWidget.chapter || widget.bookName != oldWidget.bookName) {
      _rebuildKeys();
      _selectionNotifier.value = {};
      _anchorWordId = null;
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
          Scrollable.ensureVisible(key.currentContext!, alignment: 0.3, duration: Duration(milliseconds: force ? 500 : 800), curve: Curves.easeInOutCubic);
          if (force) _scrollRetryCount = 0;
        } else if (force && _scrollRetryCount < 10) {
          _scrollRetryCount++;
          Future.delayed(Duration(milliseconds: 100 * _scrollRetryCount), _attemptScroll);
        }
      }
    } catch (_) {}
  }

  String _getSelectionText(Set<String> selection, {BibleViewStyle? style}) {
    if (selection.isEmpty) return "";
    final targetStyle = style ?? widget.currentStyle;
    List<Map<String, dynamic>> allWords = [];
    for (var v in widget.allVersesOfChapter) {
      for (var w in v.styledWords) {
        allWords.add({'id': "${v.id}:${w.index}", 'v': v, 'w': w});
      }
    }
    List<List<Map<String, dynamic>>> segments = [];
    List<Map<String, dynamic>> currentSegment = [];
    for (var wordEntry in allWords) {
      if (selection.contains(wordEntry['id'])) {
        currentSegment.add(wordEntry);
      } else if (currentSegment.isNotEmpty) {
        segments.add(currentSegment);
        currentSegment = [];
      }
    }
    if (currentSegment.isNotEmpty) segments.add(currentSegment);
    List<String> combinedTextParts = [];
    List<String> combinedLocParts = [];
    for (var segment in segments) {
      Map<int, List<int>> verseToWords = {};
      List<int> verseOrder = [];
      for (var entry in segment) {
        BibleVerse v = entry['v'];
        if (!verseToWords.containsKey(v.id)) { verseToWords[v.id] = []; verseOrder.add(v.id); }
        verseToWords[v.id]!.add(entry['w'].index);
      }
      List<String> segmentLocs = [];
      List<String> segmentText = [];
      for (var verseId in verseOrder) {
        final v = widget.allVersesOfChapter.firstWhere((v) => v.id == verseId);
        final indices = verseToWords[verseId]!;
        final styled = BibleLogic.getStyledPhrase(v, indices, targetStyle, widget.continuityMap, widget.parenthesesMap);
        segmentText.add(styled);
        final loc = BibleLogic.formatLocation(v.bookAbbreviation, v.chapter, v.verse, indices.first, indices.last);
        segmentLocs.add(loc);
      }
      combinedTextParts.add(segmentText.join(' '));
      combinedLocParts.add(segmentLocs.join('_'));
    }
    return "${combinedTextParts.join(' ')} (${combinedLocParts.join(', ')})";
  }

  void _shareContent(Set<String> selection) {
    if (selection.isEmpty) return;
    StringBuffer buffer = StringBuffer();
    buffer.writeln("Shared from Holy Bible Mobile");
    buffer.writeln("=" * 30);
    for (var style in BibleViewStyle.values) {
      buffer.writeln("\n[${BibleLogic.getReadingLabel(style)}]");
      buffer.writeln(_getSelectionText(selection, style: style));
    }
    Share.share(buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final bool isPreface = widget.bookName.toLowerCase() == 'preface' || (widget.allVersesOfChapter.isNotEmpty && widget.allVersesOfChapter.first.bookAbbreviation == 'Pre');
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;
    return Column(children: [
      _buildSelectionToolbar(),
      if (!isPreface) _buildHeader(isMath),
      Expanded(child: Container(color: isMath ? Colors.black : null, child: isPreface ? _buildPrefaceView() : _buildCanonicalView())),
      _buildAudioControls(),
    ]);
  }

  Widget _buildSelectionToolbar() {
    return ValueListenableBuilder<Set<String>>(valueListenable: _selectionNotifier, builder: (context, selection, _) {
      if (selection.isEmpty) return const SizedBox.shrink();
      return Container(color: Colors.blueGrey[100], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [
        Text('${selection.length} selected', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
        const Spacer(), 
        IconButton(icon: const Icon(Icons.copy, color: Colors.black, size: 20), onPressed: () { 
          Clipboard.setData(ClipboardData(text: _getSelectionText(selection))); 
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selection copied to clipboard'))); 
        }),
        IconButton(icon: const Icon(Icons.share, color: Colors.black, size: 20), onPressed: () => _shareContent(selection)),
      ]));
    });
  }

  Widget _buildHeader(bool isMath) {
    String label = BibleLogic.getReadingLabel(widget.currentStyle);
    Color labelColor = Colors.grey;
    String breadthLabel = "Breadth";
    switch (widget.currentStyle) {
      case BibleViewStyle.mathematics: labelColor = Colors.green; breadthLabel = "Tongue of the Mathematicians"; break;
      case BibleViewStyle.mathematics2: labelColor = Colors.blue; breadthLabel = "Tongue of the Mathematicians"; break;
      case BibleViewStyle.mathematicsUnconstraint: labelColor = Colors.orange; breadthLabel = "Tongue of the Mathematicians"; break;
      default: break;
    }
    return Container(
      color: isMath ? Colors.grey[900] : Colors.grey[200], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: labelColor, fontFamily: isMath ? 'Courier' : null))),
        Expanded(child: Text(breadthLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, fontFamily: isMath ? 'Courier' : null))),
        IconButton(icon: const Icon(Icons.share, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _shareContent(widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toSet()), tooltip: "Share Chapter", color: isMath ? Colors.grey : Colors.black54),
      ]),
    );
  }

  Widget _buildCanonicalView() {
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;
    return ListView.builder(
      controller: _scrollController, itemCount: widget.allVersesOfChapter.length,
      itemBuilder: (context, index) {
        final v = widget.allVersesOfChapter[index];
        final bool isVerse0 = v.verse == 0;
        final bool isSuperscript = widget.currentStyle == BibleViewStyle.superscript;
        final locationText = isSuperscript ? '${v.bookAbbreviation}${v.chapter}:${v.verse}' : '${v.bookAbbreviation}${v.chapter}:${v.verse}:1-${v.wordCount}';
        return Container(
          key: _verseKeys[v.id], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!isVerse0) SizedBox(width: 110, child: Row(children: [
              Expanded(child: Text(locationText, style: TextStyle(fontWeight: FontWeight.bold, color: widget.isDarkMode || isMath ? Colors.grey[400] : Colors.grey, fontSize: 10, fontFamily: isMath ? 'Courier' : null))),
              const SizedBox(width: 4),
              IconButton(icon: const Icon(Icons.share, size: 14), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () => _shareContent(v.styledWords.map((w) => "${v.id}:${w.index}").toSet()), color: Colors.blue[300], tooltip: "Share Verse"),
            ])) else const SizedBox(width: 110),
            Expanded(child: _buildVerseContent(v, isVerse0: isVerse0)),
          ]),
        );
      },
    );
  }

  Widget _buildPrefaceView() {
    final List<Widget> items = [];
    List<BibleVerse> currentParagraph = [];
    for (var v in widget.allVersesOfChapter) {
      if (widget.chapter == 0) {
        items.add(_buildParagraph([v], center: true, isTitle: v.verse == 0));
      } else {
        currentParagraph.add(v);
        if (v.text.contains('¶') || v.verse == widget.allVersesOfChapter.last.verse) {
          items.add(_buildParagraph(currentParagraph));
          currentParagraph = [];
        }
      }
    }
    return ListView(controller: _scrollController, padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8), children: items);
  }

  Widget _buildParagraph(List<BibleVerse> verses, {bool center = false, bool isTitle = false}) {
    List<Widget> wordWidgets = [];
    for (var v in verses) {
      double fontSize = widget.fontSize;
      if (isTitle) fontSize *= 1.5;
      final mathWords = BibleLogic.applyContinuity(v, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
      
      for (var mw in mathWords) {
        wordWidgets.add(_renderWord(v, mw, customSize: fontSize, isBold: isTitle));
      }
      if (v.text.contains('¶')) wordWidgets.add(const Text('¶ ', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isTitle ? Colors.brown.withOpacity(0.05) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Wrap(alignment: center ? WrapAlignment.center : WrapAlignment.start, spacing: 0, runSpacing: 6, children: wordWidgets)
    );
  }

  Widget _renderWord(BibleVerse v, MathWord mw, {double? customSize, bool isBold = false}) {
    final wordId = '${v.id}:${mw.original.index}';
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;
    return ValueListenableBuilder<String?>(valueListenable: _activeWordNotifier, builder: (context, activeId, _) {
      return ValueListenableBuilder<Set<String>>(valueListenable: _selectionNotifier, builder: (context, selection, _) {
        final bool isSelected = selection.contains(wordId);
        final bool isActive = activeId == wordId;
        final Color symbolColor = widget.currentStyle == BibleViewStyle.mathematics2 ? Colors.blue : (widget.currentStyle == BibleViewStyle.mathematicsUnconstraint ? Colors.orange : Colors.red);
        
        return GestureDetector(
          onTap: () => _handleWordTap(wordId),
          onLongPress: () => _handleLongPress(wordId),
          child: Container(
            decoration: BoxDecoration(color: isSelected ? Colors.blue.withOpacity(0.3) : (isActive ? Colors.amber.withOpacity(0.4) : Colors.transparent), borderRadius: BorderRadius.circular(2)),
            child: RichText(text: TextSpan(children: [
              if (mw.hasLeadingSpace) const TextSpan(text: ' '),
              ...mw.parts.map((p) {
                if (widget.currentStyle == BibleViewStyle.superscript && !p.isParenthesis) {
                   return TextSpan(children: [
                     TextSpan(text: p.text, style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black, fontSize: customSize ?? widget.fontSize, fontStyle: p.isItalic ? FontStyle.italic : FontStyle.normal, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
                     WidgetSpan(child: Transform.translate(offset: const Offset(0, -8), child: Text('${mw.original.index}', style: TextStyle(fontSize: (customSize ?? widget.fontSize) * 0.55, color: Colors.blue, fontWeight: FontWeight.bold)))),
                   ]);
                }
                return TextSpan(text: p.text, style: TextStyle(
                  color: p.isRed ? symbolColor : (isMath || widget.isDarkMode ? Colors.white : Colors.black),
                  fontSize: customSize ?? widget.fontSize,
                  fontWeight: (p.isRed || isBold) ? FontWeight.bold : FontWeight.normal,
                  fontStyle: p.isItalic ? FontStyle.italic : FontStyle.normal,
                  fontFamily: isMath ? 'Courier' : null,
                  shadows: p.isRed && isMath ? [Shadow(blurRadius: 2.0, color: symbolColor)] : null,
                ));
              })
            ])),
          ),
        );
      });
    });
  }

  Widget _buildVerseContent(BibleVerse v, {bool isVerse0 = false}) {
    double fontSize = widget.fontSize;
    if (isVerse0) fontSize *= 0.75;
    final mathWords = BibleLogic.applyContinuity(v, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
    return Wrap(children: mathWords.map((mw) => _renderWord(v, mw, customSize: fontSize)).toList());
  }

  void _handleWordTap(String id) {
    if (widget.isAudioEnabled && widget.audioService.isAudioLoaded) widget.audioService.seekToFragment(id);
    final bool isMultiSelectPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
    Set<String> current = Set.from(_selectionNotifier.value);
    if (isMultiSelectPressed) {
      if (current.contains(id)) current.remove(id); else current.add(id);
      _anchorWordId = id;
    } else if (_anchorWordId != null) {
      final allIds = widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toList();
      int start = allIds.indexOf(_anchorWordId!);
      int end = allIds.indexOf(id);
      if (start != -1 && end != -1) {
        current.clear();
        for (int i = min(start, end); i <= max(start, end); i++) current.add(allIds[i]);
      }
      _anchorWordId = null;
    } else { current = {id}; _anchorWordId = id; }
    _selectionNotifier.value = current;
  }

  void _handleLongPress(String id) {
    _anchorWordId = id; _selectionNotifier.value = {id}; HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Start point set. Tap another word to select range.'), duration: Duration(seconds: 1)));
  }

  Widget _buildAudioControls() { return Container(color: Colors.brown[50], padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => widget.onChapterChange(widget.chapter - 1)), IconButton(icon: const Icon(Icons.play_arrow, size: 48), onPressed: () {}), IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => widget.onChapterChange(widget.chapter + 1))])); }
}
