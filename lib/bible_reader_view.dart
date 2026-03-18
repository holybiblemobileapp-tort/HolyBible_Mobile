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
    if (widget.isAudioEnabled) _loadAudio();
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
    bool chapterChanged = widget.chapter != oldWidget.chapter || widget.bookName != oldWidget.bookName;
    if (chapterChanged) {
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

  String _getPlainSelectionText(Set<String> selection) {
    final allIds = widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toList();
    final selectedSorted = allIds.where((id) => selection.contains(id)).toList();
    if (selectedSorted.isEmpty) return "";

    StringBuffer textBuffer = StringBuffer();
    Map<int, List<int>> wordsByVerse = {};
    for (var id in selectedSorted) {
      final parts = id.split(':');
      final vId = int.parse(parts[0]);
      final wIdx = int.parse(parts[1]);
      wordsByVerse.putIfAbsent(vId, () => []).add(wIdx);
    }

    String lastLoc = "";
    for (var entry in wordsByVerse.entries) {
      final v = widget.allVersesOfChapter.firstWhere((v) => v.id == entry.key);
      final plainText = entry.value.map((idx) => v.styledWords[idx - 1].text).join(' ');
      textBuffer.write("$plainText ");
      lastLoc = "${v.bookAbbreviation}${v.chapter}:${v.verse}";
    }
    
    return "${textBuffer.toString().trim()} ($lastLoc)";
  }

  String _getSelectionText(Set<String> selection) {
    // Keep mathematical Phrase(Location) formatting for internal clipboard use
    final allIds = widget.allVersesOfChapter.expand((v) => v.styledWords.map((w) => "${v.id}:${w.index}")).toList();
    final selectedSorted = allIds.where((id) => selection.contains(id)).toList();
    if (selectedSorted.isEmpty) return "";
    List<List<String>> spans = [];
    List<String> currentSpan = [selectedSorted[0]];
    for (int i = 1; i < selectedSorted.length; i++) {
      if (allIds.indexOf(selectedSorted[i]) == allIds.indexOf(selectedSorted[i-1]) + 1) {
        currentSpan.add(selectedSorted[i]);
      } else { spans.add(currentSpan); currentSpan = [selectedSorted[i]]; }
    }
    spans.add(currentSpan);
    List<String> results = [];
    for (var span in spans) {
      Map<int, List<int>> spanWords = {};
      for (var id in span) {
        final p = id.split(':'); spanWords.putIfAbsent(int.parse(p[0]), () => []).add(int.parse(p[1]));
      }
      for (var entry in spanWords.entries) {
        final v = widget.allVersesOfChapter.firstWhere((v) => v.id == entry.key);
        final styled = BibleLogic.getStyledPhrase(v, entry.value, widget.currentStyle, widget.continuityMap, widget.parenthesesMap);
        final loc = BibleLogic.formatLocation(v.bookAbbreviation, v.chapter, v.verse, entry.value.first, entry.value.last);
        results.add("$styled($loc)");
      }
    }
    return results.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final bool isPreface = widget.bookName.toLowerCase() == 'preface' || (widget.allVersesOfChapter.isNotEmpty && widget.allVersesOfChapter.first.bookAbbreviation == 'Pre');
    final bool isMath = widget.currentStyle != BibleViewStyle.standard && widget.currentStyle != BibleViewStyle.superscript;

    return Column(children: [
      ValueListenableBuilder<Set<String>>(
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied Phrase(Location)')));
                  }
                ),
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.blue), 
                  tooltip: "Share Actual Text to Social Media",
                  onPressed: () {
                    final output = _getPlainSelectionText(selection);
                    if (output.isNotEmpty) Share.share(output);
                  }
                ),
              ],
            ),
          );
        }
      ),
      Expanded(
          child: Container(
        color: isMath ? Colors.black : null,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: widget.allVersesOfChapter.length,
          itemBuilder: (context, index) {
            final v = widget.allVersesOfChapter[index];
            return Container(
              key: _verseKeys[v.id],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 90, child: Text('${v.bookAbbreviation}${v.chapter}:${v.verse}', style: TextStyle(fontWeight: FontWeight.bold, color: widget.isDarkMode ? Colors.grey[400] : Colors.grey, fontSize: 10))),
                Expanded(child: _buildVerseContent(v)),
              ]),
            );
          },
        )
      )),
      _buildAudioControls(),
    ]);
  }

  Widget _buildVerseContent(BibleVerse v) {
    return Wrap(children: v.styledWords.map((w) => _buildWord(v, w)).toList());
  }

  Widget _buildWord(BibleVerse v, BibleWord w) {
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
              onTap: () {
                if (widget.isAudioEnabled) widget.audioService.seekToFragment(wordId);
                _handleSelection(wordId, isCtrl: HardwareKeyboard.instance.isControlPressed);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.3) : (isActive || isTarget ? Colors.amber.withOpacity(0.4) : Colors.transparent),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text('${w.text} ', style: TextStyle(fontSize: widget.fontSize, color: widget.isDarkMode ? Colors.white : Colors.black)),
              ),
            );
          }
        );
      }
    );
  }

  void _handleSelection(String id, {bool isCtrl = false}) {
    Set<String> current = Set.from(_selectionNotifier.value);
    if (isCtrl) {
      if (current.contains(id)) current.remove(id); else current.add(id);
    } else {
      current.clear(); current.add(id);
    }
    _selectionNotifier.value = current;
  }

  Widget _buildAudioControls() { /* ... unchanged ... */ return const SizedBox.shrink(); }
  void _loadAudio() async { /* ... unchanged ... */ }
  Future<void> _startDownload() async { /* ... unchanged ... */ }
}
