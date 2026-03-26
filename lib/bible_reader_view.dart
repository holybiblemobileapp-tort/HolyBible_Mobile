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
  String? _anchorWordId;

  @override
  void initState() {
    super.initState();
    widget.audioService.currentFragmentIdStream.listen((id) {
      if (mounted) _activeWordNotifier.value = id;
    });
    
    if (widget.targetVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
  }

  @override
  void didUpdateWidget(BibleReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetVerse != oldWidget.targetVerse && widget.targetVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
  }

  void _scrollToTarget() {
    if (!mounted || widget.targetVerse == null) return;
    
    final List<BibleVerse> displayVerses = List.from(widget.allVersesOfChapter);
    final String abbr = widget.allVersesOfChapter.isNotEmpty ? widget.allVersesOfChapter.first.bookAbbreviation : "";
    final bool isPauline = ['Rom', '1Co', '2Co', 'Gal', 'Eph', 'Phi', 'Col', '1Th', '2Th', '1Ti', '2Ti', 'Tit', 'Phm', 'Heb'].contains(abbr);
    
    if (isPauline && displayVerses.isNotEmpty && displayVerses.first.verse == 0) {
      final verse0 = displayVerses.removeAt(0);
      displayVerses.add(verse0);
    }

    int index = displayVerses.indexWhere((v) => v.verse == widget.targetVerse);
    if (index != -1) {
      double targetOffset = index * 120.0; 
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _selectionNotifier.dispose();
    _activeWordNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;
    final bool isPreface = widget.bookName.toLowerCase() == 'preface' || (widget.allVersesOfChapter.isNotEmpty && widget.allVersesOfChapter.first.bookAbbreviation == 'Pre');

    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(isMath),
            Expanded(child: Container(color: isMath ? Colors.black : null, child: isPreface ? _buildPrefaceView() : _buildStandardView())),
          ],
        ),
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: _selectionNotifier,
            builder: (context, selection, _) {
              if (selection.isEmpty) return const SizedBox.shrink();
              return _buildFloatingActionBar(selection);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingActionBar(Set<String> selection) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(30),
      color: Colors.brown[800],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(icon: const Icon(Icons.copy, color: Colors.white), onPressed: () => _handleCopy(selection), tooltip: "Copy"),
            IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () => _handleShare(selection), tooltip: "Share"),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectionNotifier.value = {}), tooltip: "Clear"),
          ],
        ),
      ),
    );
  }

  void _handleCopy(Set<String> selection) {
    String text = _getSelectedText(selection);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied to clipboard"), duration: Duration(seconds: 1)));
  }

  void _handleShare(Set<String> selection) {
    String text = _getSelectedText(selection);
    Share.share(text);
  }

  String _getSelectedText(Set<String> selection) {
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
    for (int vId in sortedVerseIds) {
      final v = widget.allVersesOfChapter.firstWhere((v) => v.id == vId);
      List<int> indices = verseGroups[vId]!..sort();
      String styledText = BibleLogic.getStyledPhrase(v, indices, widget.currentStyle, widget.continuityMap, widget.parenthesesMap);
      if (sb.isNotEmpty) sb.write(" ");
      sb.write(styledText);
    }
    return sb.toString();
  }

  Widget _buildHeader(bool isMath) {
    final textColor = isMath ? Colors.white : Colors.brown;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      color: isMath ? Colors.grey[900] : Colors.brown[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: textColor, size: 32),
            onPressed: widget.onChapterChange != null ? () => widget.onChapterChange!(-1) : null,
          ),
          Column(
            children: [
              Text(widget.bookName, style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 16)),
              Text('Chapter ${widget.chapter}', style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 12)),
            ],
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: textColor, size: 32),
            onPressed: widget.onChapterChange != null ? () => widget.onChapterChange!(1) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStandardView() {
    if (widget.allVersesOfChapter.isEmpty) return const SizedBox.shrink();
    
    final List<BibleVerse> displayVerses = List.from(widget.allVersesOfChapter);
    final String abbr = widget.allVersesOfChapter.first.bookAbbreviation;
    final bool isPauline = ['Rom', '1Co', '2Co', 'Gal', 'Eph', 'Phi', 'Col', '1Th', '2Th', '1Ti', '2Ti', 'Tit', 'Phm', 'Heb'].contains(abbr);
    
    // Handle Pauline Epistle Superscriptions (Verse 0 moves to bottom)
    if (isPauline && displayVerses.isNotEmpty && displayVerses.first.verse == 0) {
      final verse0 = displayVerses.removeAt(0);
      displayVerses.add(verse0);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: displayVerses.length,
      itemBuilder: (context, index) {
        final v = displayVerses[index];
        final bool isVerse0 = v.verse == 0;
        
        // Handle Author/Superscription Header Logic (Verse 0)
        if (isVerse0) {
           return Padding(
             padding: const EdgeInsets.symmetric(vertical: 8.0),
             child: Center(
               child: _buildVerseContent(
                 v, 
                 customScale: 0.8, // Section 5 requirement: Small font size
                 forceItalic: true,
                 isVerse0: true
               )
             ),
           );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 35, 
                child: Text('${v.verse}', style: TextStyle(fontSize: widget.fontSize * 0.6, color: Colors.grey, fontWeight: FontWeight.bold))
              ),
              Expanded(child: _buildVerseContent(v)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrefaceView() {
    final List<Widget> items = [];
    
    if (widget.chapter == 0) {
      for (var v in widget.allVersesOfChapter) {
        double scale = 1.0; bool isItalic = false; bool isBold = false; bool skip = false;
        switch (v.verse) {
          case 0: skip = true; break;
          case 1: scale = 0.85; break;
          case 2: scale = 2.4; isBold = true; break;
          case 3: scale = 0.85; break;
          case 4: scale = 1.5; isBold = true; break;
          case 5: case 6: case 7: case 8: scale = 0.95; break;
          case 9: scale = 1.0; isItalic = true; break;
          case 10: case 11: scale = 1.1; break;
          default: scale = 0.8;
        }
        if (!skip) {
          items.add(_buildParagraph([v], center: true, customScale: scale, forceItalic: isItalic, forceBold: isBold));
        }
      }
    } else if (widget.chapter == 1) {
      List<BibleVerse> currentParagraph = [];
      for (int i = 0; i < widget.allVersesOfChapter.length; i++) {
        final v = widget.allVersesOfChapter[i];
        if (v.verse == 0) {
          items.add(_buildParagraph([v], center: true, customScale: 1.4, forceBold: true));
          items.add(const SizedBox(height: 24));
        } else if (v.verse >= 1 && v.verse <= 7) {
          items.add(_buildParagraph([v], center: true, customScale: 1.1, forceBold: true));
        } else {
          currentParagraph.add(v);
          if (v.text.contains('¶') || i == widget.allVersesOfChapter.length - 1) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
        }
      }
    } else {
      // General logic for Sections 3 (Ch 2) through 16 (Ch 15) and Section 4 (Ch 17)
      List<BibleVerse> currentParagraph = [];
      for (int i = 0; i < widget.allVersesOfChapter.length; i++) {
        final v = widget.allVersesOfChapter[i];
        
        if (widget.chapter == 17) {
           // SPECIAL SECTION 4 (Chapter 17)
           if (v.verse >= 0 && v.verse <= 2) {
             items.add(_buildParagraph([v], center: true, customScale: 1.3, forceBold: true));
             if (v.verse == 2) items.add(const SizedBox(height: 24));
             continue;
           } else if (v.verse >= 3 && v.verse <= 5) {
             currentParagraph.add(v);
             if (v.text.contains('¶') || v.verse == 5) {
               items.add(_buildParagraph(currentParagraph));
               currentParagraph = [];
             }
             continue;
           }
        }

        // Generic Chapter Handling (Sections 3-16)
        if (v.verse == 0) {
          // Header (Verse 0)
          items.add(_buildParagraph([v], center: true, customScale: 1.4, forceBold: true));
          items.add(const SizedBox(height: 24));
        } else if (v.verse == 1 && widget.chapter >= 2 && widget.chapter <= 15) {
          // Title (Verse 1) for Sections 3-16
          items.add(_buildParagraph([v], center: true, customScale: 1.2, forceBold: true));
          items.add(const SizedBox(height: 16));
        } else {
          // Body Text with Paragraph concatenation
          currentParagraph.add(v);
          if (v.text.contains('¶') || i == widget.allVersesOfChapter.length - 1) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
        }
      }
    }
    return ListView(controller: _scrollController, padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8), children: items);
  }

  Widget _buildParagraph(List<BibleVerse> verses, {bool center = false, double customScale = 1.0, bool forceItalic = false, bool forceBold = false}) {
    List<Widget> wordWidgets = [];
    bool isFirstWordOfParagraph = true;
    for (var v in verses) {
      double baseSize = widget.fontSize * customScale;
      final mathWords = BibleLogic.applyContinuity(v, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
      for (var mw in mathWords) {
        wordWidgets.add(_renderWord(v, mw, customSize: baseSize, isBold: forceBold, isItalic: forceItalic, forceSpace: !isFirstWordOfParagraph && mw.original.index == 1));
        isFirstWordOfParagraph = false;
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Wrap(alignment: center ? WrapAlignment.center : WrapAlignment.start, spacing: 0, runSpacing: 4, children: wordWidgets)
    );
  }

  Widget _renderWord(BibleVerse v, MathWord mw, {double? customSize, bool isBold = false, bool isItalic = false, bool forceSpace = false}) {
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
              if (mw.hasLeadingSpace || forceSpace) const TextSpan(text: ' '),
              ...mw.parts.map((p) {
                if (widget.currentStyle == BibleViewStyle.superscript && !p.isParenthesis) {
                   return TextSpan(children: [
                     TextSpan(text: p.text, style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black, fontSize: customSize ?? widget.fontSize, fontStyle: (p.isItalic || isItalic) ? FontStyle.italic : FontStyle.normal, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
                     WidgetSpan(child: Transform.translate(offset: const Offset(0, -8), child: Text('${mw.original.index}', style: TextStyle(fontSize: (customSize ?? widget.fontSize) * 0.55, color: Colors.blue, fontWeight: FontWeight.bold)))),
                   ]);
                }
                final bool isPilcrow = p.text.contains('¶');
                return TextSpan(text: p.text, style: TextStyle(
                  color: isPilcrow ? Colors.red : (p.isRed ? symbolColor : (isMath || widget.isDarkMode ? Colors.white : Colors.black)),
                  fontSize: customSize ?? widget.fontSize,
                  fontWeight: (isPilcrow || p.isRed || isBold) ? FontWeight.bold : FontWeight.normal,
                  fontStyle: (p.isItalic || isItalic) ? FontStyle.italic : FontStyle.normal,
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

  Widget _buildVerseContent(BibleVerse v, {double customScale = 1.0, bool forceBold = false, bool forceItalic = false, bool isVerse0 = false}) {
    double fontSize = widget.fontSize * customScale;
    if (isVerse0 && customScale == 1.0) fontSize *= 0.70;
    final mathWords = BibleLogic.applyContinuity(v, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
    return Wrap(children: mathWords.map((mw) => _renderWord(v, mw, customSize: fontSize, isBold: forceBold, isItalic: forceItalic)).toList());
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
    } else {
      current = {id};
      _anchorWordId = id;
    }
    _selectionNotifier.value = current;
  }

  void _handleLongPress(String id) {
    _selectionNotifier.value = {id};
    _anchorWordId = id;
  }
}
