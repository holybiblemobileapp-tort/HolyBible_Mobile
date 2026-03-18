import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_tts/flutter_tts.dart';
import 'bible_model.dart';

enum AudioQuality { high, medium, low, systemTts }

class AudioService {
  AudioPlayer? _player;
  final FlutterTts _tts = FlutterTts();
  final _fragmentController = StreamController<String?>.broadcast();
  StreamSubscription? _posSub;

  List<AudioSyncWord> _currentWords = [];
  List<String> _chapterWordIds = [];
  
  int _ttsWordIndex = 0;
  bool _isTtsPlaying = false;

  bool _isAudioLoaded = false;
  bool _isDisposed = false;
  String? _currentKey;
  bool _isError = false;
  bool _isEnabled = false;
  bool _isLoading = false;
  
  AudioQuality _quality = AudioQuality.high;

  static const int _highlightLeadOffsetMs = 30; 

  AudioService() {
    _initTts();
  }

  void _initTts() {
    _tts.setLanguage("en-US");
    _tts.setSpeechRate(0.5);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);

    // FIX: Capturing real-time progress for Google TTS highlight sync
    _tts.setProgressHandler((String text, int start, int end, String word) {
      if (_isEnabled) {
        if (_ttsWordIndex < _chapterWordIds.length) {
          final currentId = _chapterWordIds[_ttsWordIndex];
          _fragmentController.add(currentId);
          _ttsWordIndex++;
        }
      }
    });

    _tts.setStartHandler(() {
      _isTtsPlaying = true;
    });

    _tts.setCompletionHandler(() {
      _isTtsPlaying = false;
      _ttsWordIndex = 0;
      _fragmentController.add(null);
    });

