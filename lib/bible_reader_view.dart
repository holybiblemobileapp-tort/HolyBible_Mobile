import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:just_audio/just_audio.dart';
import 'bible_model.dart';
import 'bible_logic.dart';
import 'audio_service.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.isAudioEnabled) _loadAudio();
    for (var v in widget.allVersesOfChapter) {
      _verseKeys[v.id] = GlobalKey();
    }
    _audioSubscription = widget.audioService.currentFragmentIdStream.listen((id) {
      if (mounted && id != _activeWordNotifier.value) {
        _activeWordNotifier.value = id;
        if (id != null) _scrollToId(id);
      }
    });
    if (widget.targetVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final verse = widget.allVersesOfChapter.firstWhere((v) => v.verse == widget.targetVerse);
          _scrollToId("${verse.id}:${widget.targetWordIndex ?? 1}", force: true);
        } catch (_) {}
      });
    }
  }

  @override
  void didUpdateWidget(BibleReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool chapterChanged = widget.chapter != oldWidget.chapter || widget.bookName != oldWidget.bookName;
    if (chapterChanged) {
      for (var v in widget.allVersesOfChapter) {
        _verseKeys.putIfAbsent(v.id, () => GlobalKey());
      }
      _selectionNotifier.value = {};
    }

    if (widget.isAudioEnabled) {
      if (!oldWidget.isAudioEnabled || chapterChanged) {
        _loadAudio();
      }
    } else if (oldWidget.isAudioEnabled) {
      widget.audioService.pause();
    }

    if (widget.targetVerse != oldWidget.targetVerse && widget.targetVerse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final verse = widget.allVersesOfChapter.firstWhere((v) => v.verse == widget.targetVerse);
          _scrollToId("${verse.id}:${widget.targetWordIndex ?? 1}", force: true);
        } catch (_) {}
      });
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

  void _handleWordTap(String id) {
    if (widget.isAudioEnabled && widget.audioService.isAudioLoaded) {
      widget.audioService.seekToFragment(id);
    }
    _handleSelection(id, isCtrl: HardwareKeyboard.instance.isControlPressed);
  }

  void _handleSelection(String id, {bool isCtrl = false, bool isRange = false}) {
    Set<String> current = Set.from(_selectionNotifier.value);

    if (isRange) {
      current.clear();
      current.add(id);
      _anchorWordId = id;
    } else if (isCtrl) {
      if (current.contains(id))
        current.remove(id);
      else {
        current.add(id);
        _anchorWordId = id;
      }
    } else {
      if (_anchorWordId != null && !isCtrl) {
        final allIds = widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toList();
        int start = allIds.indexOf(_anchorWordId!);
        int end = allIds.indexOf(id);
        if (start != -1 && end != -1) {
          int minIdx = min(start, end);
          int maxIdx = max(start, end);
          current.clear();
          for (int i = minIdx; i <= maxIdx; i++) {
            current.add(allIds[i]);
          }
        }
      } else {
        if (current.contains(id) && current.length == 1) {
          current.clear();
          _anchorWordId = null;
        } else {
          current.clear();
          current.add(id);
          _anchorWordId = id;
        }
      }
    }

    _selectionNotifier.value = current;
  }

  Future<void> _loadAudio() async {
    if (!widget.isAudioEnabled || widget.allVersesOfChapter.isEmpty || widget.audioService.isAudioLoading) return;
    final bookAbbr = widget.allVersesOfChapter.first.bookAbbreviation;
    await widget.audioService.loadChapter(bookAbbr, widget.chapter, widget.allVersesOfChapter);
    if (mounted) setState(() {});
  }

  void _scrollToId(String wordId, {bool force = false}) {
    if (!force && _lastScrolledId == wordId) return;
    _lastScrolledId = wordId;

    try {
      final parts = wordId.split(':');
      final verseId = int.tryParse(parts[0]);
      if (verseId != null) {
        final key = _verseKeys[verseId];
        if (key?.currentContext != null) {
          final RenderBox? box = key!.currentContext!.findRenderObject() as RenderBox?;
          if (box != null) {
            final position = box.localToGlobal(Offset.zero);
            final screenHeight = MediaQuery.of(context).size.height;
            if (!force && position.dy > 100 && position.dy < screenHeight - 200) {
              return;
            }
          }

          Scrollable.ensureVisible(
            key.currentContext!,
            alignment: 0.2,
            duration: Duration(milliseconds: force ? 400 : 800),
            curve: Curves.easeInOutCubic,
          );
        }
      }
    } catch (_) {}
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
                Text('${selection.length} items selected', style: const TextStyle(color: Colors.black)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.copy, color: Colors.black),
                    onPressed: () {
                      final allIds = widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toList();
                      final selectedSorted = allIds.where((id) => selection.contains(id)).toList();
                      if (selectedSorted.isEmpty) return;

                      List<List<String>> spans = [];
                      if (selectedSorted.isNotEmpty) {
                        List<String> currentSpan = [selectedSorted[0]];
                        for (int i = 1; i < selectedSorted.length; i++) {
                          final prevId = selectedSorted[i - 1];
                          final currId = selectedSorted[i];
                          if (allIds.indexOf(currId) == allIds.indexOf(prevId) + 1) {
                            currentSpan.add(currId);
                          } else {
                            spans.add(currentSpan);
                            currentSpan = [currId];
                          }
                        }
                        spans.add(currentSpan);
                      }

                      List<String> phraseParts = [];
                      List<String> coordParts = [];

                      for (var span in spans) {
                        Map<int, List<int>> wordsByVerse = {};
                        for (var id in span) {
                          final parts = id.split(':');
                          final vId = int.parse(parts[0]);
                          final wIdx = int.parse(parts[1]);
                          wordsByVerse.putIfAbsent(vId, () => []).add(wIdx);
                        }

                        List<String> spanPhrases = [];
                        for (var entry in wordsByVerse.entries) {
                          final v = widget.allVersesOfChapter.firstWhere((v) => v.id == entry.key);
                          final styled = BibleLogic.getStyledPhrase(v, entry.value, widget.currentStyle, widget.continuityMap, widget.parenthesesMap);
                          spanPhrases.add(styled.replaceAll('¶', '').trim());
                        }
                        phraseParts.add(spanPhrases.join(' '));

                        if (wordsByVerse.length == 1) {
                          final vId = wordsByVerse.keys.first;
                          final indices = wordsByVerse[vId]!..sort();
                          final v = widget.allVersesOfChapter.firstWhere((v) => v.id == vId);
                          final start = indices.first;
                          final end = indices.last;
                          coordParts.add((start == end) ? "${v.bookAbbreviation}${v.chapter}:${v.verse}:$start" : "${v.bookAbbreviation}${v.chapter}:${v.verse}:$start-$end");
                        } else {
                          final firstVId = wordsByVerse.keys.first;
                          final lastVId = wordsByVerse.keys.last;
                          final firstIndices = wordsByVerse[firstVId]!..sort();
                          final lastIndices = wordsByVerse[lastVId]!..sort();
                          final firstV = widget.allVersesOfChapter.firstWhere((v) => v.id == firstVId);
                          final lastV = widget.allVersesOfChapter.firstWhere((v) => v.id == lastVId);

                          String s = "${firstV.bookAbbreviation}${firstV.chapter}:${firstV.verse}:${firstIndices.first}";
                          if (firstIndices.first != firstIndices.last) s += "-${firstIndices.last}";
                          String e = "${lastV.bookAbbreviation}${lastV.chapter}:${lastV.verse}:${lastIndices.first}";
                          if (lastIndices.first != lastIndices.last) e += "-${lastIndices.last}";
                          coordParts.add("${s}_${e}");
                        }
                      }

                      List<String> shortenedCoords = [];
                      String? lastBCV;
                      for (var coord in coordParts) {
                        if (coord.contains('_')) {
                          shortenedCoords.add(coord);
                          lastBCV = null;
                          continue;
                        }
                        final loc = BibleLogic.parseLocation(coord);
                        if (loc != null) {
                          final bcv = "${loc.bookAbbr}${loc.chapter}:${loc.verse}";
                          final range = coord.substring(coord.lastIndexOf(':') + 1);
                          if (bcv == lastBCV) {
                            shortenedCoords.add(range);
                          } else {
                            shortenedCoords.add(coord);
                            lastBCV = bcv;
                          }
                        } else {
                          shortenedCoords.add(coord);
                          lastBCV = null;
                        }
                      }

                      final output = BibleLogic.formatPhraseFunction(phraseParts.join(', '), shortenedCoords.join(', '));
                      Clipboard.setData(ClipboardData(text: output));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selection copied')));
                    }),
                IconButton(icon: const Icon(Icons.share, color: Colors.black), onPressed: () => Share.share("Bible selection")),
              ],
            ),
          );
        });
  }

  Widget _buildHeader(bool isMath) {
    String leftLabel = BibleLogic.getReadingLabel(widget.currentStyle);
    return Container(
      color: isMath ? Colors.grey[900] : Colors.grey[200],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(leftLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey))),
          const Expanded(child: Text('BREADTH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildCanonicalView() {
    final bool isPauline = const {'Rom', '1Co', '2Co', 'Gal', 'Eph', 'Phi', 'Col', '1Th', '2Th', '1Ti', '2Ti', 'Tit', 'Phm', 'Heb'}.contains(widget.allVersesOfChapter.isNotEmpty ? widget.allVersesOfChapter.first.bookAbbreviation : '');
    final List<BibleVerse> verses = List<BibleVerse>.from(widget.allVersesOfChapter);
    
    if (isPauline && verses.any((v) => v.verse == 0)) {
      final v0 = verses.firstWhere((v) => v.verse == 0);
      verses.remove(v0);
      verses.add(v0);
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: verses.length,
      itemBuilder: (context, index) {
        final v = verses[index];
        final bool isVerse0 = v.verse == 0;
        final bool isSuperscript = widget.currentStyle == BibleViewStyle.superscript;
        final locationText = isSuperscript ? '${v.bookAbbreviation}${v.chapter}:${v.verse}' : '${v.bookAbbreviation}${v.chapter}:${v.verse}:1-${v.wordCount}';

        return Container(
          key: _verseKeys[v.id],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              if (isVerse0) _buildVerse0Heading(v, isPauline) else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 90, child: Text(locationText, style: TextStyle(fontWeight: FontWeight.bold, color: widget.isDarkMode ? Colors.grey[400] : Colors.grey, fontSize: widget.fontSize * 0.55))),
                Expanded(child: _buildVerseContent(v)),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVerse0Heading(BibleVerse v, bool isPauline) {
    String text = v.text.replaceAll('¶', '').trim();
    if (isPauline) text = "$text ¶";
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: widget.fontSize * 0.75,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
            color: widget.isDarkMode ? Colors.amberAccent.withOpacity(0.7) : Colors.brown.withOpacity(0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildPrefaceView() {
    final List<Widget> items = [];
    List<BibleVerse> currentParagraph = [];
    final int chapter = widget.chapter;

    for (var v in widget.allVersesOfChapter) {
      if (chapter == 0) {
        if (v.verse == 0) {
          items.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Text(
              v.text.replaceAll('¶', '').trim().toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: widget.fontSize * 1.8, fontWeight: FontWeight.bold, color: widget.isDarkMode ? Colors.white : Colors.black),
            ),
          ));
        } else {
          items.add(_buildParagraph([v], center: true));
        }
      } else if (chapter == 1) {
        if (v.verse == 0) {
          items.add(_buildParagraph([v], center: true, isHeader: true));
        } else if (v.verse >= 1 && v.verse <= 7) {
          items.add(_buildParagraph([v], center: true));
        } else {
          currentParagraph.add(v);
          if (v.text.contains('¶')) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
        }
      } else if (chapter >= 2 && chapter <= 16) {
        if (v.verse == 0) {
          if (currentParagraph.isNotEmpty) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
          items.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Text(
              v.text.replaceAll('¶', '').trim().toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: widget.fontSize * 1.5, fontWeight: FontWeight.bold, color: widget.isDarkMode ? Colors.white : Colors.black),
            ),
          ));
        } else if (v.verse == 1) {
          if (currentParagraph.isNotEmpty) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
          items.add(_buildParagraph([v], center: true, isHeader: true));
        } else {
          currentParagraph.add(v);
          if (v.text.contains('¶')) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
        }
      } else if (chapter == 17) {
        if (v.verse <= 2) {
          items.add(_buildParagraph([v], center: true, isHeader: true));
        } else if (v.verse >= 3 && v.verse <= 5) {
          currentParagraph.add(v);
          if (v.text.contains('¶')) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
        } else {
          if (currentParagraph.isNotEmpty) {
            items.add(_buildParagraph(currentParagraph));
            currentParagraph = [];
          }
          items.add(_buildParagraph([v]));
        }
      }
    }
    if (currentParagraph.isNotEmpty) {
      items.add(_buildParagraph(currentParagraph));
    }
    if (items.isEmpty) return const Center(child: Text("No content found"));
    return ListView(controller: _scrollController, children: items);
  }

  Widget _buildParagraph(List<BibleVerse> verses, {bool center = false, bool isHeader = false, bool isItalic = false}) {
    List<Widget> wordWidgets = [];
    for (var v in verses) {
      for (int i = 0; i < v.styledWords.length; i++) {
        final w = v.styledWords[i];
        Widget wordWidget = _buildWord(v, w, forceItalic: isItalic, forceBold: isHeader);
        if (i == 0) {
          wordWidget = Container(key: _verseKeys[v.id], child: wordWidget);
        }
        wordWidgets.add(wordWidget);
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Wrap(alignment: center ? WrapAlignment.center : WrapAlignment.start, children: wordWidgets),
    );
  }

  Widget _buildVerseContent(BibleVerse v) {
    if (widget.currentStyle == BibleViewStyle.standard) {
      return Wrap(children: v.styledWords.map((w) => _buildWord(v, w)).toList());
    }
    if (widget.currentStyle == BibleViewStyle.superscript) {
      return Wrap(children: v.styledWords.map((w) => _buildSuperscriptWord(v, w)).toList());
    }
    final mathWords = BibleLogic.applyContinuity(v, widget.continuityMap, parenthesesMap: widget.parenthesesMap, style: widget.currentStyle);
    return Wrap(children: mathWords.map((mw) => _buildMathWord(v, mw)).toList());
  }

  Widget _buildAudioControls() {
    return Container(
        color: Colors.brown[50],
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: StreamBuilder<PlayerState>(
            stream: widget.audioService.playerStateStream,
            builder: (context, snapshot) {
              final isPlaying = snapshot.data?.playing ?? false;
              final isLoaded = widget.audioService.isAudioLoaded;
              return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => widget.onChapterChange(widget.chapter - 1)),
                if (widget.isAudioEnabled && widget.audioService.hasAudioError) const Icon(Icons.error_outline, color: Colors.red),
                if (widget.isAudioEnabled && widget.audioService.isAudioLoading) const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator())),
                if (widget.isAudioEnabled && isLoaded) IconButton(icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow), iconSize: 48, onPressed: isPlaying ? widget.audioService.pause : widget.audioService.play),
                IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => widget.onChapterChange(widget.chapter + 1)),
              ]);
            }));
  }

  Widget _buildWord(BibleVerse v, BibleWord w, {bool forceItalic = false, bool forceBold = false}) {
    final cleanText = w.text.replaceAll('¶', '').trim();
    if (cleanText.isEmpty) return const SizedBox.shrink();
    
    final wordId = '${v.id}:${w.index}';
    final isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;

    bool isHighlighted = false;
    if (widget.highlightPhrase != null && widget.highlightPhrase!.isNotEmpty) {
      final queryLower = widget.highlightPhrase!.toLowerCase();
      final words = v.styledWords.map((w) => w.text.toLowerCase().replaceAll('¶', '')).toList();
      final queryParts = queryLower.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      if (queryParts.length == 1) {
        isHighlighted = cleanText.toLowerCase().contains(queryLower);
      } else {
        for (int i = 0; i <= words.length - queryParts.length; i++) {
          bool match = true;
          for (int j = 0; j < queryParts.length; j++) {
            if (!words[i + j].contains(queryParts[j])) { match = false; break; }
          }
          if (match && w.index >= i + 1 && w.index <= i + queryParts.length) { isHighlighted = true; break; }
        }
      }
    }

    return ValueListenableBuilder<String?>(
        valueListenable: _activeWordNotifier,
        builder: (context, activeId, child) {
          final isActive = activeId == wordId;
          return ValueListenableBuilder<Set<String>>(
              valueListenable: _selectionNotifier,
              builder: (context, selection, _) {
                final isSelected = selection.contains(wordId);
                return GestureDetector(
                  onTap: () => _handleWordTap(wordId),
                  onLongPress: () => _handleSelection(wordId, isRange: true),
                  child: Container(
                      decoration: BoxDecoration(color: isSelected ? Colors.blue.withOpacity(0.3) : (isActive ? (isMath ? Colors.white24 : Colors.yellow.withOpacity(0.5)) : (isHighlighted ? Colors.orange.withOpacity(0.4) : Colors.transparent)), borderRadius: BorderRadius.circular(2)),
                      child: Text('$cleanText ',
                          style: TextStyle(
                            fontSize: widget.fontSize,
                            fontStyle: (w.isItalic || forceItalic) ? FontStyle.italic : FontStyle.normal,
                            fontWeight: forceBold ? FontWeight.bold : FontWeight.normal,
                            color: (isMath || widget.isDarkMode) ? Colors.white : Colors.black,
                          ))),
                );
              });
        });
  }

  Widget _buildSuperscriptWord(BibleVerse v, BibleWord w) {
    final cleanText = w.text.replaceAll('¶', '').trim();
    if (cleanText.isEmpty) return const SizedBox.shrink();
    final wordId = '${v.id}:${w.index}';
    bool isHighlighted = false;
    if (widget.highlightPhrase != null && widget.highlightPhrase!.isNotEmpty) {
      final queryLower = widget.highlightPhrase!.toLowerCase();
      isHighlighted = cleanText.toLowerCase().contains(queryLower);
    }

    return ValueListenableBuilder<String?>(
        valueListenable: _activeWordNotifier,
        builder: (context, activeId, child) {
          final isActive = activeId == wordId;
          return ValueListenableBuilder<Set<String>>(
              valueListenable: _selectionNotifier,
              builder: (context, selection, _) {
                final isSelected = selection.contains(wordId);
                return GestureDetector(
                  onTap: () => _handleWordTap(wordId),
                  onLongPress: () => _handleSelection(wordId, isRange: true),
                  child: Container(
                    decoration: BoxDecoration(color: isSelected ? Colors.blue.withOpacity(0.3) : (isActive ? Colors.yellow.withOpacity(0.5) : (isHighlighted ? Colors.orange.withOpacity(0.4) : Colors.transparent)), borderRadius: BorderRadius.circular(2)),
                    child: RichText(
                        text: TextSpan(children: [
                      TextSpan(text: '$cleanText', style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black, fontSize: widget.fontSize, fontStyle: w.isItalic ? FontStyle.italic : FontStyle.normal)),
                      WidgetSpan(child: Transform.translate(offset: const Offset(0, -10), child: Text('${w.index}', style: TextStyle(fontSize: widget.fontSize * 0.6, color: Colors.blue, fontWeight: FontWeight.bold)))),
                      const TextSpan(text: ' '),
                    ])),
                  ),
                );
              });
        });
  }

  Widget _buildMathWord(BibleVerse v, MathWord mw) {
    final cleanOriginal = mw.original.text.replaceAll('¶', '').trim();
    if (cleanOriginal.isEmpty) return const SizedBox.shrink();
    
    final wordId = '${v.id}:${mw.original.index}';
    bool isHighlighted = false;
    if (widget.highlightPhrase != null && widget.highlightPhrase!.isNotEmpty) {
      isHighlighted = cleanOriginal.toLowerCase().contains(widget.highlightPhrase!.toLowerCase());
    }

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
                      decoration: BoxDecoration(color: isSelected ? Colors.blue.withOpacity(0.3) : (isActive ? Colors.white24 : (isHighlighted ? Colors.orange.withOpacity(0.4) : Colors.transparent)), borderRadius: BorderRadius.circular(2)),
                      child: RichText(
                          text: TextSpan(children: [
                        if (mw.hasLeadingSpace) const TextSpan(text: ' '),
                        ...mw.parts.map((p) {
                          final cleanPart = p.text.replaceAll('¶', '');
                          return TextSpan(
                                text: cleanPart,
                                style: TextStyle(
                                  color: p.isRed ? Colors.redAccent : Colors.white,
                                  fontSize: widget.fontSize,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Roboto',
                                  shadows: [
                                    Shadow(
                                      blurRadius: 8.0,
                                      color: p.isRed ? Colors.red : Colors.cyanAccent,
                                      offset: const Offset(0, 0),
                                    ),
                                  ],
                                ));
                        })
                      ]))),
                );
              });
        });
  }
}
