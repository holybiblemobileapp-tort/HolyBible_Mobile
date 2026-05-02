import 'bible_model.dart';
import 'package:flutter/material.dart';
import 'database_service.dart';

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

  static const List<Color> argumentColors = [
    Colors.black,
    Colors.red,
    Colors.blue,
    const Color(0xFF2E7D32), // Green
    Colors.orange,
    Colors.purple,
    Colors.brown,
    Colors.pink,
    Colors.teal,
    const Color(0xFF808000), // Olive
    const Color(0xFFFF00FF), // Magenta
  ];

  static Color getArgumentColor(int index, bool isDarkMode) {
    if (index == 0) return isDarkMode ? Colors.white : Colors.black;
    return argumentColors[index % argumentColors.length];
  }

  static String getLatexColor(int index) {
    switch (index) {
      case 1: return "red";
      case 2: return "blue";
      case 3: return "green";
      case 4: return "orange";
      case 5: return "purple";
      case 6: return "brown";
      case 7: return "pink";
      case 8: return "teal";
      case 9: return "olive";
      case 10: return "magenta";
      default: return "";
    }
  }

  static const Set<String> _wrappers = {
    'a', 'an', 'the', 'all', 'his', 'her', 'my', 'your', 'our', 'their', 'its', 'thy', 'y', 
    'most', 'those', 'these', 'this', 'that', 'mine', 'thine',
    'low', 'high', 'strong', 'good', 'great', 'little', 'much', 'many',
    'corruptible', 'incorruptible', 'living', 'any', 'every', 'evil', 'sudden', 'wicked', 'own', 'and',
    'strange', 'whorish', 'excellent', 'witty', 'righteous', 'faithful', 'froward', 'perverse', 'understanding',
    'burnt', 'shittim', 'brass', 'silver', 'fine', 'fifty', 'fifteen', 'one', 'side', 'court', 'gate', 'cubits', 'testimony', 'offering', 'it',
    'old', 'testament', 'holy', 'ghost', 'mount', 'seir', 'time', 'only', 'begotten', 'jesus', 'christ'
  };

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
      case BibleViewStyle.standard: return 'AKJV 1611 PCE circa 1900';
      case BibleViewStyle.superscript: return 'Superscript KJV';
      case BibleViewStyle.mathematics: return 'MathKJVP';
      case BibleViewStyle.mathematics2: return 'MathKJVS';
      case BibleViewStyle.mathematicsUnconstraint: return 'MathKJVT';
    }
  }

  static String getStyleHeader(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard: return 'KEY';
      case BibleViewStyle.superscript: return 'ARRAY';
      case BibleViewStyle.mathematics: return 'PROPORTION';
      case BibleViewStyle.mathematics2: return 'BALANCE';
      case BibleViewStyle.mathematicsUnconstraint: return 'JOIN';
    }
  }

  static String getStyleHoverTitle(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.superscript: return 'HeightDepth:Length';
      default: return 'HeightDepth:Length:Breadth';
    }
  }

  static Color getMarginReferenceColor(BibleViewStyle style, bool isDarkMode) {
    if (isDarkMode) return Colors.white70;
    switch (style) {
      case BibleViewStyle.mathematics: return Colors.green;
      case BibleViewStyle.mathematics2: return Colors.blue;
      case BibleViewStyle.mathematicsUnconstraint: return const Color(0xFFFF6347); // Tomato
      default: return Colors.grey;
    }
  }

  static Color getMathSymbolColor(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.mathematics2: return Colors.orange;
      case BibleViewStyle.mathematicsUnconstraint: return const Color(0xFFFFD700); // Gold
      default: return Colors.red;
    }
  }

  static String getBreadthDescription(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard: return 'Breadth';
      case BibleViewStyle.superscript: return 'Breadth = Counting One By One';
      default: return 'Breadth = Tongue of the Mathematicians';
    }
  }

  static void clearCache() { _mathCache.clear(); }

  static String formatLocation(String bookAbbr, int chapter, int verse, int start, int end, {bool isSuperscript = false}) {
    if (isSuperscript) return '$bookAbbr$chapter:$verse';
    if (start == end && start != 0) return '$bookAbbr$chapter:$verse:$start';
    return '$bookAbbr$chapter:$verse:$start-$end';
  }

  static BibleLocation? parseLocation(String loc) {
    String clean = loc.trim();
    if (clean.contains('_')) clean = clean.split('_').first;
    try {
      final regExp = RegExp(r'^(\d?[a-zA-Z]+)(\d+):(\d+)(?::(\d+))?(?:-(\d+))?$', caseSensitive: false);
      final match = regExp.firstMatch(clean.replaceAll(' ', ''));
      if (match != null) {
        int start = match.group(4) != null ? int.parse(match.group(4)!) : 1;
        int end = match.group(5) != null ? int.parse(match.group(5)!) : (match.group(4) != null ? start : 0);
        return BibleLocation(bookAbbr: match.group(1)!, chapter: int.parse(match.group(2)!), verse: int.parse(match.group(3)!), startWord: start, endWord: end);
      }
    } catch (_) {}
    return null;
  }

  static bool isLocationQuery(String q) {
    final trimmed = q.trim().replaceAll(' ', '');
    if (trimmed.isEmpty) return false;
    return RegExp(r'^(\d?[a-zA-Z]+\d+:\d+([:,\-_\d]+)?)(,\d?[a-zA-Z]+\d+:\d+([:,\-_\d]+)?)*$').hasMatch(trimmed);
  }

  static bool _isVerbContext(List<BibleWord> words, int index, String word) {
    if (word != 'will' && word != 'might') return true; 
    if (index > 0) {
      final prev = words[index - 1].text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      const nounMarkers = {'the', 'a', 'an', 'my', 'thy', 'his', 'her', 'our', 'your', 'their', 'all', 'its', 'mine', 'thine'};
      if (nounMarkers.contains(prev)) return false;
    }
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
      if (count <= 0) return;
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

    for (int i = 0; i < verse.styledWords.length; i++) {
      final bw = verse.styledWords[i];
      final String rawText = bw.text.replaceAll('¶', '').trim();
      final String wordLower = rawText.toLowerCase().replaceAll(RegExp(r'[.,;:!?\(\)\[\]]'), '');
      
      String? symbol = continuityMap[wordLower];
      bool isVerb = _isVerbContext(verse.styledWords, i, wordLower);
      bool hasPunctuation = rawText.contains(RegExp(r'[.,;:!?]'));
      String punctuation = rawText.replaceAll(RegExp(r'[^.,;:!?]'), '');
      bool isStartOfVerse = i == 0;
      bool isEndOfVerse = i == verse.styledWords.length - 1;
      bool isOf = wordLower == 'of';
      bool precededByPunctuation = i > 0 && verse.styledWords[i-1].text.contains(RegExp(r'[.,;:!?]'));
      
      bool shouldReplaceFunction = false;
      bool inhibitFunction = false;
      bool inhibitOf = false;

      if (isTertiary) {
        shouldReplaceFunction = true;
      } else if (isSecondary) {
        inhibitOf = isStartOfVerse || isEndOfVerse;
        inhibitFunction = isStartOfVerse || (hasPunctuation && !isOf);
        bool isIsolated = !isFunctionWord(i - 1) && !isFunctionWord(i + 1);
        bool isSecondInSeq = i > 0 && i < verse.styledWords.length && isFunctionWord(i - 1) && !isFunctionWord(i - 2);
        shouldReplaceFunction = isIsolated || isSecondInSeq || precededByPunctuation;
      } else {
        inhibitOf = isStartOfVerse || precededByPunctuation || isEndOfVerse;
        inhibitFunction = isStartOfVerse || hasPunctuation || precededByPunctuation;
        bool isIsolated = !isFunctionWord(i - 1) && !isFunctionWord(i + 1);
        bool isFirstInSeq = !isFunctionWord(i - 1) && i < verse.styledWords.length - 1 && isFunctionWord(i + 1);
        shouldReplaceFunction = isIsolated || isFirstInSeq;
      }

      List<MathPart> parts = [];
      bool currentIsOfBracket = false;

      if (isOf && !inhibitOf) {
        currentIsOfBracket = true;
        if (hasPunctuation || isEndOfVerse) {
          if (isTertiary) {
            parts.add(MathPart('()', isRed: true, isParenthesis: true, isOfReplacement: true));
            if (punctuation.isNotEmpty) parts.add(MathPart(punctuation));
          } else {
            parts.add(MathPart('of'));
            if (punctuation.isNotEmpty) parts.add(MathPart(punctuation));
          }
        } else {
          parts.add(MathPart('(', isRed: true, isParenthesis: true, isOfReplacement: true));
          openOfCount++; 
        }
      } else if (symbol != null && isVerb && !inhibitFunction && shouldReplaceFunction) {
        if (openOfCount > 0) {
          String nextWordText = i < verse.styledWords.length - 1 ? verse.styledWords[i+1].text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') : '';
          bool nextIsOf = nextWordText == 'of';
          bool nextIsAnd = nextWordText == 'and';
          if (!nextIsOf && !nextIsAnd) {
             if (result.isNotEmpty) {
               closeParenthesis(result.last.parts, openOfCount);
             } else {
               parts.insert(0, MathPart(')' * openOfCount, isRed: true, isParenthesis: true, isOfReplacement: true));
             }
             openOfCount = 0;
          }
        }
        parts.add(MathPart(symbol, isRed: true));
        if (punctuation.isNotEmpty) parts.add(MathPart(punctuation));
      } else {
        String cleanWord = rawText.replaceAll(RegExp(r'[.,;:!?]'), '');
        parts.add(MathPart(cleanWord, isItalic: bw.isItalic));
        if (punctuation.isNotEmpty) parts.add(MathPart(punctuation));
        
        if (openOfCount > 0) {
          String nextWordText = i < verse.styledWords.length - 1 ? verse.styledWords[i+1].text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') : '';
          bool nextIsOf = nextWordText == 'of';
          bool nextIsAnd = nextWordText == 'and';
          bool isPossessive = wordLower.endsWith("'s") || wordLower.endsWith("’s");
          
          bool shouldClose = (!(_wrappers.contains(wordLower) || nextIsOf || nextIsAnd || isPossessive)) || isEndOfVerse;
          if (hasPunctuation) shouldClose = true;

          if (shouldClose) {
            closeParenthesis(parts, openOfCount); 
            openOfCount = 0;
          }
        }
      }

      bool isStrongPunct = rawText.contains(RegExp(r'[.!?;:]'));
      if (isStrongPunct && openOfCount > 0) {
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

  static String formatInverseRelation(String query, List<BibleMatch> results) {
    final cleanQuery = query.trim();
    if (isLocationQuery(cleanQuery)) {
      if (results.isEmpty) return "$cleanQuery ↦ NULL";
      final fullPhrase = results.map((m) => m.phrase).join(' ').trim();
      return "$cleanQuery ↦ $fullPhrase($cleanQuery)";
    }
    final String joined = results.map((m) => m.location).join('; ');
    return "$query ↦ { $joined } RecordCount: ${results.length}";
  }

  static List<TextSpan> highlightText(String text, String query, {TextStyle? normalStyle, TextStyle? highlightStyle}) {
    if (query.isEmpty) return [TextSpan(text: text, style: normalStyle)];
    List<TextSpan> spans = []; 
    final lowerText = text.toLowerCase(); 
    final lowerQuery = query.toLowerCase(); 
    int start = 0; 
    int indexOfMatch;
    final hStyle = highlightStyle ?? const TextStyle(fontWeight: FontWeight.bold, backgroundColor: Colors.yellow, color: Colors.black);
    while ((indexOfMatch = lowerText.indexOf(lowerQuery, start)) != -1) {
      if (indexOfMatch > start) spans.add(TextSpan(text: text.substring(start, indexOfMatch), style: normalStyle));
      spans.add(TextSpan(text: text.substring(indexOfMatch, indexOfMatch + query.length), style: hStyle));
      start = indexOfMatch + query.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: normalStyle));
    return spans;
  }
}
