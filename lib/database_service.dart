import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'bible_model.dart';
import 'bible_logic.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'holybible_v4.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE bible (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book TEXT,
            abbr TEXT,
            chapter INTEGER,
            verse INTEGER,
            word_count INTEGER,
            words_data TEXT,
            plain_text TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_bible_lookup ON bible (book, chapter)');
        await db.execute('''
          CREATE TABLE dictionary (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            term TEXT UNIQUE,
            definition TEXT,
            location TEXT,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            content TEXT,
            location TEXT,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE study_paths (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            description TEXT,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE study_path_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path_id INTEGER,
            location TEXT,
            ordinal INTEGER,
            comment TEXT,
            FOREIGN KEY (path_id) REFERENCES study_paths (id) ON DELETE CASCADE
          )
        ''');
      },
    );
  }

  Future<void> initialize() async {
    final db = await database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM bible');
    final count = Sqflite.firstIntValue(countResult) ?? 0;

    if (count == 0) {
      debugPrint("Starting Bible import from JSON...");
      try {
        final String jsonString = await rootBundle.loadString('assets/Bible.json');
        final List<dynamic> data = json.decode(jsonString);

        await db.transaction((txn) async {
          for (var item in data) {
            String abbr = item['BN']?.toString() ?? '';
            int chapter = int.tryParse(item['CHAPTER']?.toString() ?? '0') ?? 0;
            if (abbr == 'Lev' && chapter == 0) continue;

            int wordCount = int.tryParse(item['WORDCOUNT']?.toString() ?? '0') ?? 0;
            List<Map<String, dynamic>> words = [];
            List<String> plainWords = [];

            for (int i = 1; i <= wordCount; i++) {
              String rawWord = item[i.toString()]?.toString() ?? '';
              String clean = rawWord.replaceAll('[', '').replaceAll(']', '');
              words.add({'t': clean, 'i': rawWord.startsWith('[') ? 1 : 0});
              plainWords.add(clean);
            }

            await txn.insert('bible', {
              'book': item['BOOKS'],
              'abbr': abbr,
              'chapter': chapter,
              'verse': int.tryParse(item['VERSE']?.toString() ?? '0'),
              'word_count': wordCount,
              'words_data': json.encode(words),
              'plain_text': plainWords.join(' '),
            });
          }
        });
        debugPrint("Bible import complete.");
      } catch (e) {
        debugPrint("Error importing Bible: $e");
      }
    }
  }

  Future<List<String>> getBooks() async {
    final db = await database;
    final maps = await db.rawQuery('SELECT DISTINCT book FROM bible ORDER BY id ASC');
    return maps.map((m) => m['book'] as String).toList();
  }

  Future<String?> getBookNameFromAbbr(String abbr) async {
    final db = await database;
    final maps = await db.query('bible', columns: ['book'], where: 'abbr = ? COLLATE NOCASE', whereArgs: [abbr], limit: 1);
    if (maps.isEmpty) return null;
    return maps.first['book'] as String?;
  }

  Future<List<int>> getChapters(String book) async {
    final db = await database;
    final result = await db.rawQuery('SELECT DISTINCT chapter FROM bible WHERE book = ? ORDER BY chapter ASC', [book]);
    return result.map((m) => (m['chapter'] ?? 0) as int).toList();
  }

  Future<List<BibleVerse>> getChapter(String book, int chapter) async {
    final db = await database;
    final maps = await db.query('bible', where: 'book = ? AND chapter = ?', whereArgs: [book, chapter], orderBy: 'verse ASC, id ASC');
    return maps.map((m) => BibleVerse.fromJson(m)).toList();
  }

  Future<BibleVerse?> getRandomVerse() async {
    final db = await database;
    final maps = await db.rawQuery('SELECT * FROM bible ORDER BY RANDOM() LIMIT 1');
    if (maps.isEmpty) return null;
    final book = maps.first['book'] as String;
    final chapter = maps.first['chapter'] as int;
    final id = maps.first['id'] as int;
    return getChapter(book, chapter).then((list) => list.firstWhere((v) => v.id == id));
  }

  Future<BibleVerse?> _getVerse(String abbr, int ch, int v) async {
    final db = await database;
    final res = await db.query('bible',
      where: 'abbr = ? COLLATE NOCASE AND chapter = ? AND verse = ?',
      whereArgs: [abbr, ch, v],
      limit: 1
    );
    if (res.isEmpty) return null;
    return BibleVerse.fromJson(res.first);
  }

  Future<List<BibleMatch>> search(String query) async {
    final db = await database;
    List<BibleMatch> results = [];
    final Set<String> seenLocations = {};

    void addResult(BibleMatch match) {
      if (!seenLocations.contains(match.location)) {
        results.add(match);
        seenLocations.add(match.location);
      }
    }

    // 1. Location and Range parsing
    if (query.contains('_')) {
      final parts = query.split('_');
      if (parts.length == 2) {
        final sLoc = BibleLogic.parseLocation(parts[0]);
        final eLoc = BibleLogic.parseLocation(parts[1]);
        if (sLoc != null && eLoc != null) {
          final sV = await _getVerse(sLoc.bookAbbr, sLoc.chapter, sLoc.verse);
          final eV = await _getVerse(eLoc.bookAbbr, eLoc.chapter, eLoc.verse);
          if (sV != null && eV != null) {
            final maps = await db.query('bible', where: 'id >= ? AND id <= ?', whereArgs: [sV.id, eV.id], orderBy: 'id ASC');
            List<BibleVerse> verses = maps.map((m) => BibleVerse.fromJson(m)).toList();
            if (verses.isNotEmpty) {
              StringBuffer sb = StringBuffer();
              for (int i = 0; i < verses.length; i++) {
                int start = (i == 0) ? sLoc.startWord : 1;
                int end = (i == verses.length - 1) ? (eLoc.endWord == 0 ? verses[i].wordCount : eLoc.endWord) : verses[i].wordCount;
                if (sb.isNotEmpty) sb.write(' ');
                sb.write(verses[i].styledWords.sublist(start - 1, end).map((w) => w.text).join(' '));
              }
              results.add(BibleMatch(phrase: sb.toString(), location: query.trim(), verse: sV));
              return results;
            }
          }
        }
      }
    }

    final loc = BibleLogic.parseLocation(query);
    if (loc != null) {
      final locMaps = await db.query('bible',
        where: 'abbr = ? COLLATE NOCASE AND chapter = ? AND (verse = ? OR ? = 0)',
        whereArgs: [loc.bookAbbr, loc.chapter, loc.verse, loc.verse]
      );
      for (var m in locMaps) {
        final verse = BibleVerse.fromJson(m);
        int start = loc.startWord;
        int end = loc.endWord;
        if (start == 1 && end == 0) end = verse.wordCount;
        int effectiveEnd = (end > 0 && end <= verse.wordCount) ? end : start;
        final phrase = verse.styledWords.sublist(start - 1, effectiveEnd).map((w) => w.text).join(' ');
        addResult(BibleMatch(phrase: phrase, location: BibleLogic.formatLocation(verse.bookAbbreviation, verse.chapter, verse.verse, start, effectiveEnd), verse: verse));
      }
      if (results.isNotEmpty) return results;
    }

    // 2. Keyword/Phrase Search
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // First search single verses
    final singleVerseMaps = await db.query('bible', where: 'plain_text LIKE ?', whereArgs: ['%$cleanQuery%'], limit: 1000);
    for (var m in singleVerseMaps) {
      final verse = BibleVerse.fromJson(m);
      final qParts = cleanQuery.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      final words = verse.styledWords.map((w) => w.text.toLowerCase()).toList();

      for (int i = 0; i <= words.length - qParts.length; i++) {
        bool match = true;
        for (int j = 0; j < qParts.length; j++) {
          if (!words[i+j].contains(qParts[j])) { match = false; break; }
        }
        if (match) {
          int sIdx = i + 1;
          int eIdx = i + qParts.length;
          addResult(BibleMatch(
            phrase: verse.styledWords.sublist(sIdx - 1, eIdx).map((w) => w.text).join(' '),
            location: BibleLogic.formatLocation(verse.bookAbbreviation, verse.chapter, verse.verse, sIdx, eIdx),
            verse: verse
          ));
          i += qParts.length - 1; // Move past this occurrence to find next one
        }
      }
    }

    // If phrase search, handle cross-verse matches
    if (cleanQuery.contains(' ')) {
      final qParts = cleanQuery.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
      final firstPart = qParts.first;
      final candidates = await db.query('bible', where: 'plain_text LIKE ?', whereArgs: ['%$firstPart%'], limit: 200);

      for (var m in candidates) {
        final startV = BibleVerse.fromJson(m);
        for (int i = 0; i < startV.styledWords.length; i++) {
          if (startV.styledWords[i].text.toLowerCase().contains(firstPart)) {
            List<String> foundWords = [];
            bool fullMatch = true;
            int currentVId = startV.id;
            int vOffset = 0;
            int wIdx = i;
            String startLoc = ""; String endLoc = "";

            for (int q = 0; q < qParts.length; q++) {
              final vRes = await db.query('bible', where: 'id = ?', whereArgs: [currentVId + vOffset], limit: 1);
              if (vRes.isEmpty) { fullMatch = false; break; }
              final v = BibleVerse.fromJson(vRes.first);

              if (wIdx >= v.styledWords.length) {
                vOffset++; wIdx = 0;
                final nVRes = await db.query('bible', where: 'id = ?', whereArgs: [currentVId + vOffset], limit: 1);
                if (nVRes.isEmpty) { fullMatch = false; break; }
                final nextV = BibleVerse.fromJson(nVRes.first);
                if (!nextV.styledWords[wIdx].text.toLowerCase().contains(qParts[q])) { fullMatch = false; break; }
                foundWords.add(nextV.styledWords[wIdx].text);
                if (q == 0) startLoc = BibleLogic.formatLocation(nextV.bookAbbreviation, nextV.chapter, nextV.verse, wIdx + 1, wIdx + 1);
                endLoc = BibleLogic.formatLocation(nextV.bookAbbreviation, nextV.chapter, nextV.verse, wIdx + 1, wIdx + 1);
                wIdx++;
              } else {
                if (!v.styledWords[wIdx].text.toLowerCase().contains(qParts[q])) { fullMatch = false; break; }
                foundWords.add(v.styledWords[wIdx].text);
                if (q == 0) startLoc = BibleLogic.formatLocation(v.bookAbbreviation, v.chapter, v.verse, wIdx + 1, wIdx + 1);
                endLoc = BibleLogic.formatLocation(v.bookAbbreviation, v.chapter, v.verse, wIdx + 1, wIdx + 1);
                wIdx++;
              }
            }

            if (fullMatch) {
              String rangeLoc = startLoc.split(':').take(2).join(':') == endLoc.split(':').take(2).join(':')
                ? "${startLoc.split(':').take(3).join(':')}-${endLoc.split(':').last}"
                : "${startLoc}_$endLoc";
              addResult(BibleMatch(phrase: foundWords.join(' '), location: rangeLoc, verse: startV));
              i += qParts.length - 1;
            }
          }
        }
      }
    }
    return results;
  }

  // --- DICTIONARY, NOTES & PATHS ---
  Future<int> addDictionaryEntry(String term, String def, String loc) async => (await database).insert('dictionary', {'term': term, 'definition': def, 'location': loc, 'created_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<Map<String, dynamic>>> getDictionary() async => (await database).query('dictionary', orderBy: 'term ASC');
  Future<int> saveNote({required String title, required String content, required String location}) async => (await database).insert('notes', {'title': title, 'content': content, 'location': location, 'created_at': DateTime.now().toIso8601String()});
  Future<List<Map<String, dynamic>>> getNotes() async => (await database).query('notes', orderBy: 'created_at DESC');
  Future<int> createStudyPath(String name, String desc) async => (await database).insert('study_paths', {'name': name, 'description': desc, 'created_at': DateTime.now().toIso8601String()});
  Future<List<Map<String, dynamic>>> getStudyPaths() async => (await database).query('study_paths', orderBy: 'created_at DESC');
  Future<void> addLocationToPath(int pathId, String location) async => (await database).insert('study_path_items', {'path_id': pathId, 'location': location, 'ordinal': 1});
  Future<List<Map<String, dynamic>>> getPathItems(int pathId) async => (await database).query('study_path_items', where: 'path_id = ?', whereArgs: [pathId]);
}

class BibleMatch {
  final String phrase;
  final String location;
  final BibleVerse verse;
  BibleMatch({required this.phrase, required this.location, required this.verse});
}
