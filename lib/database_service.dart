import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'bible_model.dart';
import 'bible_logic.dart';

class BibleMatch {
  final String phrase;
  final String location;
  final BibleVerse verse;
  final List<BibleVerse> extraVerses;
  final List<String> phraseSegments;
  final int startWord;
  final int endWord;
  
  BibleMatch({
    required this.phrase, 
    required this.location, 
    required this.verse, 
    this.extraVerses = const [],
    List<String>? phraseSegments,
    required this.startWord, 
    required this.endWord
  }) : this.phraseSegments = phraseSegments ?? [phrase];

  Map<String, dynamic> toJson() => {
    'phrase': phrase,
    'location': location,
    'verse': verse.toJson(),
    'extraVerses': extraVerses.map((v) => v.toJson()).toList(),
    'phraseSegments': phraseSegments,
    'startWord': startWord,
    'endWord': endWord,
  };

  factory BibleMatch.fromJson(Map<String, dynamic> json) => BibleMatch(
    phrase: json['phrase'],
    location: json['location'],
    verse: BibleVerse.fromJson(json['verse']),
    extraVerses: (json['extraVerses'] as List? ?? []).map((v) => BibleVerse.fromJson(v)).toList(),
    phraseSegments: (json['phraseSegments'] as List?)?.map((e) => e.toString()).toList(),
    startWord: json['startWord'],
    endWord: json['endWord'],
  );
}

class WitnessPair {
  final BibleMatch witness; 
  final BibleMatch spiritual; 
  WitnessPair({required this.witness, required this.spiritual});
}

class VectorSpaceRow {
  final String word;
  final String location;
  final int bookOrder;
  List<WitnessPair> witnessesBefore = [];
  List<WitnessPair> witnessesAfter = [];
  VectorSpaceRow({required this.word, required this.location}) : bookOrder = BibleLogic.getBookOrder(location);
}

