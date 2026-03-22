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
  static final RegExp _terminalPunct = RegExp(r'[.!?;:]');

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
      return continuityMap.containsKey(wordLower);
    }

    void closeParenthesis(List<MathPart> targetParts, int count) {
      if (targetParts.isEmpty) {
        targetParts.add(MathPart(')' * count, isRed: true, isParenthesis: true, isOfReplacement: true));
        return;
      }
      String lastText = targetParts.last.text;
      if (_terminalPunct.hasMatch(lastText)) {
        String punct = lastText.replaceAll(RegExp(r'[^.!?;:]'), '');
        String text = lastText.replaceAll(RegExp(r'[.!?;:]'), '');
        targetParts.removeLast();
        if (text.isNotEmpty) targetParts.add(MathPart(text));
        targetParts.add(MathPart(')' * count, isRed: true, isParenthesis: true, isOfReplacement: true));
        if (punct.isNotEmpty) targetParts.add(MathPart(punct));
      } else {
        targetParts.add(MathPart(')' * count, isRed: true, isParenthesis: true, isOfReplacement: true));
      }
    }

    Set<int> processedIndices = {};
    bool hideNextLeadingSpace = false;

    for (int i = 0; i < verse.styledWords.length; i++) {
      if (processedIndices.contains(i)) continue;
      final bw = verse.styledWords[i];
      final String rawText = bw.text.replaceAll('¶', '').trim();
      final String wordLower = rawText.toLowerCase().replaceAll(RegExp(r'[.,;:!?\(\)\[\]]'), '');
      bool currentHasLeadingSpace = i > 0 && !hideNextLeadingSpace;
      hideNextLeadingSpace = false;

      if (parenthesesMap != null) {
        String? parOverride; int overrideLength = 0;
        for (int len = 10; len >= 1; len--) {
          if (i + len > verse.styledWords.length) continue;
          String phrase = verse.styledWords.sublist(i, i + len).map((w) => w.text.toLowerCase().replaceAll(RegExp(r'[.,;:!?\(\)\[\]]'), '')).join(' ');
          if (parenthesesMap.containsKey(phrase)) { parOverride = parenthesesMap[phrase]; overrideLength = len; break; }
        }
        if (parOverride != null) {
          bool suppressSpace = parOverride.startsWith('(') || parOverride.startsWith('[');
          result.add(MathWord(
            original: bw, endIndex: bw.index + overrideLength - 1, displayId: '${verse.id}:${bw.index}',
            parts: [MathPart(parOverride, isRed: true, isParenthesis: true)],
            hasLeadingSpace: currentHasLeadingSpace && !suppressSpace,
          ));
          for (int k = 1; k < overrideLength; k++) {
            result.add(MathWord(original: verse.styledWords[i+k], endIndex: verse.styledWords[i+k].index, displayId: '${verse.id}:${verse.styledWords[i+k].index}', parts: [], hasLeadingSpace: false));
          }
          for (int k = 0; k < overrideLength; k++) processedIndices.add(i + k);
          continue;
        }
      }

      String? symbol = continuityMap[wordLower];
      bool hasPunctuation = rawText.contains(RegExp(r'[.,;:!?]'));
      String punctuation = rawText.replaceAll(RegExp(r'[^.,;:!?]'), '');
      bool isStartOfVerse = i == 0;
      bool isOf = wordLower == 'of';
      bool precededByPunctuation = i > 0 && verse.styledWords[i-1].text.contains(RegExp(r'[.,;:!?]'));
      bool inhibitOf = !isTertiary && (isStartOfVerse || (precededByPunctuation && !isSecondary) || hasPunctuation);
      bool inhibitFunction = !isTertiary && (isStartOfVerse || hasPunctuation || (precededByPunctuation && !isSecondary));

      List<MathPart> parts = [];
      bool suppressThisLeadingSpace = false;

      if (isOf && !inhibitOf) {
        suppressThisLeadingSpace = true; hideNextLeadingSpace = true;
        bool canColour = !isStartOfVerse && !precededByPunctuation;
        if (isTertiary && hasPunctuation) { parts.add(MathPart('()$punctuation', isRed: canColour, isParenthesis: true, isOfReplacement: true)); }
        else { parts.add(MathPart('(', isRed: canColour, isParenthesis: true, isOfReplacement: true)); openOfCount++; }
      } else if (symbol != null && !inhibitFunction) {
        if (openOfCount > 0) {
          if (result.isNotEmpty) { closeParenthesis(result.last.parts, openOfCount); }
          else { parts.insert(0, MathPart(')' * openOfCount, isRed: true, isParenthesis: true, isOfReplacement: true)); }
          openOfCount = 0;
        }
        bool shouldReplace = isTertiary;
        if (!shouldReplace) {
          bool isIsolated = !isFunctionWord(i - 1) && !isFunctionWord(i + 1);
          bool isFirstInSeq = !isFunctionWord(i - 1) && isFunctionWord(i + 1);
          bool isSecondInSeq = isFunctionWord(i - 1) && !isFunctionWord(i - 2);
          if (isSecondary) { shouldReplace = isIsolated || isSecondInSeq; }
          else {
            bool nearPunct = (i > 0 && verse.styledWords[i-1].text.contains(RegExp(r'[.,;:!?]'))) || (i < verse.styledWords.length - 1 && verse.styledWords[i+1].text.contains(RegExp(r'[.,;:!?]')));
            shouldReplace = (isIsolated || isFirstInSeq) && !nearPunct;
          }
        }
        if (shouldReplace) { parts.add(MathPart(symbol + punctuation, isRed: true)); }
        else { parts.add(MathPart(rawText, isItalic: bw.isItalic)); }
      } else {
        String cleanWord = rawText.replaceAll(RegExp(r'[.,;:!?]'), '');
        parts.add(MathPart(cleanWord, isItalic: bw.isItalic, isParenthesis: rawText.contains(RegExp(r'[\(\)]'))));
        if (punctuation.isNotEmpty) parts.add(MathPart(punctuation));
      }

      if (hasPunctuation && openOfCount > 0) {
        closeParenthesis(parts, openOfCount);
        openOfCount = 0;
      }

      result.add(MathWord(
        original: bw, endIndex: bw.index, displayId: '${verse.id}:${bw.index}',
        parts: parts, hasLeadingSpace: currentHasLeadingSpace && !suppressThisLeadingSpace,
      ));
    }
    if (openOfCount > 0 && result.isNotEmpty) { closeParenthesis(result.last.parts, openOfCount); }
    _mathCache[cacheKey] = result;
    return result;
  }

  static String getStyledPhrase(BibleVerse verse, List<int> wordIndices, BibleViewStyle style, Map<String, String> cont, Map<String, String> par) {
    if (wordIndices.isEmpty) return "";
    if (style == BibleViewStyle.standard) { return wordIndices.map((i) => verse.styledWords[i - 1].text.replaceAll('¶', '').trim()).join(' '); }
    if (style == BibleViewStyle.superscript) {
      return wordIndices.map((i) {
        final w = verse.styledWords[i - 1];
        String t = w.text.replaceAll('¶', '').trim();
        final punctuation = t.replaceAll(RegExp(r'[^.,;:!?]'), '');
        final cleanWord = t.replaceAll(RegExp(r'[.,;:!?]'), '');
        return '$cleanWord$i$punctuation';
      }).join(' ');
    }
    final mathWords = applyContinuity(verse, cont, parenthesesMap: par, style: style);
    
    StringBuffer sb = StringBuffer();
    bool isFirst = true;
    Set<int> seenStartIndices = {};
    for (int i in wordIndices) {
      final matches = mathWords.where((mw) => i >= mw.original.index && i <= mw.endIndex);
      if (matches.isNotEmpty) {
        final mw = matches.first;
        if (!seenStartIndices.contains(mw.original.index)) {
          String content = mw.parts.map((p) => p.text).join('');
          if (content.isNotEmpty) {
            if (!isFirst && mw.hasLeadingSpace) sb.write(' ');
            sb.write(content);
            isFirst = false;
          }
          seenStartIndices.add(mw.original.index);
        }
      }
    }
    return sb.toString();
  }
}
