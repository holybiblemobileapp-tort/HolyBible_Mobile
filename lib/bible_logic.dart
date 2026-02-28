import 'bible_model.dart';

enum BibleViewStyle { standard, superscript, mathematics, mathematics2, mathematicsUnconstraint }

class MathPart {
  final String text;
  final bool isRed;
  final bool isItalic;
  MathPart(this.text, {this.isRed = false, this.isItalic = false});
}

class MathWord {
  final BibleWord original;
  final String displayId;
  final List<MathPart> parts;
  final bool hasLeadingSpace;
  MathWord({required this.original, required this.displayId, required this.parts, this.hasLeadingSpace = true});
}

class BibleLogic {
  static final Map<String, List<MathWord>> _mathCache = {};
  static const int _maxCacheSize = 300;
  static Map<String, String>? _normalizedParenthesesMap;
  static List<String>? _sortedKeys;
  static final Map<String, RegExp> _regexCache = {};

  static const Set<String> _nounIndicators = {
    'the', 'a', 'an', 'thy', 'my', 'his', 'her', 'their', 'our', 'your', 'all', 'no', 'this', 'that', 'every', 'those', 'mine'
  };

  static String getReadingLabel(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard: return 'KEY';
      case BibleViewStyle.superscript: return 'ARRAY';
      case BibleViewStyle.mathematics: return 'ARRAY';
      case BibleViewStyle.mathematics2: return 'PROPORTION';
      case BibleViewStyle.mathematicsUnconstraint: return 'JOIN';
    }
  }

  static String getReadingHeader(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard: return 'KEY = BookChapter:Verse:1-WordCount';
      case BibleViewStyle.superscript: return 'ARRAY = BookChapter:Verse';
      case BibleViewStyle.mathematics: return 'ARRAY = BookChapter:Verse:1-WordCount';
      case BibleViewStyle.mathematics2: return 'PROPORTION = BookChapter:Verse:1-WordCount';
      case BibleViewStyle.mathematicsUnconstraint: return 'JOIN = BookChapter:Verse:1-WordCount';
    }
  }

  static String getReadingTooltip(BibleViewStyle style) {
    switch (style) {
      case BibleViewStyle.standard:
      case BibleViewStyle.mathematics:
      case BibleViewStyle.mathematics2:
      case BibleViewStyle.mathematicsUnconstraint:
        return 'HeightDepth:Length:Breadth';
      case BibleViewStyle.superscript:
        return 'HeightDepth:Length';
    }
  }

  static void clearCache() {
    _mathCache.clear();
    _regexCache.clear();
  }

  static void prepareParentheses(Map<String, String>? parenthesesMap) {
    if (parenthesesMap == null || parenthesesMap.isEmpty) return;
    if (_normalizedParenthesesMap != null && _normalizedParenthesesMap!.length == parenthesesMap.length) return;
    
    _normalizedParenthesesMap = parenthesesMap.map((k, v) => MapEntry(k.toLowerCase(), v));
    _sortedKeys = _normalizedParenthesesMap!.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    _regexCache.clear();
  }

  static RegExp _getRegex(String key) {
    final escapedKey = RegExp.escape(key);
    return _regexCache.putIfAbsent(key, () =>
      RegExp(r'(?<=^|\s|\(|\))' + escapedKey + r'(?=\s|$|[.,;:!?¶\)])', caseSensitive: false)
    );
  }

  static String formatMathToText(List<MathWord> words) {
    StringBuffer sb = StringBuffer();
    for (var w in words) {
      if (w.hasLeadingSpace && sb.isNotEmpty) sb.write(' ');
      for (var p in w.parts) {
        sb.write(p.text);
      }
    }
    return sb.toString();
  }

  static String formatLocation(String bookAbbr, int chapter, int verse, int start, int end, [int? totalWords]) {
    if (start == end && start != 0) return '$bookAbbr$chapter:$verse:$start';
    final effectiveEnd = (end == 0 && totalWords != null) ? totalWords : end;
    if (effectiveEnd == 0) return '$bookAbbr$chapter:$verse:$start';
    return '$bookAbbr$chapter:$verse:$start-$effectiveEnd';
  }

  static String formatPhraseFunction(String phrase, String location) {
    return '$phrase($location)';
  }

  static String formatInverseRelation(String phrase, List<String> locations) {
    if (locations.isEmpty) return phrase;
    return '$phrase ↦ {${locations.join(', ')}}';
  }

  static bool isWordSelected(String bookAbbr, int ch, int v, int wordIdx, String selectionString) {
    if (selectionString.isEmpty) return false;
    final parts = selectionString.split(',');
    for (var part in parts) {
      if (part.contains('_')) {
        final range = part.split('_');
        if (range.length == 2) {
          final start = parseLocation(range[0]);
          final end = parseLocation(range[1]);
          if (start != null && end != null) {
            if (_isBetween(bookAbbr, ch, v, wordIdx, start, end)) return true;
          }
        }
      } else {
        final loc = parseLocation(part);
        if (loc != null) {
          if (loc.bookAbbr.toLowerCase() == bookAbbr.toLowerCase() && loc.chapter == ch && loc.verse == v) {
            if (wordIdx >= loc.startWord && (loc.endWord == 0 || wordIdx <= loc.endWord)) return true;
          }
        }
      }
    }
    return false;
  }

  static bool _isBetween(String book, int ch, int v, int word, BibleLocation start, BibleLocation end) {
    int current = _val(book, ch, v, word);
    int sVal = _val(start.bookAbbr, start.chapter, start.verse, start.startWord);
    int eVal = _val(end.bookAbbr, end.chapter, end.verse, end.endWord == 0 ? 999 : end.endWord);
    if (sVal > eVal) { int temp = sVal; sVal = eVal; eVal = temp; }
    return current >= sVal && current <= eVal;
  }

  static int _val(String b, int c, int v, int w) => (c * 1000000) + (v * 1000) + w;

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
    final String cacheKey = '${verse.bookChapterVerse}_${continuityMap.length}_${parenthesesMap?.length}_$style';
    if (_mathCache.containsKey(cacheKey)) return _mathCache[cacheKey]!;
    if (_mathCache.length > _maxCacheSize) _mathCache.remove(_mathCache.keys.first);

    String currentText = verse.text;
    final isPreface = verse.bookAbbreviation == 'Pre';

    if (parenthesesMap != null && parenthesesMap.isNotEmpty) {
      if (_normalizedParenthesesMap == null) prepareParentheses(parenthesesMap);
      bool changed = true; int passes = 0;
      while (changed && passes < 10) { 
        changed = false; passes++;
        for (var key in _sortedKeys!) {
          if (!currentText.toLowerCase().contains(key.toLowerCase())) continue;
          final isOfMapping = key.startsWith('of ');
          if (isOfMapping) {
            final escapedKey = RegExp.escape(key);
            final regex = RegExp(r'\s+' + escapedKey + r'(?=\s|$|[.,;:!?¶\)])', caseSensitive: false);
            if (regex.hasMatch(currentText)) {
              currentText = currentText.replaceAllMapped(regex, (m) { changed = true; return _normalizedParenthesesMap![key]!; });
            }
          } else {
            final regex = _getRegex(key);
            if (regex.hasMatch(currentText)) {
              currentText = currentText.replaceAllMapped(regex, (m) { changed = true; return _normalizedParenthesesMap![key]!; });
            }
          }
        }

        // 1. Nest adjacent parentheses: (A)(B) -> (A(B))
        currentText = currentText.replaceAllMapped(RegExp(r'\(([^)]+)\)\s*\(([^)]+)\)'),
            (m) { changed = true; return '(${m.group(1)}(${m.group(2)}))'; });
        // 2. Nest function call following another: A(B)(C) -> A(B(C))
        currentText = currentText.replaceAllMapped(RegExp(r'(\w+)\(([^)]+)\)\s*\(([^)]+)\)'),
            (m) { changed = true; return '${m.group(1)}(${m.group(2)}(${m.group(3)}))'; });
        // 3. Nest lists/additional arguments: A(B), (C) -> A(B,(C))
        currentText = currentText.replaceAllMapped(RegExp(r'(\w+)\(([^)]+)\)\s*,\s*\(([^)]+)\)'),
            (m) { changed = true; return '${m.group(1)}(${m.group(2)},(${m.group(3)}))'; });

        final detPattern = r'the|a|an|thy|my|his|her|their|our|your|all|no|this|that|every|those|mine';
        final determinerRegex = RegExp('\\((${detPattern})\\)\\s+([^.,;:!?¶\\s]+)', caseSensitive: false);
        if (determinerRegex.hasMatch(currentText)) {
          currentText = currentText.replaceAllMapped(determinerRegex, (m) { changed = true; return '(${m.group(1)} ${m.group(2)})'; });
        }
        final recursiveOfRegex = RegExp(r'\b(\w+)\s+of\s+([^.,;:!?¶\(\)]+?)(?=[.,;:!?¶\(\)]|\s\w+\()', caseSensitive: false);
        if (recursiveOfRegex.hasMatch(currentText)) {
          currentText = currentText.replaceAllMapped(recursiveOfRegex, (m) { changed = true; String base = m.group(1)!; String content = m.group(2)!.trim(); return '$base($content)'; });
        }
      }
      currentText = currentText.replaceAllMapped(RegExp(r'([\w\)])\s+\('), (m) => '${m.group(1) ?? ''}(');
    }

    if (isPreface) currentText = currentText.replaceAll('¶', '').trim();
    List<String> rawParts = currentText.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (rawParts.isEmpty) return [];

    List<MathWord> results = [];
    int funcSeqCount = 0;
    
    for (int i = 0; i < rawParts.length; i++) {
      final raw = rawParts[i];
      final punctMatch = RegExp(r'^(.*?)([.,;:!?¶]+)$').firstMatch(raw);
      final wordText = punctMatch?.group(1) ?? raw;
      String trailingPunct = punctMatch?.group(2) ?? '';
      if (isPreface) trailingPunct = trailingPunct.replaceAll('¶', '');
      
      bool isAfterPunct = false;
      if (i > 0) {
        final prevRaw = rawParts[i-1];
        if (RegExp(r'[.,;:!?¶]$').hasMatch(prevRaw)) isAfterPunct = true;
      }

      final clean = wordText.toLowerCase().trim();
      final baseWordMatch = RegExp(r'^([a-zA-Z]+)').firstMatch(clean);
      final baseWord = baseWordMatch?.group(1) ?? clean;

      bool isNounUsage = false;
      if (i > 0 && (baseWord == 'will' || baseWord == 'might')) {
        final prevWord = rawParts[i-1].toLowerCase().replaceAll(RegExp(r'[.,;:!?¶\(\)]'), '');
        if (_nounIndicators.contains(prevWord)) isNounUsage = true;
      }

      final symbol = isNounUsage ? null : continuityMap[baseWord];
      List<MathPart> parts = [];

      if (style == BibleViewStyle.mathematicsUnconstraint) {
        if (baseWord == 'of' && trailingPunct.isNotEmpty) {
          parts.add(MathPart('()', isRed: true));
        } else if (symbol != null) {
          final rest = wordText.substring(baseWord.length);
          parts.add(MathPart(symbol, isRed: true));
          if (rest.isNotEmpty) _parseWithStyles(rest, parts, true);
        } else {
          if (wordText.contains('(')) { _parseWithStyles(wordText, parts); }
          else { parts.add(MathPart(wordText, isRed: false)); }
        }
      } else if (symbol != null && i != 0 && trailingPunct.isEmpty && !isAfterPunct) {
        bool shouldReplace = true;
        if (style == BibleViewStyle.mathematics2) {
          bool nextIsFunc = false;
          if (i < rawParts.length - 1) {
            final nextRaw = rawParts[i + 1];
            final nextPm = RegExp(r'^(.*?)([.,;:!?¶]+)$').firstMatch(nextRaw);
            final nextWt = nextPm?.group(1) ?? nextRaw;
            final nextTp = nextPm?.group(2) ?? '';
            final nextBase = RegExp(r'^([a-zA-Z]+)').firstMatch(nextWt.toLowerCase().trim())?.group(1) ?? nextWt.toLowerCase().trim();
            nextIsFunc = continuityMap.containsKey(nextBase) && nextTp.isEmpty;
          }
          shouldReplace = (funcSeqCount == 0 && !nextIsFunc) || (funcSeqCount == 1);
        } else {
          shouldReplace = (funcSeqCount == 0);
        }

        if (shouldReplace) {
          final rest = wordText.substring(baseWord.length);
          parts.add(MathPart(symbol, isRed: true));
          if (rest.isNotEmpty) _parseWithStyles(rest, parts, true);
        } else {
          parts.add(MathPart(wordText, isRed: false));
        }
        funcSeqCount++;
      } else {
        if (wordText.contains('(')) { _parseWithStyles(wordText, parts); }
        else { parts.add(MathPart(wordText, isRed: false)); }
        funcSeqCount = 0;
      }

      if (trailingPunct.isNotEmpty) parts.add(MathPart(trailingPunct, isRed: false));
      results.add(MathWord(original: BibleWord(text: raw, isItalic: false, index: i + 1), displayId: (i + 1).toString(), parts: parts, hasLeadingSpace: i > 0));
    }
    _mathCache[cacheKey] = results;
    return results;
  }

  static void _parseWithStyles(String text, List<MathPart> parts, [bool initialAttached = false]) {
    int lastIdx = 0; int depth = 0; bool isFunctionalAttached = initialAttached;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == '(') {
        if (i > lastIdx) parts.add(MathPart(text.substring(lastIdx, i), isRed: depth > 0 && isFunctionalAttached));
        if (depth == 0 && !initialAttached) isFunctionalAttached = i > 0;
        parts.add(MathPart('(', isRed: isFunctionalAttached));
        depth++; lastIdx = i + 1;
      } else if (text[i] == ')') {
        if (i > lastIdx) parts.add(MathPart(text.substring(lastIdx, i), isRed: depth > 0 && isFunctionalAttached));
        parts.add(MathPart(')', isRed: isFunctionalAttached));
        depth--; if (depth == 0 && !initialAttached) isFunctionalAttached = false;
        lastIdx = i + 1;
      }
    }
    if (lastIdx < text.length) parts.add(MathPart(text.substring(lastIdx), isRed: (depth > 0 || initialAttached) && isFunctionalAttached));
  }

  static String getStyledPhrase(BibleVerse verse, List<int> wordIndices, BibleViewStyle style, Map<String, String> cont, Map<String, String> par) {
    if (style == BibleViewStyle.standard || style == BibleViewStyle.superscript) {
      final sorted = List<int>.from(wordIndices)..sort();
      return sorted.map((idx) => verse.styledWords.firstWhere((w) => w.index == idx).text).join(' ');
    }
    final mathWords = applyContinuity(verse, cont, parenthesesMap: par, style: style);
    final sorted = List<int>.from(wordIndices)..sort();
    return sorted.map((idx) {
      final mw = mathWords.firstWhere((mw) => mw.original.index == idx);
      return mw.parts.map((p) => p.text).join('');
    }).join(' ');
  }
}
