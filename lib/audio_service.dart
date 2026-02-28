import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'bible_model.dart';

class AudioService {
  AudioPlayer? _player;
  final _fragmentController = StreamController<String?>.broadcast();
  StreamSubscription? _posSub;

  List<AudioSyncWord> _currentWords = [];
  List<String> _chapterWordIds = [];

  bool _isAudioLoaded = false;
  bool _isDisposed = false;
  String? _currentKey;
  bool _isError = false;
  bool _isEnabled = false;
  bool _isLoading = false;

  static const int _highlightLeadOffsetMs = 50;

  AudioService();

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
    } catch (_) {}
    _isAudioLoaded = false;
    _currentKey = null;
    _isError = false;
  }

  void _attachListener() {
    _posSub?.cancel();
    if (_player == null) return;

    _posSub = _player!.positionStream.listen((pos) {
      if (_isDisposed || !_isEnabled || _currentWords.isEmpty || !_isAudioLoaded || _isLoading) return;

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
      } catch (e) {
        // Guard against platform-specific position access errors
      }
    });
  }

  bool get isAudioLoaded => _isAudioLoaded;
  bool get isAudioLoading => _isEnabled && (_isLoading || (!_isAudioLoaded && _currentKey != null && !_isError));
  bool get hasAudioError => _isError;
  Stream<String?> get currentFragmentIdStream => _fragmentController.stream.distinct();
  Stream<PlayerState> get playerStateStream => _player?.playerStateStream ?? const Stream.empty();

  Future<void> loadChapter(String bookAbbr, int chapter, List<BibleVerse> allVerses) async {
    if (_isDisposed || !_isEnabled || _isLoading) return;

    final key = '$bookAbbr$chapter';
    if (_currentKey == key && _isAudioLoaded) return;

    _isLoading = true;
    _isAudioLoaded = false;
    _isError = false;
    _currentKey = key;

    try {
      if (_player == null) await _initPlayer();
      if (_player == null) {
        _isLoading = false;
        _isError = true;
        return;
      }

      bool wasPlaying = _player?.playing ?? false;

      if (defaultTargetPlatform == TargetPlatform.windows) {
        _posSub?.cancel();
        await _player?.dispose();
        _player = null;
        await Future.delayed(const Duration(milliseconds: 200));
        _player = AudioPlayer();
        _attachListener();
        await Future.delayed(const Duration(milliseconds: 200));
      } else {
        if (_player?.playing == true) await _player?.pause();
        await _player?.stop();
      }

      // 1. Determine Paths (Local first, then fallback to Assets)
      final docDir = await getApplicationDocumentsDirectory();
      final localAudioFile = File(p.join(docDir.path, 'audio', '$key.ogg'));
      final localSyncFile = File(p.join(docDir.path, 'sync', '$key.json'));

      // 2. Load Sync Data
      String syncContent;
      if (await localSyncFile.exists()) {
        syncContent = await localSyncFile.readAsString();
      } else {
        // Fallback to internal assets for Preface/Genesis
        try {
          syncContent = await rootBundle.loadString('assets/sync/$key.json');
        } catch (e) {
          debugPrint("AUDIO: Sync missing for $key locally and in assets");
          _isError = true;
          _isLoading = false;
          return;
        }
      }

      final dynamic decoded = json.decode(syncContent);
      if (decoded is! List) throw Exception("Invalid sync format");

      _currentWords = decoded.map((w) => AudioSyncWord.fromJson(w as Map<String, dynamic>)).toList();
      _chapterWordIds = _generateIDs(allVerses, bookAbbr, chapter);

      // 3. Load Audio
      try {
        if (await localAudioFile.exists()) {
          await _player!.setFilePath(localAudioFile.path, preload: true).timeout(const Duration(seconds: 15));
        } else {
          // Fallback to internal assets for Preface/Genesis
          await _player!.setAsset('assets/audio/$key.ogg', preload: true).timeout(const Duration(seconds: 15));
        }

        if (_currentKey == key && _isEnabled) {
          _isAudioLoaded = true;
          debugPrint("AUDIO: $key loaded successfully.");

          if (wasPlaying && !_isDisposed) {
            await play();
          }
        }
      } catch (e) {
        debugPrint("AUDIO: Load failed for $key: $e");
        _isError = true;
      }
    } catch (e) {
      debugPrint("AUDIO ERROR ($key): $e");
      _isError = true;
      _isAudioLoaded = false;
    } finally {
      _isLoading = false;
    }
  }

  List<String> _generateIDs(List<BibleVerse> verses, String abbr, int ch) {
    final list = verses.where((v) => v.bookAbbreviation == abbr && v.chapter == ch).toList();
    list.sort((a, b) => a.verse.compareTo(b.verse));
    return list.expand((v) => v.styledWords.map((w) => '${v.id}:${w.index}')).toList();
  }

  Future<void> seekToFragment(String fragmentId) async {
    if (!_isAudioLoaded || _chapterWordIds.isEmpty || _isLoading || _player == null) return;
    final index = _chapterWordIds.indexOf(fragmentId);
    if (index != -1 && index < _currentWords.length) {
      final startTime = _currentWords[index].begin;
      try {
        await _player!.seek(Duration(milliseconds: (startTime * 1000).toInt()));
        if (_player!.playing == false) await play();
      } catch (e) {
        debugPrint("AUDIO: Seek failed: $e");
      }
    }
  }

  Future<void> play() async {
    if (_isEnabled && _isAudioLoaded && !_isLoading && _player != null) {
      try {
        await _player!.play();
      } catch (e) {
        debugPrint("AUDIO: Play failed: $e");
      }
    }
  }

  Future<void> pause() async {
    if (_player != null) {
      try {
        await _player!.pause();
      } catch (e) {
        debugPrint("AUDIO: Pause failed: $e");
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    _posSub?.cancel();
    _player?.dispose();
    if (!_fragmentController.isClosed) {
      _fragmentController.close();
    }
  }
}
