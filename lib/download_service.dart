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
  
  // Base URL for your raw assets on GitHub
  final String _baseUrl = "https://raw.githubusercontent.com/ceyumsama-glitch/HolyBible_Mobile/main/assets";

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
      // Log the exact URL for manual verification
      debugPrint("DOWNLOAD: Attempting Sync JSON from: $syncUrl");
      
      // 1. Download Sync JSON
      await _dio.download(
        syncUrl,
        syncPath,
      ).catchError((e) {
        debugPrint("DOWNLOAD ERROR: Sync file not found at $syncUrl");
        throw Exception("Sync File 404: Please verify the URL in your browser.");
      });

      debugPrint("DOWNLOAD: Attempting Audio OGG from: $audioUrl");

      // 2. Download Audio OGG
      await _dio.download(
        audioUrl,
        audioPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
      ).catchError((e) {
        debugPrint("DOWNLOAD ERROR: Audio file not found at $audioUrl");
        throw Exception("Audio File 404: Please verify the URL in your browser.");
      });
      
      debugPrint("DOWNLOAD: Successfully saved $key to local storage.");
    } on DioException catch (e) {
      String msg = "Download Failed: ";
      if (e.response?.statusCode == 404) msg += "File Not Found (404). Is your repo Private?";
      else msg += e.message ?? "Network Error";
      throw Exception(msg);
    } catch (e) {
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
}
