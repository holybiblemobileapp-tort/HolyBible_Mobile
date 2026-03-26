import 'bible_model.dart';

enum BibleViewStyle { standard, superscript, mathematics, mathematics2, mathematicsUnconstraint }

class MathPart {
  final String text;
  final bool isRed;
  final bool isItalic;
  final bool isParenthesis;
  final bool isOfReplacement;

  MathPart(this.text, {
    this.isRed = false, 
    this.isItalic = false, 
    this.isParenthesis = false,
    this.isOfReplacement = false,
  });
}

class MathWord {
  final BibleWord original;
  final int endIndex;
  final String displayId;
  final List<MathPart> parts;
  final bool hasLeadingSpace;
  MathWord({required this.original, required this.endIndex, required this.displayId, required this.parts, this.hasLeadingSpace = true});
}

class BibleLogic {
  static final Map<String, List<MathWord>> _mathCache = {};
  static const int _maxCacheSize = 300;
  
  static final RegExp _terminalPunct = RegExp(r'[.,!?;:¶]');

  static const Map<String, int> _bookOrderMap = {
    'Pre': 0, 'Gen': 1, 'Exo': 2, 'Lev': 3, 'Num': 4, 'Deu': 5, 'Jos': 6, 'Jud': 7, 'Rut': 8, '1Sa': 9, '2Sa': 10, '1Ki': 11, '2Ki': 12, '1Ch': 13, '2Ch': 14, 'Ezr': 15, 'Neh': 16, 'Est': 17, 'Job': 18, 'Psa': 19, 'Pro': 20, 'Ecc': 21, 'Son': 22, 'Isa': 23, 'Jer': 24, 'Lam': 25, 'Eze': 26, 'Dan': 27, 'Hos': 28, 'Joe': 29, 'Amo': 30, 'Oba': 31, 'Jon': 32, 'Mic': 33, 'Nah': 34, 'Hab': 35, 'Zep': 36, 'Hag': 37, 'Zec': 38, 'Mal': 39, 'Mat': 40, 'Mar': 41, 'Luk': 42, 'Joh': 43, 'Act': 44, 'Rom': 45, '1Co': 46, '2Co': 47, 'Gal': 48, 'Eph': 49, 'Phi': 50, 'Col': 51, '1Th': 52, '2Th': 53, '1Ti': 54, '2Ti': 55, 'Tit': 56, 'Heb': 58, 'Jam': 59, '1Pe': 60, '2Pe': 61, '1Jo': 62, '2Jo': 63, '3Jo': 64, 'Rev': 66
  };

  static int getBookOrder(String location) {
    final loc = parseLocation(location);
    if (loc == null) return 999;
    String abbr = loc.bookAbbr;
    if (abbr == 'Phi' && loc.chapter == 0) return 57;
    if (abbr == 'Jud' && loc.chapter == 0) return 65;
    return _bookOrderMap[abbr] ?? 999;
  }

