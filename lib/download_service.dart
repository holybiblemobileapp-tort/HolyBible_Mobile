import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class DownloadService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 5),
  ));
  
  // UPDATED: Base URL for your raw assets on the NEW GitHub repository
  // Note: For LFS files, we use the /raw/ path which redirects to the LFS media server
  final String _baseUrl = "https://github.com/holybiblemobileapp-tort/HolyBible_Mobile/raw/main/assets";

  /// Downloads a Bible book (Sync JSON and Audio OGG)
  Future<void> downloadBook(String bookAbbr, int chapter, {Function(double)? onProgress}) async {
    final key = '$bookAbbr$chapter';
    final docDir = await getApplicationDocumentsDirectory();
    
    final audioDir = Directory(p.join(docDir.path, 'audio'));
    final syncDir = Directory(p.join(docDir.path, 'sync'));
    
    if (!await audioDir.exists()) await audioDir.create(recursive: true);
    if (!await syncDir.exists()) await syncDir.create(recursive: true);

    final syncUrl = "$_baseUrl/sync/$key.json";
    final audioUrl = "$_baseUrl/audio/$key.ogg";
    
    final audioPath = p.join(audioDir.path, '$key.ogg');
    final syncPath = p.join(syncDir.path, '$key.json');

    try {
      debugPrint("DOWNLOAD: Attempting Sync JSON from: $syncUrl");
      await _dio.download(syncUrl, syncPath);

      debugPrint("DOWNLOAD: Attempting Audio OGG from: $audioUrl");
      await _dio.download(
        audioUrl,
        audioPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );
      
      debugPrint("DOWNLOAD: Successfully saved $key to local storage.");
    } catch (e) {
      debugPrint("DOWNLOAD ERROR: $e");
      rethrow;
    }
  }

  /// NEW: Downloads a font file for offline use
  Future<void> downloadFont(String fontFileName, {Function(double)? onProgress}) async {
    final docDir = await getApplicationDocumentsDirectory();
    final fontDir = Directory(p.join(docDir.path, 'fonts'));
    
    if (!await fontDir.exists()) await fontDir.create(recursive: true);

    final fontUrl = "$_baseUrl/fonts/$fontFileName";
    final fontPath = p.join(fontDir.path, fontFileName);

    try {
      debugPrint("DOWNLOAD: Attempting Font from: $fontUrl");
      await _dio.download(
        fontUrl,
        fontPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      );
      debugPrint("DOWNLOAD: Successfully saved font $fontFileName to $fontPath");
    } catch (e) {
      debugPrint("DOWNLOAD ERROR (Font): $e");
      rethrow;
    }
  }

  Future<bool> isBookDownloaded(String bookAbbr, int chapter) async {
    final key = '$bookAbbr$chapter';
    final docDir = await getApplicationDocumentsDirectory();
    final audioFile = File(p.join(docDir.path, 'audio', '$key.ogg'));
    final syncFile = File(p.join(docDir.path, 'sync', '$key.json'));
    return await audioFile.exists() && await syncFile.exists();
  }

  /// NEW: Checks if a font is already downloaded
  Future<bool> isFontDownloaded(String fontFileName) async {
    final docDir = await getApplicationDocumentsDirectory();
    final fontFile = File(p.join(docDir.path, 'fonts', fontFileName));
    return await fontFile.exists();
  }
}