class VectorSpaceResult {
  final List<VectorSpaceRow> rows;
  final int totalCount;
  VectorSpaceResult(this.rows, this.totalCount);
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;
  final RegExp _terminalPunct = RegExp(r'[.!?;:¶]');
  final Map<String, List<BibleMatch>> _searchCache = {};

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
      path, version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA journal_mode=WAL');
        await db.execute('PRAGMA synchronous=NORMAL');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('CREATE TABLE library (id INTEGER PRIMARY KEY AUTOINCREMENT, book_title TEXT, chapter_title TEXT, chapter_index INTEGER, content TEXT, source_vectors TEXT, created_at TEXT)');
          await db.execute('CREATE VIRTUAL TABLE library_fts USING fts5(book_title, chapter_title, content, tokenize = "unicode61")');
        }
      },
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE bible (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, abbr TEXT, chapter INTEGER, verse INTEGER, word_count INTEGER, words_data TEXT, plain_text TEXT)');
        await db.execute('CREATE INDEX idx_bible_lookup ON bible (book, chapter)');
        await db.execute('CREATE INDEX idx_bible_abbr ON bible (abbr)');
        await db.execute('CREATE VIRTUAL TABLE bible_fts USING fts5(book, abbr, content, verse_id UNINDEXED, tokenize = "unicode61 remove_diacritics 0")');
        await db.execute('CREATE TABLE constants (id INTEGER PRIMARY KEY AUTOINCREMENT, phrase TEXT UNIQUE, created_at TEXT)');
        await db.execute('CREATE TABLE library (id INTEGER PRIMARY KEY AUTOINCREMENT, book_title TEXT, chapter_title TEXT, chapter_index INTEGER, content TEXT, source_vectors TEXT, created_at TEXT)');
        await db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, content TEXT, location TEXT, created_at TEXT)');
      },
    );
  }

  Future<void> initialize() async {
    final db = await database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM bible');
    if ((Sqflite.firstIntValue(countResult) ?? 0) == 0) {
      try {
        final String jsonString = await rootBundle.loadString('assets/Bible.json');
        final List<dynamic> data = await compute(jsonDecode, jsonString) as List<dynamic>;
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (var item in data) {
            String abbr = item['BN']?.toString() ?? '';
            int chapter = int.tryParse(item['CHAPTER']?.toString() ?? '0') ?? 0;
            // Skip Lev 0 artifacts
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
              'book': item['BOOKS'], 'abbr': abbr, 'chapter': chapter, 'verse': int.tryParse(item['VERSE']?.toString() ?? '0'),
              'word_count': wordCount, 'words_data': json.encode(words), 'plain_text': plainWords.join(' '),
            });
          }
          await batch.commit(noResult: true);
          final bibleData = await txn.query('bible', columns: ['id', 'book', 'abbr', 'plain_text']);
          final batchFts = txn.batch();
          for (var row in bibleData) { batchFts.insert('bible_fts', { 'book': row['book'], 'abbr': row['abbr'], 'content': row['plain_text'], 'verse_id': row['id'] }); }
          await batchFts.commit(noResult: true);
        });
      } catch (e) { debugPrint("IMPORT ERROR: $e"); }
    }
  }

  Future<void> clearDatabase() async {
    final db = await database;
    await db.execute('DELETE FROM bible');
    await db.execute('DELETE FROM bible_fts');
    _searchCache.clear();
    await initialize();
  }

  Future<List<BibleMatch>> search(String query) async {
    final String cleanQuery = query.trim().toLowerCase().replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanQuery.isEmpty) return [];
    if (_searchCache.containsKey(cleanQuery)) return _searchCache[cleanQuery]!;

    final db = await database;
    final loc = BibleLogic.parseLocation(query);
    if (loc != null) return _searchByLocation(loc);

    try {
      final ftsQuery = cleanQuery.contains(' ') ? '"$cleanQuery"' : cleanQuery;
      final queryWords = cleanQuery.split(' ');
      final results = await db.rawQuery('SELECT b.* FROM bible b JOIN bible_fts f ON b.id = f.verse_id WHERE f.content MATCH ? ORDER BY b.id ASC', [ftsQuery]);
      List<BibleMatch> allMatches = [];
      for (var m in results) {
        final verse = BibleVerse.fromJson(m);
        allMatches.addAll(_findMatchesInVerse(verse, queryWords));
      }
      if (allMatches.isEmpty && queryWords.length > 1) allMatches.addAll(await _searchCrossVerse(queryWords));
      _searchCache[cleanQuery] = allMatches;
      return allMatches;
    } catch (e) { return []; }
  }

  List<BibleMatch> _findMatchesInVerse(BibleVerse verse, List<String> queryWords) {
    List<BibleMatch> matches = [];
    final words = verse.styledWords.map((w) => w.text.toLowerCase().replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), '')).toList();
    for (int i = 0; i <= words.length - queryWords.length; i++) {
      bool found = true;
      for (int j = 0; j < queryWords.length; j++) { if (i + j >= words.length || words[i + j] != queryWords[j]) { found = false; break; } }
      if (found) {
        int sw = i + 1; int ew = i + queryWords.length;
        matches.add(BibleMatch(phrase: verse.styledWords.sublist(sw - 1, ew).map((w) => w.text).join(' '), location: BibleLogic.formatLocation(verse.bookAbbreviation, verse.chapter, verse.verse, sw, ew), verse: verse, startWord: sw, endWord: ew));
        i = ew - 1;
      }
    }
    return matches;
  }

  Future<List<BibleMatch>> _searchCrossVerse(List<String> queryWords) async {
    final db = await database;
    final String firstWord = queryWords.first;
    final candidateResults = await db.rawQuery('SELECT b.* FROM bible b JOIN bible_fts f ON b.id = f.verse_id WHERE f.content MATCH ? ORDER BY b.id ASC', [firstWord]);
    List<BibleMatch> allMatches = [];
    for (var m in candidateResults) {
      final v1 = BibleVerse.fromJson(m);
      final words1 = v1.styledWords.map((w) => w.text.toLowerCase().replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), '')).toList();
      for (int i = 0; i < words1.length; i++) {
        if (words1[i] == firstWord) {
          int phraseIdx = 0; int currentVerseId = v1.id; int wordInVerseIdx = i; bool mismatch = false;
          List<BibleVerse> matchedVerses = []; List<String> locSegments = []; List<String> phraseSegments = [];
          int finalEndWord = 0;
          while (phraseIdx < queryWords.length) {
            final vMap = await db.query('bible', where: 'id = ?', whereArgs: [currentVerseId]);
            if (vMap.isEmpty) { mismatch = true; break; }
            final v = BibleVerse.fromJson(vMap.first);
            final vWords = v.styledWords.map((w) => w.text.toLowerCase().replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), '')).toList();
            int startInV = wordInVerseIdx + 1; int endInV = startInV;
            while (wordInVerseIdx < vWords.length && phraseIdx < queryWords.length) {
              if (vWords[wordInVerseIdx] == queryWords[phraseIdx]) { endInV = wordInVerseIdx + 1; wordInVerseIdx++; phraseIdx++; } else { mismatch = true; break; }
            }
            if (currentVerseId == v1.id) finalEndWord = endInV;
            matchedVerses.add(v);
            locSegments.add(BibleLogic.formatLocation(v.bookAbbreviation, v.chapter, v.verse, startInV, endInV));
            phraseSegments.add(v.styledWords.sublist(max(0, startInV - 1), min(v.styledWords.length, endInV)).map((w) => w.text).join(' '));
            if (mismatch) break;
            if (phraseIdx < queryWords.length) { currentVerseId++; wordInVerseIdx = 0; }
          }
          if (!mismatch) allMatches.add(BibleMatch(phrase: phraseSegments.join(' '), location: locSegments.join('_'), verse: matchedVerses.first, extraVerses: matchedVerses.skip(1).toList(), phraseSegments: phraseSegments, startWord: i + 1, endWord: finalEndWord));
        }
      }
    }
    return allMatches;
  }

  Future<List<BibleMatch>> _searchByLocation(BibleLocation loc) async {
    final db = await database;
    final locMaps = await db.query('bible', where: 'abbr = ? COLLATE NOCASE AND chapter = ? AND (verse = ?)', whereArgs: [loc.bookAbbr, loc.chapter, loc.verse]);
    List<BibleMatch> results = [];
    for (var m in locMaps) {
      final verse = BibleVerse.fromJson(m);
      int start = loc.startWord; int end = loc.endWord;
      if (start == 1 && end == 0) end = verse.wordCount;
      int effEnd = (end >= start && end <= verse.wordCount) ? end : start;
      results.add(BibleMatch(phrase: verse.styledWords.sublist(max(0, start - 1), min(verse.styledWords.length, effEnd)).map((w) => w.text).join(' '), location: BibleLogic.formatLocation(verse.bookAbbreviation, verse.chapter, verse.verse, start, effEnd), verse: verse, startWord: start, endWord: effEnd));
    }
    return results;
  }

  Future<VectorSpaceResult> getVectorSpaceGrid(String query, {int n = 3, bool includeBefore = true, bool includeAfter = true, int limit = 10, int offset = 0, String definitionLevel = 'compact'}) async {
    var baseMatches = await search(query);
    int totalCount = baseMatches.length;
    if (offset < baseMatches.length) baseMatches = baseMatches.skip(offset).toList(); else baseMatches = [];
    baseMatches = baseMatches.take(limit).toList();
    final List<VectorSpaceRow> rows = [];
    for (var match in baseMatches) {
      final row = VectorSpaceRow(word: match.phrase, location: match.location);
      if (includeBefore) row.witnessesBefore = await _findAllContextWitnesses(match, n, true, level: definitionLevel);
      if (includeAfter) row.witnessesAfter = await _findAllContextWitnesses(match, n, false, level: definitionLevel);
      rows.add(row);
    }
    return VectorSpaceResult(rows..sort((a,b) => a.bookOrder.compareTo(b.bookOrder)), totalCount);
  }

  Future<List<WitnessPair>> _findAllContextWitnesses(BibleMatch anchor, int n, bool isBefore, {String level = 'compact'}) async {
    List<WitnessPair> results = [];
    int startVerseId = anchor.verse.id;
    int baseWordIdx = isBefore ? anchor.startWord - 1 : (anchor.endWord == 0 ? anchor.startWord : anchor.endWord);
    
    // EXCLUSIVE N-LENGTH SEARCH: Magnitude must be exactly n
    List<BibleWord> sequenceWords = [];
    for (int i = 0; i < n; i++) {
      int offset = isBefore ? -(n - i) : i;
      final res = await _getWordAtGlobalOffset(startVerseId, baseWordIdx, offset);
      if (res != null) sequenceWords.add(res.word);
    }

    if (sequenceWords.length == n) {
      final String witnessStr = sequenceWords.map((w) => w.text).join(' ');
      final matches = await search(witnessStr);
      for (var m in matches) {
        if (m.location != anchor.location) {
          // Found a witness location. Now find the spiritual match (Agreeing Grace) at THIS location.
          // For AFTER context (isBefore=false), we look for the phrase IMMEDIATELY PRECEDING the witness.
          final spiritualRes = await _getWordAtGlobalOffset(m.verse.id, m.startWord - 1, -1);
          if (spiritualRes != null) {
            final spiritualMatch = BibleMatch(
              phrase: spiritualRes.word.text,
              location: BibleLogic.formatLocation(spiritualRes.verse.bookAbbreviation, spiritualRes.verse.chapter, spiritualRes.verse.verse, spiritualRes.word.index, spiritualRes.word.index),
              verse: spiritualRes.verse,
              startWord: spiritualRes.word.index,
              endWord: spiritualRes.word.index,
            );
            results.add(WitnessPair(
              witness: m,
              spiritual: await _refineDefinition(spiritualMatch, level, isBefore)
            ));
          }
        }
      }
    }
    return results;
  }

  Future<({BibleVerse verse, BibleWord word})?> _getWordAtGlobalOffset(int startVerseId, int wordIdxInStartVerse, int offset) async {
    final db = await database;
    int currentVerseId = startVerseId;
    int currentWordIdx = wordIdxInStartVerse + offset;

    while (true) {
      final maps = await db.query('bible', where: 'id = ?', whereArgs: [currentVerseId]);
      if (maps.isEmpty) return null;
      final verse = BibleVerse.fromJson(maps.first);
      if (verse.styledWords.isEmpty) return null;
      
      if (currentWordIdx >= 0 && currentWordIdx < verse.styledWords.length) {
        return (verse: verse, word: verse.styledWords[currentWordIdx]);
      } else if (currentWordIdx < 0) {
        currentVerseId--;
        final prevMaps = await db.query('bible', where: 'id = ?', whereArgs: [currentVerseId]);
        if (prevMaps.isEmpty) return null;
        final prevVerse = BibleVerse.fromJson(prevMaps.first);
        currentWordIdx += prevVerse.styledWords.length;
      } else {
        currentWordIdx -= verse.styledWords.length;
        currentVerseId++;
      }
    }
  }

  Future<BibleMatch> _refineDefinition(BibleMatch m, String level, bool isBefore) async {
    if (level == 'compact') {
      final db = await database;
      // Start with the words of the verse where the match was found
      List<BibleWord> allWords = List.from(m.verse.styledWords);
      List<BibleVerse> extraVerses = [];
      List<String> locSegments = [m.location];
      
      // sw and ew are 1-based indices relative to 'allWords'
      int sw = m.startWord;
      int ew = m.endWord > 0 ? m.endWord : m.startWord;

      if (allWords.isEmpty) return m;

      if (!isBefore) {
        // Expand BACKWARD (for CSTWS_AFT)
        int currentVerseId = m.verse.id;
        int wordIdx = sw - 2; // relative to 'allWords'
        bool foundTerminal = false;
        
        while (!foundTerminal) {
          if (wordIdx < 0) {
            currentVerseId--;
            final vMap = await db.query('bible', where: 'id = ?', whereArgs: [currentVerseId]);
            if (vMap.isEmpty) break;
            final v = BibleVerse.fromJson(vMap.first);
            if (v.styledWords.isEmpty) break;
            
            extraVerses.insert(0, v);
            
            // Adjust sw and ew before inserting at the start
            final int addedCount = v.styledWords.length;
            allWords.insertAll(0, v.styledWords);
            sw += addedCount;
            ew += addedCount;
            wordIdx = addedCount - 1;
          }
          
          if (_terminalPunct.hasMatch(allWords[wordIdx].text)) {
            sw = wordIdx + 2;
            foundTerminal = true;
          } else {
            wordIdx--;
          }
        }
        if (!foundTerminal) sw = 1;
      } else {
        // Expand FORWARD (for CSTWS_BEF)
        int currentVerseId = m.verse.id;
        int wordIdx = ew; // relative to 'allWords'
        bool foundTerminal = false;
        
        while (!foundTerminal) {
          if (wordIdx >= allWords.length) {
            currentVerseId++;
            final vMap = await db.query('bible', where: 'id = ?', whereArgs: [currentVerseId]);
            if (vMap.isEmpty) break;
            final v = BibleVerse.fromJson(vMap.first);
            if (v.styledWords.isEmpty) break;
            
            extraVerses.add(v);
            allWords.addAll(v.styledWords);
          }
          
          if (_terminalPunct.hasMatch(allWords[wordIdx].text)) {
            ew = wordIdx + 1;
            foundTerminal = true;
          } else {
            wordIdx++;
          }
        }
        if (!foundTerminal) ew = allWords.length;
      }

      // Final clamping with safety
      final int len = allWords.length;
      sw = sw.clamp(1, len);
      ew = ew.clamp(sw, len);

      // Re-calculate location based on actual span across verses
      String finalLoc = m.location;
      if (extraVerses.isNotEmpty) {
        List<String> locs = [];
        if (!isBefore) {
          for (var ev in extraVerses) locs.add(BibleLogic.formatLocation(ev.bookAbbreviation, ev.chapter, ev.verse, 1, ev.wordCount));
          locs.add(m.location);
        } else {
          locs.add(m.location);
          for (var ev in extraVerses) locs.add(BibleLogic.formatLocation(ev.bookAbbreviation, ev.chapter, ev.verse, 1, ev.wordCount));
        }
        finalLoc = locs.join('_');
      }

      final resultPhrase = allWords.sublist(sw - 1, ew).map((w) => w.text).join(' ');
      return BibleMatch(
        phrase: resultPhrase,
        location: finalLoc,
        verse: m.verse,
        extraVerses: extraVerses,
        startWord: sw,
        endWord: ew,
      );
    }
    return m;
  }

  Future<int> countSearchMatches(String query) async { final matches = await search(query); return matches.length; }
  Future<Map<String, String>> getContinuityMap() async { try { final String jsonString = await rootBundle.loadString('assets/CONTINUITY.json'); final List<dynamic> data = json.decode(jsonString); return { for (var item in data) item['FunctionWord'].toString().toLowerCase() : item['Symbol'].toString() }; } catch (_) { return {}; } }
  Future<Map<String, String>> getParenthesesMap() async { try { final String jsonString = await rootBundle.loadString('assets/PARENTHESES.json'); final List<dynamic> data = json.decode(jsonString); return { for (var item in data) item['AuxVerb'].toString().toLowerCase().replaceAll(RegExp(r'[.,;:!?¶\(\)\[\]]'), '').trim() : item['Symbol'].toString() }; } catch (_) { return {}; } }
  Future<List<BibleVerse>> getChapter(String book, int chapter) async { final db = await database; final maps = await db.query('bible', where: 'book = ? AND chapter = ?', whereArgs: [book, chapter], orderBy: 'verse ASC, id ASC'); return maps.map((m) => BibleVerse.fromJson(m)).toList(); }
  
  Future<List<BibleVerse>> getChapterByAbbr(String abbr, int chapter) async {
    final db = await database;
    final maps = await db.query('bible', where: 'abbr = ? COLLATE NOCASE AND chapter = ?', whereArgs: [abbr, chapter], orderBy: 'verse ASC, id ASC');
    return maps.map((m) => BibleVerse.fromJson(m)).toList();
  }

  Future<List<int>> getVerseNumbers(String book, int chapter) async { final db = await database; final result = await db.rawQuery('SELECT verse FROM bible WHERE book = ? AND chapter = ? AND verse > 0 ORDER BY verse ASC', [book, chapter]); return result.map((m) => (m['verse'] ?? 0) as int).toList(); }
  Future<List<String>> getBooks() async { final db = await database; final maps = await db.rawQuery('SELECT DISTINCT book FROM bible ORDER BY id ASC'); return maps.map((m) => m['book'] as String).toList(); }
  Future<List<int>> getChapters(String book) async { final db = await database; final result = await db.rawQuery('SELECT DISTINCT chapter FROM bible WHERE book = ? ORDER BY chapter ASC', [book]); return result.map((m) => (m['chapter'] ?? 0) as int).toList(); }
  Future<BibleVerse?> getDailyVerse() async { final db = await database; final maps = await db.rawQuery('SELECT * FROM bible WHERE verse > 0 ORDER BY RANDOM() LIMIT 1'); return maps.isEmpty ? null : BibleVerse.fromJson(maps.first); }
  Future<BibleVerse?> getSpecificVerse(String book, int chapter, int verse) async { final db = await database; final maps = await db.query('bible', where: 'book = ? AND chapter = ? AND verse = ?', whereArgs: [book, chapter, verse], limit: 1); return maps.isEmpty ? null : BibleVerse.fromJson(maps.first); }
  Future<BibleVerse?> getSpecificVerseByAbbr(String abbr, int chapter, int verse) async { final db = await database; final maps = await db.query('bible', where: 'abbr = ? COLLATE NOCASE AND chapter = ? AND verse = ?', whereArgs: [abbr, chapter, verse], limit: 1); return maps.isEmpty ? null : BibleVerse.fromJson(maps.first); }
  Future<List<Map<String, dynamic>>> getNotes() async => (await database).query('notes', orderBy: 'created_at DESC');
  Future<List<String>> getLibraryBooks() async { final db = await database; final results = await db.rawQuery('SELECT DISTINCT book_title FROM library ORDER BY book_title ASC'); return results.map((r) => r['book_title'] as String).toList(); }
  Future<void> addLibraryChapter(String book, String chapter, int index, String content, List<String> vectors) async { final db = await database; final now = DateTime.now().toIso8601String(); await db.insert('library', { 'book_title': book, 'chapter_title': chapter, 'chapter_index': index, 'content': content, 'source_vectors': vectors.join(','), 'created_at': now }); }
}