  static String getReadingLabel(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard: return 'AKJV 1611 PCE';
      case BibleViewStyle.superscript: return 'ARRAY';
      case BibleViewStyle.mathematics: return 'MathKJVP';
      case BibleViewStyle.mathematics2: return 'MathKJVS';
      case BibleViewStyle.mathematicsUnconstraint: return 'MathKJVT';
    }
  }

  static void clearCache() { _mathCache.clear(); }

  static String formatLocation(String bookAbbr, int chapter, int verse, int start, int end, [int? totalWords]) {
    final effectiveEnd = (end == 0 && totalWords != null) ? totalWords : end;
    if (start == effectiveEnd && start != 0) return '$bookAbbr$chapter:$verse:$start';
    if (effectiveEnd == 0) return '$bookAbbr$chapter:$verse:$start';
    return '$bookAbbr$chapter:$verse:$start-$effectiveEnd';
  }

  static String formatPhraseFunction(String phrase, String location) => '$phrase($location)';

  static BibleLocation? parseLocation(String loc) {
    try {
      final regExp = RegExp(r'^(\d?[a-zA-Z]+)(\d+):(\d+)(?::(\d+))?(?:-(\d+))?$', caseSensitive: false);
      final match = regExp.firstMatch(loc.trim().replaceAll(' ', ''));
      if (match != null) {
        int start = match.group(4) != null ? int.parse(match.group(4)!) : 1;
        int end = match.group(5) != null ? int.parse(match.group(5)!) : (match.group(4) != null ? start : 0);
        return BibleLocation(bookAbbr: match.group(1)!, chapter: int.parse(match.group(2)!), verse: int.parse(match.group(3)!), startWord: start, endWord: end);
      }
    } catch (_) {}
    return null;
  }

  static bool _isVerbContext(List<BibleWord> words, int index, String word) {
    if (word != 'will' && word != 'might') return true; // Other words are handled normally
    
    if (index > 0) {
      final prev = words[index - 1].text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      // If preceded by an article or possessive, it's a NOUN
      const nounMarkers = {'the', 'a', 'an', 'my', 'thy', 'his', 'her', 'our', 'your', 'their'};
      if (nounMarkers.contains(prev)) return false;
    }
    
    // In PCE, "will" as a verb is usually followed by another word (not terminal)
    // "thy will be done" -> "will" is preceded by "thy" (Noun marker) -> Correctly skipped.
    return true;
  }

  static List<MathWord> applyContinuity(BibleVerse verse, Map<String, String> continuityMap, {Map<String, String>? parenthesesMap, BibleViewStyle style = BibleViewStyle.mathematics}) {
    final cacheKey = '${verse.id}_${style.name}';
    if (_mathCache.containsKey(cacheKey)) return _mathCache[cacheKey]!;

    if (style == BibleViewStyle.standard || style == BibleViewStyle.superscript) {
      final res = verse.styledWords.map((w) {
        String cleanText = w.text.replaceAll('¶', '').trim();
        return MathWord(
          original: w, endIndex: w.index, displayId: '${verse.id}:${w.index}',
          parts: [MathPart(cleanText, isItalic: w.isItalic)],
          hasLeadingSpace: w.index > 1,
        );
      }).toList();
      _mathCache[cacheKey] = res;
      return res;
    }

    List<MathWord> result = [];
    final bool isTertiary = style == BibleViewStyle.mathematicsUnconstraint;
    final bool isSecondary = style == BibleViewStyle.mathematics2;
    int openOfCount = 0;
    final RegExp punctRegex = RegExp(r'[.,;:!?¶\(\)\[\]]');

    bool isFunctionWord(int index) {
      if (index < 0 || index >= verse.styledWords.length) return false;
      final w = verse.styledWords[index];
      final wordLower = w.text.toLowerCase().replaceAll(punctRegex, '');
      return continuityMap.containsKey(wordLower) && _isVerbContext(verse.styledWords, index, wordLower);
    }

    void closeParenthesis(List<MathPart> targetParts, int count) {
      if (targetParts.isEmpty) {
        targetParts.add(MathPart(')' * count, isRed: true, isParenthesis: true, isOfReplacement: true));
        return;
      }
      String lastText = targetParts.last.text;
      if (_terminalPunct.hasMatch(lastText)) {
        String punct = "";
        String text = lastText;
        while (text.isNotEmpty && _terminalPunct.hasMatch(text.substring(text.length - 1))) {
          punct = text.substring(text.length - 1) + punct;
          text = text.substring(0, text.length - 1);
        }
        targetParts.removeLast();
        if (text.isNotEmpty) targetParts.add(MathPart(text));
        targetParts.add(MathPart(')' * count, isRed: true, isParenthesis: true, isOfReplacement: true));
        if (punct.isNotEmpty) targetParts.add(MathPart(punct));
      } else {
        targetParts.add(MathPart(')' * count, isRed: true, isParenthesis: true, isOfReplacement: true));
      }
    }

    Set<int> processedIndices = {};
    for (int i = 0; i < verse.styledWords.length; i++) {
      if (processedIndices.contains(i)) continue;
      final bw = verse.styledWords[i];
      final String rawText = bw.text.replaceAll('¶', '').trim();
      final String wordLower = rawText.toLowerCase().replaceAll(RegExp(r'[.,;:!?\(\)\[\]]'), '');
      
      // 1. PARENTHESES.json multi-word overrides
      if (parenthesesMap != null) {
        String? parOverride; int overrideLength = 0;
        for (int len = 10; len >= 1; len--) {
          if (i + len > verse.styledWords.length) continue;
          String phrase = verse.styledWords.sublist(i, i + len).map((w) => w.text.toLowerCase().replaceAll(RegExp(r'[.,;:!?\(\)\[\]]'), '')).join(' ');
          if (parenthesesMap.containsKey(phrase)) { parOverride = parenthesesMap[phrase]; overrideLength = len; break; }
        }
        if (parOverride != null) {
          String lastRaw = verse.styledWords[i + overrideLength - 1].text;
          String punctuation = lastRaw.replaceAll(RegExp(r'[^.,;:!?]'), '');
          String cleanOverride = parOverride.replaceAll(RegExp(r'[.,;:!?]$'), '');
          bool startsWithBracket = cleanOverride.startsWith('(') || cleanOverride.startsWith('[');
          result.add(MathWord(
            original: bw, endIndex: bw.index + overrideLength - 1, displayId: '${verse.id}:${bw.index}',
            parts: [ MathPart(cleanOverride, isRed: true, isParenthesis: true), if (punctuation.isNotEmpty) MathPart(punctuation) ],
            hasLeadingSpace: i > 0 && !startsWithBracket,
          ));
          for (int k = 0; k < overrideLength; k++) processedIndices.add(i + k);
          continue;
        }
      }

      // 2. Automated Continuity Logic
      String? symbol = continuityMap[wordLower];
      bool isVerb = _isVerbContext(verse.styledWords, i, wordLower);
      
      bool hasPunctuation = rawText.contains(RegExp(r'[.,;:!?]'));
      String punctuation = rawText.replaceAll(RegExp(r'[^.,;:!?]'), '');
      bool isStartOfVerse = i == 0;
      bool isOf = wordLower == 'of';
      bool precededByPunctuation = i > 0 && verse.styledWords[i-1].text.contains(RegExp(r'[.,;:!?]'));
      
      bool inhibitOf = false;
      bool inhibitFunction = false;
      bool shouldReplaceFunction = false;

      if (isTertiary) {
        inhibitOf = false;
        inhibitFunction = false;
        shouldReplaceFunction = true;
      } else if (isSecondary) {
        inhibitOf = isStartOfVerse || (i == verse.styledWords.length - 1);
        inhibitFunction = isStartOfVerse || (hasPunctuation && !isOf);
        bool isIsolated = !isFunctionWord(i - 1) && !isFunctionWord(i + 1);
        bool isSecondInSeq = i > 0 && isFunctionWord(i - 1) && !isFunctionWord(i - 2);
        shouldReplaceFunction = isIsolated || isSecondInSeq || precededByPunctuation;
      } else {
        // MathKJVP
        inhibitOf = isStartOfVerse || precededByPunctuation || (i == verse.styledWords.length - 1);
        inhibitFunction = isStartOfVerse || hasPunctuation || precededByPunctuation;
        bool isIsolated = !isFunctionWord(i - 1) && !isFunctionWord(i + 1);
        bool isFirstInSeq = !isFunctionWord(i - 1) && isFunctionWord(i + 1);
        shouldReplaceFunction = isIsolated || isFirstInSeq;
      }

      List<MathPart> parts = [];
      bool currentIsOfBracket = false;

      if (isOf && !inhibitOf) {
        currentIsOfBracket = true;
        if (isTertiary && hasPunctuation) {
          parts.add(MathPart('()', isRed: true, isParenthesis: true, isOfReplacement: true));
          parts.add(MathPart(punctuation));
        } else {
          parts.add(MathPart('(', isRed: true, isParenthesis: true, isOfReplacement: true));
          openOfCount++;
        }
      } else if (symbol != null && isVerb && !inhibitFunction && shouldReplaceFunction) {
        if (openOfCount > 0) {
          if (result.isNotEmpty) { closeParenthesis(result.last.parts, openOfCount); }
          else { parts.insert(0, MathPart(')' * openOfCount, isRed: true, isParenthesis: true, isOfReplacement: true)); }
          openOfCount = 0;
        }
        parts.add(MathPart(symbol, isRed: true));
        if (punctuation.isNotEmpty) parts.add(MathPart(punctuation));
      } else {
        String cleanWord = rawText.replaceAll(RegExp(r'[.,;:!?]'), '');
        parts.add(MathPart(cleanWord, isItalic: bw.isItalic));
        if (punctuation.isNotEmpty) parts.add(MathPart(punctuation));
      }

      bool isStrongPunct = rawText.contains(RegExp(r'[.!?;:]'));
      if ((isStrongPunct || (hasPunctuation && isSecondary)) && openOfCount > 0) {
        closeParenthesis(parts, openOfCount);
        openOfCount = 0;
      }

      bool prevWasOfBracket = i > 0 && result.isNotEmpty && result.last.parts.any((p) => p.text == '(');
      bool shouldHaveSpace = i > 0 && !currentIsOfBracket && !prevWasOfBracket;

      result.add(MathWord(
        original: bw, endIndex: bw.index, displayId: '${verse.id}:${bw.index}',
        parts: parts, hasLeadingSpace: shouldHaveSpace,
      ));
    }

    if (openOfCount > 0 && result.isNotEmpty) {
      closeParenthesis(result.last.parts, openOfCount);
    }

    _mathCache[cacheKey] = result;
    return result;
  }

  static String getStyledPhrase(BibleVerse verse, List<int> wordIndices, BibleViewStyle style, Map<String, String> cont, Map<String, String> par) {
    if (wordIndices.isEmpty) return "";
    if (style == BibleViewStyle.standard) { return wordIndices.map((i) => verse.styledWords[i - 1].text.replaceAll('¶', '').trim()).join(' '); }
    final mathWords = applyContinuity(verse, cont, parenthesesMap: par, style: style);
    StringBuffer sb = StringBuffer();
    bool isFirst = true;
    for (int i in wordIndices) {
      try {
        final mw = mathWords.firstWhere((mw) => mw.original.index == i);
        String content = mw.parts.map((p) => p.text).join('');
        if (content.isNotEmpty) {
          if (!isFirst && mw.hasLeadingSpace) sb.write(' ');
          sb.write(content);
          isFirst = false;
        }
      } catch (_) {}
    }
    return sb.toString();
  }
}
