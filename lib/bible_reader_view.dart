import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'bible_model.dart';
import 'bible_logic.dart';
import 'audio_service.dart';

class BibleReaderView extends StatefulWidget {
  final List<BibleVerse> allVersesOfChapter;
  final String bookName;
  final int chapter;
  final double fontSize;
  final bool isDarkMode;
  final BibleViewStyle currentStyle;
  final Map<String, String> continuityMap;
  final Map<String, String> parenthesesMap;
  final bool isAudioEnabled;
  final AudioService audioService;
  final Function(double) onFontSizeChanged;
  final Function(bool) onAudioChanged;
  final Function(BibleViewStyle) onStyleChanged;
  final int? targetVerse;
  final int? targetWordIndex;
  final String? highlightPhrase;
  final Function(int)? onChapterChange;

  const BibleReaderView({
    super.key,
    required this.allVersesOfChapter,
    required this.bookName,
    required this.chapter,
    required this.fontSize,
    required this.isDarkMode,
    required this.currentStyle,
    required this.continuityMap,
    required this.parenthesesMap,
    required this.isAudioEnabled,
    required this.audioService,
    required this.onFontSizeChanged,
    required this.onAudioChanged,
    required this.onStyleChanged,
    this.targetVerse,
    this.targetWordIndex,
    this.highlightPhrase,
    this.onChapterChange,
  });

  @override
  State<BibleReaderView> createState() => _BibleReaderViewState();
}

