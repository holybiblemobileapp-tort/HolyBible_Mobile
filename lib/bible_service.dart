import 'dart:convert';
import 'package:flutter/services.dart';
import 'bible_model.dart';

class BibleService {
  Future<List<BibleVerse>> loadBible(String assetPath) async {
    final String response = await rootBundle.loadString(assetPath);
    final data = await json.decode(response) as List<dynamic>;

    return data
        .map((json) => BibleVerse.fromJson(json))
        .where((verse) => !(verse.bookAbbreviation == 'Lev' && verse.chapter == 0))
        .toList();
  }

  List<Map<String, String>> getBooks() {
    return [
      {'name': 'Preface', 'abbr': 'Pre'},
      {'name': 'Genesis', 'abbr': 'Gen'},
      {'name': 'Exodus', 'abbr': 'Exo'},
      {'name': 'Leviticus', 'abbr': 'Lev'},
      {'name': 'Numbers', 'abbr': 'Num'},
      {'name': 'Deuteronomy', 'abbr': 'Deu'},
      {'name': 'Joshua', 'abbr': 'Jos'},
      {'name': 'Judges', 'abbr': 'Jud'},
      {'name': 'Ruth', 'abbr': 'Rut'},
      {'name': '1 Samuel', 'abbr': '1Sa'},
      {'name': '2 Samuel', 'abbr': '2Sa'},
      {'name': '1 Kings', 'abbr': '1Ki'},
      {'name': '2 Kings', 'abbr': '2Ki'},
      {'name': '1 Chronicles', 'abbr': '1Ch'},
      {'name': '2 Chronicles', 'abbr': '2Ch'},
      {'name': 'Ezra', 'abbr': 'Ezr'},
      {'name': 'Nehemiah', 'abbr': 'Neh'},
      {'name': 'Esther', 'abbr': 'Est'},
      {'name': 'Job', 'abbr': 'Job'},
      {'name': 'Psalms', 'abbr': 'Psa'},
      {'name': 'Proverbs', 'abbr': 'Pro'},
      {'name': 'Ecclesiastes', 'abbr': 'Ecc'},
      {'name': 'Song of Solomon', 'abbr': 'Son'},
      {'name': 'Isaiah', 'abbr': 'Isa'},
      {'name': 'Jeremiah', 'abbr': 'Jer'},
      {'name': 'Lamentations', 'abbr': 'Lam'},
      {'name': 'Ezekiel', 'abbr': 'Eze'},
      {'name': 'Daniel', 'abbr': 'Dan'},
      {'name': 'Hosea', 'abbr': 'Hos'},
      {'name': 'Joel', 'abbr': 'Joe'},
      {'name': 'Amos', 'abbr': 'Amo'},
      {'name': 'Obadiah', 'abbr': 'Oba'},
      {'name': 'Jonah', 'abbr': 'Jon'},
      {'name': 'Micah', 'abbr': 'Mic'},
      {'name': 'Nahum', 'abbr': 'Nah'},
      {'name': 'Habakkuk', 'abbr': 'Hab'},
      {'name': 'Zephaniah', 'abbr': 'Zep'},
      {'name': 'Haggai', 'abbr': 'Hag'},
      {'name': 'Zechariah', 'abbr': 'Zec'},
      {'name': 'Malachi', 'abbr': 'Mal'},
      {'name': 'Matthew', 'abbr': 'Mat'},
      {'name': 'Mark', 'abbr': 'Mar'},
      {'name': 'Luke', 'abbr': 'Luk'},
      {'name': 'John', 'abbr': 'Joh'},
      {'name': 'Acts', 'abbr': 'Act'},
      {'name': 'Romans', 'abbr': 'Rom'},
      {'name': '1 Corinthians', 'abbr': '1Co'},
      {'name': '2 Corinthians', 'abbr': '2Co'},
      {'name': 'Galatians', 'abbr': 'Gal'},
      {'name': 'Ephesians', 'abbr': 'Eph'},
      {'name': 'Philippians', 'abbr': 'Phi'},
      {'name': 'Colossians', 'abbr': 'Col'},
      {'name': '1 Thessalonians', 'abbr': '1Th'},
      {'name': '2 Thessalonians', 'abbr': '2Th'},
      {'name': '1 Timothy', 'abbr': '1Ti'},
      {'name': '2 Timothy', 'abbr': '2Ti'},
      {'name': 'Titus', 'abbr': 'Tit'},
      {'name': 'Philemon', 'abbr': 'Phm'},
      {'name': 'Hebrews', 'abbr': 'Heb'},
      {'name': 'James', 'abbr': 'Jam'},
      {'name': '1 Peter', 'abbr': '1Pe'},
      {'name': '2 Peter', 'abbr': '2Pe'},
      {'name': '1 John', 'abbr': '1Jo'},
      {'name': '2 John', 'abbr': '2Jo'},
      {'name': '3 John', 'abbr': '3Jo'},
      {'name': 'Jude', 'abbr': 'Jud'},
      {'name': 'Revelation', 'abbr': 'Rev'},
    ];
  }

  Future<Map<String, String>> loadContinuity() async {
    try {
      final String response = await rootBundle.loadString('assets/CONTINUITY.json');
      final List<dynamic> data = json.decode(response);
      Map<String, String> map = {};
      for (var item in data) {
        String word = item['FunctionWord'].toString().toLowerCase();
        String symbol = item['Symbol'].toString();
        map[word] = symbol;
      }
      return map;
    } catch (e) {
      return {};
    }
  }

  Future<Map<String, String>> loadParentheses() async {
    try {
      final String response = await rootBundle.loadString('assets/PARENTHESES.json');
      final List<dynamic> data = json.decode(response);
      Map<String, String> map = {};
      final punctRegex = RegExp(r'[.,;:!?¶]+$');
      for (var item in data) {
        String key = item['AuxVerb'].toString();
        String value = item['Symbol'].toString();
        String cleanKey = key.replaceFirst(punctRegex, '').trim();
        String cleanValue = value.replaceFirst(punctRegex, '').trim();
        if (!map.containsKey(cleanKey)) {
          map[cleanKey] = cleanValue;
        }
      }
      return map;
    } catch (e) {
      return {};
    }
  }
}
