import 'dart:convert';

class BibleWord {
  final String text;
  final bool isItalic;
  final int index;

  BibleWord({
    required this.text,
    required this.isItalic,
    required this.index,
  });

  Map<String, dynamic> toJson() => {
    't': text,
    'i': isItalic ? 1 : 0,
  };
}

class BibleVerse {
  final int id;
  final String book;
  final String bookAbbreviation;
  final int chapter;
  final int verse;
  final int bookOrder;
  final String bookChapterVerse;
  final List<BibleWord> styledWords;
  final int wordCount;

  BibleVerse({
    required this.id,
    required this.book,
    required this.bookAbbreviation,
    required this.chapter,
    required this.verse,
    required this.bookOrder,
    required this.bookChapterVerse,
    required this.styledWords,
    required this.wordCount,
  });

  String get text => styledWords.map((w) => w.text).join(' ');

  Map<String, dynamic> toJson() => {
    'id': id,
    'book': book,
    'abbr': bookAbbreviation,
    'chapter': chapter,
    'verse': verse,
    'BKORDER': bookOrder,
    'BKCHAPVERSE': bookChapterVerse,
    'words_data': jsonEncode(styledWords.map((w) => w.toJson()).toList()),
    'word_count': wordCount,
  };

  factory BibleVerse.fromJson(Map<String, dynamic> json) {
    List<BibleWord> words = [];
    
    if (json['words_data'] != null) {
      try {
        List<dynamic> data = jsonDecode(json['words_data']);
        for (int i = 0; i < data.length; i++) {
          words.add(BibleWord(
            text: data[i]['t']?.toString() ?? '',
            isItalic: data[i]['i'] == 1,
            index: i + 1
          ));
        }
      } catch (_) {}
    } 
    
    if (words.isEmpty) {
      int count = int.tryParse((json['WORDCOUNT'] ?? json['word_count'])?.toString() ?? '0') ?? 0;
      bool inBrackets = false;
      for (int i = 1; i <= count; i++) {
        String rawWord = json[i.toString()]?.toString() ?? '';
        if (rawWord.startsWith('[')) inBrackets = true;
        bool isItalic = inBrackets;
        if (rawWord.contains(']')) inBrackets = false;
        String cleanWord = rawWord.replaceAll('[', '').replaceAll(']', '');
        words.add(BibleWord(text: cleanWord, isItalic: isItalic, index: i));
      }
    }

    String abbr = (json['BN'] ?? json['abbr'])?.toString() ?? '';
    int ch = int.tryParse((json['CHAPTER'] ?? json['chapter'])?.toString() ?? '0') ?? 0;
    int v = int.tryParse((json['VERSE'] ?? json['verse'])?.toString() ?? '0') ?? 0;

    return BibleVerse(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      book: (json['BOOKS'] ?? json['book'])?.toString() ?? '',
      bookAbbreviation: abbr,
      chapter: ch,
      verse: v,
      bookOrder: int.tryParse((json['BKORDER'] ?? '0').toString()) ?? 0,
      bookChapterVerse: json['BKCHAPVERSE']?.toString() ?? '$abbr$ch:$v',
      styledWords: words,
      wordCount: words.length,
    );
  }
}

class AudioSyncWord {
  final double begin;
  final double end;
  final String text;

  AudioSyncWord({
    required this.begin,
    required this.end,
    required this.text,
  });

  factory AudioSyncWord.fromJson(Map<String, dynamic> json) {
    return AudioSyncWord(
      begin: double.tryParse((json['begin'] ?? json['start'] ?? 0).toString()) ?? 0.0,
      end: double.tryParse((json['end'] ?? 0).toString()) ?? 0.0,
      text: (json['label'] ?? json['word'] ?? json['text'] ?? '').toString(),
    );
  }
}

class BibleLocation {
  final String bookAbbr;
  final int chapter;
  final int verse;
  final int startWord;
  final int endWord;
  BibleLocation({required this.bookAbbr, required this.chapter, required this.verse, required this.startWord, required this.endWord});
}

class DictionaryEntry {
  final int? id;
  final String term;
  final String definition;
  final String location;
  final String createdAt;
  final int n;
  final String place;
  final String finding;

  DictionaryEntry({
    this.id, 
    required this.term, 
    required this.definition, 
    required this.location, 
    required this.createdAt,
    this.n = 0,
    this.place = '',
    this.finding = 'Manual Finding',
  });

  Map<String, dynamic> toMap() => {
    'term': term,
    'definition': definition,
    'location': location,
    'created_at': createdAt,
    'n': n,
    'place': place,
    'finding': finding,
  };
}
