import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'holybible_v13.db');

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
          CREATE VIRTUAL TABLE bible_fts USING fts5(
            book,
            abbr,
            content,
            verse_id UNINDEXED,
            tokenize = "unicode61 remove_diacritics 0"
          )
        ''');
        await db.execute('''
          CREATE TABLE constants (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phrase TEXT UNIQUE,
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
        final now = DateTime.now().toIso8601String();
        final initial = ["Holy Mountain", "Word of God", "Son of man", "Kingdom of heaven", "Spirit of God", "Thus saith the LORD", "children of Israel", "tabernacle of the congregation", "Lord of hosts", "In the beginning"];
        for (var p in initial) {
          await db.insert('constants', {'phrase': p, 'created_at': now});
        }
      },
    );
  }

  Future<void> initialize() async {
    final db = await database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM bible');
    final count = Sqflite.firstIntValue(countResult) ?? 0;

    if (count == 0) {
      debugPrint("IMPORT START: Loading Bible.json...");
      try {
        final String jsonString = await rootBundle.loadString('assets/Bible.json');
        final List<dynamic> data = await compute(jsonDecode, jsonString) as List<dynamic>;

        await db.transaction((txn) async {
          final batch = txn.batch();
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

            batch.insert('bible', {
              'book': item['BOOKS'],
              'abbr': abbr,
              'chapter': chapter,
              'verse': int.tryParse(item['VERSE']?.toString() ?? '0'),
              'word_count': wordCount,
              'words_data': json.encode(words),
              'plain_text': plainWords.join(' '),
            });
          }
          await batch.commit(noResult: true);
          
          final batchFts = txn.batch();
          final bibleData = await txn.query('bible', columns: ['id', 'book', 'abbr', 'plain_text']);
          for (var row in bibleData) {
            batchFts.insert('bible_fts', {
              'book': row['book'],
              'abbr': row['abbr'],
              'content': row['plain_text'],
              'verse_id': row['id']
            });
          }
          await batchFts.commit(noResult: true);
        });
      } catch (e) { debugPrint("IMPORT ERROR: $e"); }
    }
  }

  Future<int> countSearchMatches(String query) async {
    final db = await database;
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return 0;
    
    final loc = BibleLogic.parseLocation(cleanQuery);
    if (loc != null) return 1;

    try {
      final ftsSafeQuery = cleanQuery.replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), ' ').trim();
      if (ftsSafeQuery.isEmpty) return 0;
      final ftsQuery = ftsSafeQuery.contains(' ') ? '"$ftsSafeQuery"' : ftsSafeQuery;
      final results = await db.rawQuery('SELECT COUNT(*) as count FROM bible_fts WHERE content MATCH ?', [ftsQuery]);
      return Sqflite.firstIntValue(results) ?? 0;
    } catch (e) { return 0; }
  }

  Future<List<BibleMatch>> search(String query) async {
    final db = await database;
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];
    final loc = BibleLogic.parseLocation(cleanQuery);
    if (loc != null) return _searchByLocation(loc);

    try {
      final ftsSafeQuery = cleanQuery.replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), ' ').trim();
      if (ftsSafeQuery.isEmpty) return [];
      final ftsQuery = ftsSafeQuery.contains(' ') ? '"$ftsSafeQuery"' : ftsSafeQuery;
      final results = await db.rawQuery('SELECT b.* FROM bible b JOIN bible_fts f ON b.id = f.verse_id WHERE f.content MATCH ? ORDER BY b.id ASC', [ftsQuery]);
      final queryWords = ftsSafeQuery.toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

      return results.map((m) {
        final verse = BibleVerse.fromJson(m);
        final words = verse.styledWords.map((w) => w.text.toLowerCase().replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), '')).toList();
        int startWord = 1; int endWord = verse.wordCount;
        for (int i = 0; i <= words.length - queryWords.length; i++) {
          bool found = true;
          for (int j = 0; j < queryWords.length; j++) { 
            if (i+j >= words.length || words[i+j] != queryWords[j]) { found = false; break; } 
          }
          if (found) { startWord = i + 1; endWord = i + queryWords.length; break; }
        }
        // Capture EXACT text from verse including punctuation
        final exactText = verse.styledWords.sublist(startWord - 1, endWord).map((w) => w.text).join(' ');
        return BibleMatch(phrase: exactText, location: BibleLogic.formatLocation(verse.bookAbbreviation, verse.chapter, verse.verse, startWord, endWord), verse: verse, startWord: startWord, endWord: endWord);
      }).toList();
    } catch (e) { return []; }
  }

  Future<List<BibleMatch>> _searchByLocation(BibleLocation loc) async {
    final db = await database;
    final locMaps = await db.query('bible', where: 'abbr = ? COLLATE NOCASE AND chapter = ? AND (verse = ? OR ? = 0)', whereArgs: [loc.bookAbbr, loc.chapter, loc.verse, loc.verse]);
    List<BibleMatch> results = [];
    for (var m in locMaps) {
      final verse = BibleVerse.fromJson(m);
      int start = loc.startWord; int end = loc.endWord;
      if (start == 1 && end == 0) end = verse.wordCount;
      int effEnd = (end > 0 && end <= verse.wordCount) ? end : start;
      results.add(BibleMatch(phrase: verse.styledWords.sublist(start - 1, effEnd).map((w) => w.text).join(' '), location: BibleLogic.formatLocation(verse.bookAbbreviation, verse.chapter, verse.verse, start, effEnd), verse: verse, startWord: start, endWord: effEnd));
    }
    return results;
  }

  Future<List<WtotagResult>> wtotag(String query, {bool isBefore = true, int n = 3}) async {
    final matches = await search(query);
    return _wtotagInternal(matches, isBefore: isBefore, n: n);
  }

  Future<List<WtotagResult>> _wtotagInternal(List<BibleMatch> matches, {bool isBefore = true, int n = 3}) async {
    if (matches.isEmpty) return [];
    final RegExp punct = RegExp(r'[.,;:!?¶\(\)\[\]]');
    List<WtotagResult> results = [];
    for (var match in matches) {
      final verse = match.verse;
      final loc = BibleLogic.parseLocation(match.location);
      if (loc == null) continue;
      for (int currentN = n; currentN >= 2; currentN--) {
        if (isBefore) {
          int startIdx = loc.startWord - currentN;
          if (startIdx >= 1) {
            int actualStart = startIdx;
            for (int i = loc.startWord - 1; i >= startIdx; i--) { if (verse.styledWords[i - 1].text.contains(punct)) { actualStart = i + 1; break; } }
            if (loc.startWord - actualStart >= 2) {
              String phrase = verse.styledWords.sublist(actualStart - 1, loc.startWord - 1).map((w) => w.text).join(' ');
              String location = BibleLogic.formatLocation(verse.bookAbbreviation, verse.chapter, verse.verse, actualStart, loc.startWord - 1);
              final contextMatches = await search(phrase);
              if (contextMatches.length > 1) {
                results.add(WtotagResult(originalMatch: match, contextMatch: BibleMatch(phrase: phrase, location: location, verse: verse, startWord: actualStart, endWord: loc.startWord - 1), contextMatches: contextMatches, nValue: loc.startWord - actualStart, isBefore: isBefore));
              }
            }
          }
        } else {
          int startIdxAfter = loc.endWord == 0 ? loc.startWord : loc.endWord;
          int endIdx = startIdxAfter + currentN;
          if (endIdx <= verse.wordCount) {
            int actualEnd = endIdx;
            for (int i = startIdxAfter + 1; i <= endIdx; i++) { if (verse.styledWords[i - 1].text.contains(punct)) { actualEnd = i; break; } }
            if (actualEnd - startIdxAfter >= 2) {
              String phrase = verse.styledWords.sublist(startIdxAfter, actualEnd).map((w) => w.text).join(' ');
              String location = BibleLogic.formatLocation(verse.bookAbbreviation, verse.chapter, verse.verse, startIdxAfter + 1, actualEnd);
              final contextMatches = await search(phrase);
              if (contextMatches.length > 1) {
                results.add(WtotagResult(originalMatch: match, contextMatch: BibleMatch(phrase: phrase, location: location, verse: verse, startWord: startIdxAfter + 1, endWord: actualEnd), contextMatches: contextMatches, nValue: actualEnd - startIdxAfter, isBefore: isBefore));
              }
            }
          }
        }
      }
    }
    return results;
  }

  Future<List<VectorSpaceRow>> getVectorSpaceGrid(String query, {int n = 3, bool includeBefore = true, bool includeAfter = true, int? limit, int? offset}) async {
    final Map<String, VectorSpaceRow> matrix = {};
    var baseMatches = await search(query);

    if (offset != null && offset < baseMatches.length) {
      baseMatches = baseMatches.skip(offset).toList();
    }
    if (limit != null && limit < baseMatches.length) {
      baseMatches = baseMatches.take(limit).toList();
    }

    for (var m in baseMatches) { 
      matrix[m.location] = VectorSpaceRow(word: m.phrase, location: m.location); 
    }
    final RegExp punct = RegExp(r'[.,;:!?¶\(\)\[\]]');

    Future<void> processWitnesses(List<WtotagResult> witnesses, bool isBefore) async {
      for (var w in witnesses) {
        final limitedMatches = w.contextMatches.take(100); 
        for (var m in limitedMatches) {
          final loc = BibleLogic.parseLocation(m.location); if (loc == null) continue;
          if (isBefore) {
            int targetStart = loc.endWord + 1;
            if (targetStart <= m.verse.wordCount) {
              int targetEnd = targetStart;
              for (int i = targetStart; i <= m.verse.wordCount; i++) { targetEnd = i; if (m.verse.styledWords[i - 1].text.contains(punct)) break; }
              final key = w.originalMatch.location;
              matrix.putIfAbsent(key, () => VectorSpaceRow(word: w.originalMatch.phrase, location: key));
              matrix[key]!.witnessesBefore.add(m);
              matrix[key]!.spiritualsBefore.add(BibleMatch(phrase: m.verse.styledWords.sublist(targetStart - 1, targetEnd).map((w) => w.text).join(' '), location: BibleLogic.formatLocation(m.verse.bookAbbreviation, m.verse.chapter, m.verse.verse, targetStart, targetEnd), verse: m.verse, startWord: targetStart, endWord: targetEnd));
            }
          } else {
            int targetEnd = loc.startWord - 1;
            if (targetEnd >= 1) {
              int targetStart = 1;
              for (int i = targetEnd; i >= 1; i--) { if (m.verse.styledWords[i - 1].text.contains(punct)) { targetStart = i + 1; break; } targetStart = i; }
              final key = w.originalMatch.location;
              matrix.putIfAbsent(key, () => VectorSpaceRow(word: w.originalMatch.phrase, location: key));
              matrix[key]!.witnessesAfter.add(m);
              matrix[key]!.spiritualsAfter.add(BibleMatch(phrase: m.verse.styledWords.sublist(targetStart - 1, targetEnd).map((w) => w.text).join(' '), location: BibleLogic.formatLocation(m.verse.bookAbbreviation, m.verse.chapter, m.verse.verse, targetStart, targetEnd), verse: m.verse, startWord: targetStart, endWord: targetEnd));
            }
          }
        }
      }
    }

    if (includeBefore) {
      final beforeWitnesses = await _wtotagInternal(baseMatches, isBefore: true, n: n);
      await processWitnesses(beforeWitnesses, true);
    }
    if (includeAfter) {
      final afterWitnesses = await _wtotagInternal(baseMatches, isBefore: false, n: n);
      await processWitnesses(afterWitnesses, false);
    }

    final results = matrix.values.toList();
    results.sort((a,b) => a.bookOrder.compareTo(b.bookOrder));
    return results;
  }

  Future<Map<String, String>> getContinuityMap() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/CONTINUITY.json');
      final List<dynamic> data = json.decode(jsonString);
      return { for (var item in data) item['FunctionWord'].toString().toLowerCase() : item['Symbol'].toString() };
    } catch (_) { return {}; }
  }

  Future<Map<String, String>> getParenthesesMap() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/PARENTHESES.json');
      final List<dynamic> data = json.decode(jsonString);
      return { for (var item in data) item['AuxVerb'].toString().toLowerCase() : item['Symbol'].toString() };
    } catch (_) { return {}; }
  }

  Future<List<BibleVerse>> getChapter(String book, int chapter) async {
    final db = await database;
    final maps = await db.query('bible', where: 'book = ? AND chapter = ?', whereArgs: [book, chapter], orderBy: 'verse ASC, id ASC');
    return maps.map((m) => BibleVerse.fromJson(m)).toList();
  }

  Future<List<int>> getVerseNumbers(String book, int chapter) async {
    final db = await database;
    final result = await db.rawQuery('SELECT verse FROM bible WHERE book = ? AND chapter = ? AND verse > 0 ORDER BY verse ASC', [book, chapter]);
    return result.map((m) => (m['verse'] ?? 0) as int).toList();
  }

  Future<List<String>> getBooks() async {
    final db = await database;
    final maps = await db.rawQuery('SELECT DISTINCT book FROM bible ORDER BY id ASC');
    return maps.map((m) => m['book'] as String).toList();
  }

  Future<List<int>> getChapters(String book) async {
    final db = await database;
    final result = await db.rawQuery('SELECT DISTINCT chapter FROM bible WHERE book = ? ORDER BY chapter ASC', [book]);
    return result.map((m) => (m['chapter'] ?? 0) as int).toList();
  }

  Future<BibleVerse?> getDailyVerse() async {
    final db = await database;
    final maps = await db.rawQuery('SELECT * FROM bible WHERE verse > 0 ORDER BY RANDOM() LIMIT 1');
    if (maps.isEmpty) return null;
    return BibleVerse.fromJson(maps.first);
  }

  Future<BibleVerse?> getSpecificVerse(String book, int chapter, int verse) async {
    final db = await database;
    final maps = await db.query('bible', where: 'book = ? AND chapter = ? AND verse = ?', whereArgs: [book, chapter, verse], limit: 1);
    if (maps.isEmpty) return null;
    return BibleVerse.fromJson(maps.first);
  }

  Future<List<String>> getConstants() async {
    final db = await database;
    final maps = await db.query('constants', orderBy: 'created_at DESC');
    return maps.map((m) => m['phrase'] as String).toList();
  }

  Future<int> deleteConstant(String phrase) async {
    final db = await database;
    return await db.delete('constants', where: 'phrase = ?', whereArgs: [phrase]);
  }

  Future<List<Map<String, dynamic>>> getNotes() async => (await database).query('notes', orderBy: 'created_at DESC');
}

class BibleMatch {
  final String phrase;
  final String location;
  final BibleVerse verse;
  final int startWord;
  final int endWord;
  BibleMatch({required this.phrase, required this.location, required this.verse, required this.startWord, required this.endWord});
}

class WtotagResult {
  final BibleMatch originalMatch;
  final BibleMatch contextMatch;
  final List<BibleMatch> contextMatches;
  final int nValue;
  final bool isBefore;
  WtotagResult({required this.originalMatch, required this.contextMatch, required this.contextMatches, required this.nValue, required this.isBefore});
}

class VectorSpaceRow {
  final String word;
  final String location;
  final int bookOrder;
  List<BibleMatch> witnessesBefore = [];
  List<BibleMatch> spiritualsBefore = [];
  List<BibleMatch> witnessesAfter = [];
  List<BibleMatch> spiritualsAfter = [];
  VectorSpaceRow({required this.word, required this.location}) : bookOrder = BibleLogic.getBookOrder(location);
}