class _BibleReaderViewState extends State<BibleReaderView> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<Set<String>> _selectionNotifier = ValueNotifier({});
  final ValueNotifier<String?> _activeWordNotifier = ValueNotifier(null);
  final Map<int, GlobalKey> _verseKeys = {};
  String? _anchorWordId;

  static const Map<String, int> _paulineLastChapters = {
    'Rom': 16, '1Co': 16, '2Co': 13, 'Gal': 6, 'Eph': 6, 'Phi': 4,
    'Col': 4, '1Th': 5, '2Th': 3, '1Ti': 6, '2Ti': 4, 'Tit': 3,
    'Phm': 1, 'Heb': 13
  };

  @override
  void initState() {
    super.initState();
    widget.audioService.currentFragmentIdStream.listen((id) {
      if (mounted) _activeWordNotifier.value = id;
    });
    
    _updateKeys();
    if (widget.targetVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
  }

  void _updateKeys() {
    _verseKeys.clear();
    for (var v in widget.allVersesOfChapter) {
      _verseKeys[v.verse] = GlobalKey();
    }
  }

  @override
  void didUpdateWidget(BibleReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allVersesOfChapter != oldWidget.allVersesOfChapter) {
      _updateKeys();
    }
    if (widget.targetVerse != oldWidget.targetVerse && widget.targetVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
  }

  void _scrollToTarget() {
    if (!mounted || widget.targetVerse == null) return;
    final key = _verseKeys[widget.targetVerse];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        alignment: 0.1, // Scroll to near the top
      );
    }
  }

  List<BibleVerse> _getDisplayVerses() {
    final List<BibleVerse> verses = List.from(widget.allVersesOfChapter);
    final String abbr = verses.isNotEmpty ? verses.first.bookAbbreviation : "";
    final bool isPauline = _paulineLastChapters.containsKey(abbr);
    final bool isLastChapter = _paulineLastChapters[abbr] == widget.chapter;
    if (isPauline && isLastChapter && verses.isNotEmpty) {
      int v0Idx = verses.indexWhere((v) => v.verse == 0);
      if (v0Idx != -1) { final v0 = verses.removeAt(v0Idx); verses.add(v0); }
    }
    return verses;
  }

  @override
  void dispose() { _scrollController.dispose(); _selectionNotifier.dispose(); _activeWordNotifier.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;
    final bool isPreface = widget.bookName.toLowerCase() == 'preface' || (widget.allVersesOfChapter.isNotEmpty && widget.allVersesOfChapter.first.bookAbbreviation == 'Pre');
    
    return Container(
      color: isMath ? Colors.black : (widget.isDarkMode ? Colors.black : Colors.white),
      child: Column(children: [
        _buildHeader(isMath), 
        Expanded(child: Stack(
          children: [
            isPreface ? _buildPrefaceView() : _buildStandardView(),
            Positioned(bottom: 20, left: 20, right: 20, child: ValueListenableBuilder<Set<String>>(valueListenable: _selectionNotifier, builder: (context, selection, _) { if (selection.isEmpty) return const SizedBox.shrink(); return _buildFloatingActionBar(selection); })),
          ],
        ))
      ]),
    );
  }

  Widget _buildFloatingActionBar(Set<String> selection) {
    return Material(elevation: 8, borderRadius: BorderRadius.circular(30), color: Colors.brown[800], child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [IconButton(icon: const Icon(Icons.copy, color: Colors.white), onPressed: () => _handleCopy(selection), tooltip: "Copy"), IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () => _handleShare(selection), tooltip: "Share"), IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectionNotifier.value = {}), tooltip: "Clear")])));
  }

  void _handleCopy(Set<String> selection) { String text = _getSelectedTextWithLocation(selection); Clipboard.setData(ClipboardData(text: text)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied to clipboard"), duration: Duration(seconds: 1))); }
  void _handleShare(Set<String> selection) { String text = _getSelectedTextWithLocation(selection); Share.share(text); }

  String _getSelectedTextWithLocation(Set<String> selection) {
    if (selection.isEmpty) return "";
    Map<int, List<int>> verseGroups = {};
    for (var id in selection) {
      var parts = id.split(':');
      int vId = int.parse(parts[0]);
      int wIdx = int.parse(parts[1]);
      verseGroups.putIfAbsent(vId, () => []).add(wIdx);
    }
    List<int> sortedVerseIds = verseGroups.keys.toList()..sort((a, b) {
      int idxA = widget.allVersesOfChapter.indexWhere((v) => v.id == a);
      int idxB = widget.allVersesOfChapter.indexWhere((v) => v.id == b);
      return idxA.compareTo(idxB);
    });
    StringBuffer sb = StringBuffer();
    String currentBook = ""; int lastChapter = -1; int lastVerse = -1; bool lastWasFullEnd = false;
    List<String> locRefs = [];
    for (int vId in sortedVerseIds) {
      final v = widget.allVersesOfChapter.firstWhere((v) => v.id == vId);
      List<int> indices = verseGroups[vId]!..sort();
      
      String styledText = BibleLogic.getStyledPhrase(v, indices, widget.currentStyle, widget.continuityMap, widget.parenthesesMap);
      if (sb.isNotEmpty) sb.write(" ");
      sb.write(styledText);

      List<String> ranges = [];
      if (indices.isNotEmpty) {
        int start = indices[0];
        int end = indices[0];
        for (int i = 1; i < indices.length; i++) {
          if (indices[i] == end + 1) {
            end = indices[i];
          } else {
            ranges.add(start == end ? "$start" : "$start-$end");
            start = indices[i];
            end = indices[i];
          }
        }
        ranges.add(start == end ? "$start" : "$start-$end");
      }
      
      String loc = "${v.bookAbbreviation}${v.chapter}:${v.verse}:${ranges.join(', ')}";
      bool isAdjacent = currentBook == v.bookAbbreviation && v.chapter == lastChapter && v.verse == lastVerse + 1;
      bool isContiguous = isAdjacent && lastWasFullEnd && indices.first == 1;

      if (isContiguous) {
        locRefs.add("_$loc");
      } else {
        if (locRefs.isNotEmpty) locRefs.add(", ");
        locRefs.add(loc);
      }
      currentBook = v.bookAbbreviation; 
      lastChapter = v.chapter; 
      lastVerse = v.verse;
      lastWasFullEnd = (indices.isNotEmpty && indices.last == v.wordCount);
    }
    return sb.toString() + "(" + locRefs.join("").replaceAll(", _", "_") + ")";
  }

  Widget _buildHeader(bool isMath) {
    final textColor = isMath ? Colors.white : Colors.brown;
    final activeVerse = widget.targetVerse != null 
        ? widget.allVersesOfChapter.firstWhere((v) => v.verse == widget.targetVerse, orElse: () => widget.allVersesOfChapter.first)
        : widget.allVersesOfChapter.first;

    final String selectionLabel = "${widget.bookName} | Ch ${widget.chapter} | V ${activeVerse.verse} | R 1-${activeVerse.wordCount}";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      decoration: BoxDecoration(
        color: isMath ? Colors.black : Colors.brown[50],
        border: Border(bottom: BorderSide(color: isMath ? Colors.white24 : Colors.brown.withOpacity(0.3)))
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                selectionLabel,
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 13, letterSpacing: 0.5),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: Icon(Icons.chevron_left, color: textColor, size: 28), onPressed: widget.onChapterChange != null ? () => widget.onChapterChange!(-1) : null, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              IconButton(icon: Icon(Icons.chevron_right, color: textColor, size: 28), onPressed: widget.onChapterChange != null ? () => widget.onChapterChange!(1) : null, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(widget.isAudioEnabled ? Icons.volume_up : Icons.volume_off, color: textColor, size: 22),
                onPressed: () => widget.onAudioChanged(!widget.isAudioEnabled),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<BibleViewStyle>(
                icon: Icon(Icons.style, color: textColor, size: 22),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                onSelected: widget.onStyleChanged,
                itemBuilder: (context) => BibleViewStyle.values.map((s) => PopupMenuItem(value: s, child: Text(BibleLogic.getReadingLabel(s), style: const TextStyle(fontSize: 12)))).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStandardView() {
    final List<BibleVerse> displayVerses = _getDisplayVerses();
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;
    final marginColor = BibleLogic.getMarginReferenceColor(widget.currentStyle, widget.isDarkMode);
    final headerLabel = BibleLogic.getStyleHeader(widget.currentStyle);
    final hover = BibleLogic.getStyleHoverTitle(widget.currentStyle);
    final breadthDesc = BibleLogic.getBreadthDescription(widget.currentStyle);
    
    return Column(children: [
      Container(
        width: double.infinity, 
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
        decoration: BoxDecoration(
          color: isMath ? Colors.white10 : Colors.grey.withOpacity(0.1),
          border: Border(bottom: BorderSide(color: isMath ? Colors.white24 : Colors.grey.withOpacity(0.3)))
        ),
        child: Row(
          children: [
            SizedBox(width: 85, child: Tooltip(message: hover, child: Text(headerLabel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isMath ? Colors.white70 : Colors.black87)))),
            const SizedBox(width: 10),
            Expanded(child: Tooltip(
              message: breadthDesc,
              child: Text(
                widget.currentStyle == BibleViewStyle.superscript ? "counting one by one, to find out the account:" : (isMath ? "TONGUE OF THE MATHEMATICIANS" : "READ"), 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: isMath ? Colors.white70 : Colors.black87)
              ),
            )),
          ],
        )
      ),
      Expanded(child: Theme(
        data: ThemeData(
          scrollbarTheme: ScrollbarThemeData(
            thumbColor: MaterialStateProperty.all(isMath ? Colors.brown[300] : Colors.brown[200]),
            trackColor: MaterialStateProperty.all(isMath ? Colors.white10 : Colors.black12),
            thickness: MaterialStateProperty.all(8.0),
            radius: const Radius.circular(10),
            thumbVisibility: MaterialStateProperty.all(true),
          )
        ),
        child: Scrollbar(
          thumbVisibility: true,
          controller: _scrollController,
          child: ListView.builder(
            controller: _scrollController, 
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100), 
            itemCount: displayVerses.length, 
            itemBuilder: (context, index) {
              final v = displayVerses[index];
              final bool isTarget = v.verse == widget.targetVerse;
              final bool isVerse0 = v.verse == 0;
              
              if (isVerse0) return Container(key: _verseKeys[v.verse], padding: const EdgeInsets.symmetric(vertical: 16.0), child: Center(child: _buildVerseContent(v, customScale: 0.8, forceItalic: true, isVerse0: true)));
              
              final loc = BibleLogic.formatLocation(v.bookAbbreviation, v.chapter, v.verse, 1, v.wordCount, isSuperscript: widget.currentStyle == BibleViewStyle.superscript);
              
              return Container(
                key: _verseKeys[v.verse],
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0), 
                margin: const EdgeInsets.only(bottom: 8), 
                decoration: isTarget ? BoxDecoration(
                  color: widget.isDarkMode ? Colors.amber.withOpacity(0.15) : Colors.amber.withOpacity(0.1), 
                  border: Border.all(color: Colors.amber[400]!, width: 1.0), 
                  borderRadius: BorderRadius.circular(4)
                ) : null, 
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    SizedBox(width: 85, child: Text(loc, style: TextStyle(fontSize: widget.fontSize * 0.55, color: marginColor, fontWeight: FontWeight.bold))), 
                    Expanded(child: _buildVerseContent(v))
                  ]
                )
              );
            }
          ),
        ),
      ))
    ]);
  }

  Widget _buildPrefaceView() {
    final List<Widget> items = [];
    if (widget.chapter == 0) {
      for (var v in widget.allVersesOfChapter) {
        double scale = 1.0; bool isItalic = false; bool isBold = false; bool skip = false;
        switch (v.verse) { case 0: skip = true; break; case 1: scale = 0.85; break; case 2: scale = 2.4; isBold = true; break; case 3: scale = 0.85; break; case 4: scale = 1.5; isBold = true; break; case 5: case 6: case 7: scale = 0.95; break; case 8: scale = 0.95; break; case 9: scale = 1.0; isItalic = true; break; case 10: case 11: scale = 1.1; break; default: scale = 0.8; }
        if (!skip) items.add(Container(key: _verseKeys[v.verse], child: _buildParagraph([v], center: true, customScale: scale, forceItalic: isItalic, forceBold: isBold)));
      }
    } else if (widget.chapter == 1) {
      List<BibleVerse> currentParagraph = [];
      for (int i = 0; i < widget.allVersesOfChapter.length; i++) {
        final v = widget.allVersesOfChapter[i];
        if (v.verse == 0) { items.add(Container(key: _verseKeys[v.verse], child: _buildParagraph([v], center: true, customScale: 1.4, forceBold: true))); items.add(const SizedBox(height: 24)); }
        else if (v.verse >= 1 && v.verse <= 7) { items.add(Container(key: _verseKeys[v.verse], child: _buildParagraph([v], center: true, customScale: 1.1, forceBold: true))); }
        else { currentParagraph.add(v); if (v.text.contains('¶') || i == widget.allVersesOfChapter.length - 1) { items.add(Container(key: _verseKeys[currentParagraph.first.verse], child: _buildParagraph(currentParagraph))); currentParagraph = []; } }
      }
    } else {
      List<BibleVerse> currentParagraph = [];
      for (int i = 0; i < widget.allVersesOfChapter.length; i++) {
        final v = widget.allVersesOfChapter[i];
        if (widget.chapter == 17) {
           if (v.verse >= 0 && v.verse <= 2) { items.add(Container(key: _verseKeys[v.verse], child: _buildParagraph([v], center: true, customScale: 1.3, forceBold: true))); if (v.verse == 2) items.add(const SizedBox(height: 24)); continue; }
           else if (v.verse >= 3 && v.verse <= 5) { currentParagraph.add(v); if (v.text.contains('¶') || v.verse == 5) { items.add(Container(key: _verseKeys[currentParagraph.first.verse], child: _buildParagraph(currentParagraph))); currentParagraph = []; } continue; }
           else if (v.verse >= 6) { items.add(Container(key: _verseKeys[v.verse], child: _buildParagraph([v], customScale: 1.0))); continue; }
        }
        if (v.verse == 0) { items.add(Container(key: _verseKeys[v.verse], child: _buildParagraph([v], center: true, customScale: 1.4, forceBold: true))); items.add(const SizedBox(height: 24)); }
        else if (v.verse == 1 && widget.chapter >= 2 && widget.chapter <= 16) { items.add(Container(key: _verseKeys[v.verse], child: _buildParagraph([v], center: true, customScale: 1.2, forceBold: true))); items.add(const SizedBox(height: 16)); }
        else { currentParagraph.add(v); if (v.text.contains('¶') || i == widget.allVersesOfChapter.length - 1) { items.add(Container(key: _verseKeys[currentParagraph.first.verse], child: _buildParagraph(currentParagraph))); currentParagraph = []; } }
      }
    }
    return ListView(controller: _scrollController, padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8), children: items);
  }

  Widget _buildParagraph(List<BibleVerse> verses, {bool center = false, double customScale = 1.0, bool forceItalic = false, bool forceBold = false}) {
    List<Widget> wordWidgets = []; bool isFirstWordOfParagraph = true;
    for (var v in verses) {
      double baseSize = widget.fontSize * customScale;
      final mathWords = BibleLogic.applyContinuity(v, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
      for (var mw in mathWords) { wordWidgets.add(_renderWord(v, mw, customSize: baseSize, isBold: forceBold, isItalic: forceItalic, forceSpace: !isFirstWordOfParagraph && mw.original.index == 1)); isFirstWordOfParagraph = false; }
    }
    return Container(margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.symmetric(horizontal: 24), alignment: center ? Alignment.center : Alignment.centerLeft, child: Wrap(alignment: center ? WrapAlignment.center : WrapAlignment.start, spacing: 0, runSpacing: 4, children: wordWidgets));
  }

  Widget _renderWord(BibleVerse v, MathWord mw, {double? customSize, bool isBold = false, bool isItalic = false, bool forceSpace = false}) {
    final wordId = '${v.id}:${mw.original.index}';
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;
    
    // Check if this word is part of the highlighted phrase
    bool isPhraseHighlight = false;
    if (widget.highlightPhrase != null && widget.targetVerse == v.verse) {
      final String wordText = mw.original.text.toLowerCase().replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), '');
      final List<String> highlightWords = widget.highlightPhrase!.toLowerCase().split(RegExp(r'\s+'));
      if (highlightWords.contains(wordText)) {
        isPhraseHighlight = true;
      }
    }

    return ValueListenableBuilder<String?>(valueListenable: _activeWordNotifier, builder: (context, activeId, _) {
      return ValueListenableBuilder<Set<String>>(valueListenable: _selectionNotifier, builder: (context, selection, _) {
        final bool isSelected = selection.contains(wordId); final bool isActive = activeId == wordId;
        final Color symbolColor = BibleLogic.getMathSymbolColor(widget.currentStyle);
        
        Decoration? decoration;
        if (isSelected) {
          decoration = BoxDecoration(color: Colors.blue.withOpacity(0.3), borderRadius: BorderRadius.circular(2));
        } else if (isActive) {
          decoration = BoxDecoration(color: Colors.amber.withOpacity(0.4), borderRadius: BorderRadius.circular(2));
        } else if (isPhraseHighlight) {
          decoration = BoxDecoration(color: Colors.amber.withOpacity(0.25), border: Border(bottom: BorderSide(color: Colors.amber[700]!, width: 1.5)));
        }

        return GestureDetector(
          onTap: () => _handleWordTap(wordId), 
          onLongPress: () => _handleLongPress(wordId), 
          child: Container(
            decoration: decoration, 
            child: RichText(text: TextSpan(children: [
              if (mw.hasLeadingSpace || forceSpace) const TextSpan(text: ' '),
              ...mw.parts.map((p) {
                if (widget.currentStyle == BibleViewStyle.superscript && !p.isParenthesis) {
                   return TextSpan(children: [TextSpan(text: p.text, style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black, fontSize: customSize ?? widget.fontSize, fontStyle: (p.isItalic || isItalic) ? FontStyle.italic : FontStyle.normal, fontWeight: (isBold || isPhraseHighlight) ? FontWeight.bold : FontWeight.normal)), WidgetSpan(child: Transform.translate(offset: const Offset(0, -8), child: Text('${mw.original.index}', style: TextStyle(fontSize: (customSize ?? widget.fontSize) * 0.35, color: Colors.blue, fontWeight: FontWeight.bold))))]);
                }
                final bool isPilcrow = p.text.contains('¶');
                final List<Shadow>? shadows = isMath ? [
                  Shadow(blurRadius: p.isRed ? 4.0 : 2.0, color: p.isRed ? symbolColor : Colors.cyanAccent.withOpacity(0.5))
                ] : null;
                return TextSpan(text: p.text, style: TextStyle(color: isPilcrow ? Colors.red : (p.isRed ? symbolColor : (isMath || widget.isDarkMode ? Colors.white : Colors.black)), fontSize: customSize ?? widget.fontSize, fontWeight: (isPilcrow || p.isRed || isBold || isPhraseHighlight) ? FontWeight.bold : FontWeight.normal, fontStyle: (p.isItalic || isItalic) ? FontStyle.italic : FontStyle.normal, fontFamily: isMath ? 'Courier' : null, shadows: shadows));
              })
            ]))
          )
        );
      });
    });
  }

  Widget _buildVerseContent(BibleVerse v, {double customScale = 1.0, bool forceBold = false, bool forceItalic = false, bool isVerse0 = false}) {
    double fontSize = widget.fontSize * customScale; if (isVerse0 && customScale == 1.0) fontSize *= 0.70;
    final mathWords = BibleLogic.applyContinuity(v, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
    return Wrap(children: mathWords.map((mw) => _renderWord(v, mw, customSize: fontSize, isBold: forceBold, isItalic: forceItalic)).toList());
  }

  void _handleWordTap(String id) {
    if (widget.isAudioEnabled && widget.audioService.isAudioLoaded) widget.audioService.seekToFragment(id);
    final bool isMultiSelectPressed = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isShiftPressed;
    Set<String> current = Set.from(_selectionNotifier.value);
    if (isMultiSelectPressed) { if (current.contains(id)) current.remove(id); else current.add(id); _anchorWordId = id; }
    else if (_anchorWordId != null) {
      final allIds = widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toList();
      int start = allIds.indexOf(_anchorWordId!); int end = allIds.indexOf(id);
      if (start != -1 && end != -1) { current.clear(); for (int i = min(start, end); i <= max(start, end); i++) current.add(allIds[i]); }
    } else { current = {id}; _anchorWordId = id; }
    _selectionNotifier.value = current;
  }
  void _handleLongPress(String id) { _selectionNotifier.value = {id}; _anchorWordId = id; }
}