    _tts.setCancelHandler(() {
      _isTtsPlaying = false;
      _ttsWordIndex = 0;
      _fragmentController.add(null);
    });
  }

  void setQuality(AudioQuality q) {
    _quality = q;
  }

  bool get isSystemTts => _quality == AudioQuality.systemTts;

  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    if (!enabled) {
      _stopAndRelease();
    } else {
      await _initPlayer();
    }
  }

  Future<void> _initPlayer() async {
    if (_player != null || _isDisposed) return;
    try {
      _player = AudioPlayer();
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      _attachListener();
    } catch (e) {
      debugPrint("AUDIO: Failed to init player: $e");
    }
  }

  void _stopAndRelease() {
    try {
      _player?.stop();
      _tts.stop();
      _isTtsPlaying = false;
    } catch (_) {}
    _isAudioLoaded = false;
    _currentKey = null;
    _isError = false;
  }

  void _attachListener() {
    _posSub?.cancel();
    if (_player == null) return;

    _posSub = _player!.positionStream.listen((pos) {
      if (_isDisposed || !_isEnabled || _currentWords.isEmpty || !_isAudioLoaded || _isLoading || _quality == AudioQuality.systemTts) return;

      try {
        final seconds = (pos.inMilliseconds + _highlightLeadOffsetMs) / 1000.0;
        String? foundId;
        for (int i = 0; i < _currentWords.length; i++) {
          final w = _currentWords[i];
          if (seconds >= w.begin && seconds <= w.end) {
            if (i < _chapterWordIds.length) foundId = _chapterWordIds[i];
            break;
          }
        }
        if (foundId != null && !_fragmentController.isClosed) {
          _fragmentController.add(foundId);
        }
      } catch (e) {}
    });
  }

  bool get isAudioLoaded => _quality == AudioQuality.systemTts ? true : _isAudioLoaded;
  bool get isAudioLoading => _isEnabled && _quality != AudioQuality.systemTts && (_isLoading || (!_isAudioLoaded && _currentKey != null && !_isError));
  bool get hasAudioError => _isError;
  Stream<String?> get currentFragmentIdStream => _fragmentController.stream.distinct();
  
  Stream<PlayerState> get playerStateStream {
    if (_isTtsPlaying || _quality == AudioQuality.systemTts) {
      return Stream.periodic(const Duration(milliseconds: 200), (_) {
        return PlayerState(_isTtsPlaying, ProcessingState.ready);
      });
    }
    return _player?.playerStateStream ?? const Stream.empty();
  }

  Future<void> loadChapter(String bookAbbr, int chapter, List<BibleVerse> allVerses) async {
    if (_isDisposed || !_isEnabled || _isLoading) return;
    
    final key = '$bookAbbr$chapter';
    _currentKey = key;
    _chapterWordIds = _generateIDs(allVerses, bookAbbr, chapter);

    // Hybrid Check: Use Piper if file exists, otherwise Google TTS
    final docDir = await getApplicationDocumentsDirectory();
    final localAudioFile = File(p.join(docDir.path, 'audio', '$key.ogg'));
    
    if (_quality == AudioQuality.systemTts || !await localAudioFile.exists()) {
      // Switch to TTS mode
      _isAudioLoaded = true;
      _currentWords = [];
      return;
    }

    _isLoading = true;
    _isAudioLoaded = false;
    _isError = false;

    try {
      if (_player == null) await _initPlayer();
      if (_player == null) {
        _isLoading = false;
        _isError = true;
        return;
      }

      if (_player?.playing == true) await _player?.pause();
      await _player?.stop();

      final localSyncFile = File(p.join(docDir.path, 'sync', '$key.json'));

      String syncContent;
      if (await localSyncFile.exists()) {
        syncContent = await localSyncFile.readAsString();
      } else {
        try {
          syncContent = await rootBundle.loadString('assets/sync/$key.json');
        } catch (e) {
          // If no sync file, we can't do precise highlights, so fallback to generic TTS mode
          _isAudioLoaded = true;
          _isLoading = false;
          return;
        }
      }

      final dynamic decoded = json.decode(syncContent);
      _currentWords = decoded.map((w) => AudioSyncWord.fromJson(w as Map<String, dynamic>)).toList();

      await _player!.setFilePath(localAudioFile.path, preload: true).timeout(const Duration(seconds: 15));
      _isAudioLoaded = true;
    } catch (e) {
      _isError = true;
    } finally {
      _isLoading = false;
    }
  }

  List<String> _generateIDs(List<BibleVerse> verses, String abbr, int ch) {
    final list = verses.where((v) => v.bookAbbreviation == abbr && v.chapter == ch).toList();
    list.sort((a, b) => a.verse.compareTo(b.verse));
    return list.expand((v) => v.styledWords.map((w) => '${v.id}:${w.index}')).toList();
  }

  Future<void> speakVerses(List<BibleVerse> verses) async {
    if (!_isEnabled) return;
    _ttsWordIndex = 0;
    final fullText = verses.map((v) => v.text.replaceAll('¶', '')).join(" ");
    await _tts.speak(fullText);
  }

  Future<void> seekToFragment(String fragmentId) async {
    if (_quality == AudioQuality.systemTts || _isTtsPlaying) return;
    if (!_isAudioLoaded || _chapterWordIds.isEmpty || _isLoading || _player == null) return;
    final index = _chapterWordIds.indexOf(fragmentId);
    if (index != -1 && index < _currentWords.length) {
      final startTime = _currentWords[index].begin;
      try {
        await _player!.seek(Duration(milliseconds: (startTime * 1000).toInt()));
        if (_player!.playing == false) await play();
      } catch (e) {}
    }
  }

  Future<void> play() async {
    if (!_isEnabled) return;
    if (_isAudioLoaded && !_isLoading && _player != null) {
      await _player!.play();
    }
  }

  Future<void> pause() async {
    await _tts.stop();
    _isTtsPlaying = false;
    _fragmentController.add(null);
    if (_player != null) {
      await _player!.pause();
    }
  }

  void dispose() {
    _isDisposed = true;
    _posSub?.cancel();
    _player?.dispose();
    _tts.stop();
    if (!_fragmentController.isClosed) {
      _fragmentController.close();
    }
  }
}
