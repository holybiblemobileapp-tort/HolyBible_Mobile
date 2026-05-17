import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_math_fork/flutter_math.dart';
import 'bible_logic.dart';
import 'bible_model.dart';
import 'database_service.dart';

class LatexSyntax extends md.BlockSyntax {
  LatexSyntax();

  @override
  RegExp get pattern => RegExp(r'^(\$\$|\\\[)');

  @override
  md.Node? parse(md.BlockParser parser) {
    final List<String> childLines = [];
    if (parser.isDone) return null;
    
    final String firstLine = parser.current.content;
    final Match? markerMatch = RegExp(r'^(\$\$|\\\[)').firstMatch(firstLine);
    if (markerMatch == null) return null;
    
    final String marker = markerMatch.group(0) ?? r'$$';
    final String endMarker = marker == r'$$' ? r'$$' : r'\]';

    if (firstLine.length > marker.length && firstLine.endsWith(endMarker)) {
      final String content = firstLine.substring(marker.length, firstLine.length - endMarker.length);
      parser.advance();
      return md.Element('p', [md.Element('latex', [md.Text(content)])]);
    }

    parser.advance();
    while (!parser.isDone) {
      final String line = parser.current.content;
      if (line.contains(endMarker)) {
        childLines.add(line.replaceAll(endMarker, ''));
        parser.advance();
        break;
      }
      childLines.add(line);
      parser.advance();
    }
    
    return md.Element('p', [md.Element('latex', [md.Text(childLines.join('\n'))])]);
  }
}

class InlineLatexSyntax extends md.InlineSyntax {
  InlineLatexSyntax() : super(r'(\$|\\\()(.+?)(\$|\\\))');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final String content = match.group(2) ?? '';
    parser.addNode(md.Element('inlineLatex', [md.Text(content)]));
    return true;
  }
}

class PhraseSyntax extends md.InlineSyntax {
  PhraseSyntax() : super(r'Phrase\(([^)]+)\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final String content = match.group(1) ?? '';
    parser.addNode(md.Element('phrase', [md.Text(content)]));
    return true;
  }
}

class ScrollableMath extends StatefulWidget {
  final String text;
  final bool isDarkMode;
  final double fontSize;

  const ScrollableMath({
    super.key,
    required this.text,
    required this.isDarkMode,
    required this.fontSize,
  });

  @override
  State<ScrollableMath> createState() => _ScrollableMathState();
}

class _ScrollableMathState extends State<ScrollableMath> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 6,
        radius: const Radius.circular(3),
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Math.tex(
              widget.text,
              textStyle: TextStyle(
                fontSize: widget.fontSize,
                color: widget.isDarkMode ? Colors.white : Colors.black,
              ),
              onErrorFallback: (err) => SelectableText(
                widget.text,
                style: const TextStyle(color: Colors.red, fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LatexBuilder extends MarkdownElementBuilder {
  final BibleViewStyle currentStyle;
  final Map<String, String> continuityMap;
  final Map<String, String> parenthesesMap;
  final bool isDarkMode;

  LatexBuilder({
    required this.currentStyle,
    required this.continuityMap,
    required this.parenthesesMap,
    required this.isDarkMode,
  });

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return FutureBuilder<String>(
      future: _process(element.textContent, isLatex: true),
      builder: (context, snapshot) {
        if (snapshot.hasError) return SelectableText("LaTeX Error: ${snapshot.error}", style: const TextStyle(color: Colors.red));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(20.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        
        final String text = snapshot.data ?? "";
        if (text.isEmpty) return const SizedBox.shrink();

        return ScrollableMath(
          text: text,
          isDarkMode: isDarkMode,
          fontSize: preferredStyle?.fontSize ?? 18,
        );
      }
    );
  }

  Future<String> _process(String raw, {required bool isLatex}) async {
    try {
      String processed = raw;
      
      final reg = RegExp(r'Phrase\(([^)]+)\)');
      final List<Match> matches = reg.allMatches(processed).toList();
      for (var m in matches.reversed) {
        final String inner = m.group(1) ?? '';
        final String phraseResult = await _fetchPhraseLogic(inner, isLatex: isLatex);
        processed = processed.replaceRange(m.start, m.end, phraseResult);
      }

      if (isLatex) {
        processed = _sanitizeLatex(processed);
      }
      return processed;
    } catch (e) {
      return isLatex ? r"\text{Error}" : "Error";
    }
  }

  String _sanitizeLatex(String input) {
    return input
      .replaceAll('↦', r'\text{↦}')
      .replaceAll('↤', r'\text{↤}')
      .replaceAll('≤', r'\le ')
      .replaceAll('≥', r'\ge ')
      .replaceAll('≡', r'\equiv ')
      .replaceAll('≈', r'\approx ')
      .replaceAll('±', r'\pm ')
      .replaceAll('≠', r'\ne ')
      .replaceAll('∑', r'\sum ')
      .replaceAll('→', r'\to ')
      .replaceAll('∞', r'\infty ')
      .replaceAll('∂', r'\partial ')
      .replaceAll('∆', r'\Delta ')
      .replaceAll('∇', r'\nabla ')
      .replaceAll('∈', r'\in ')
      .replaceAll('∉', r'\notin ')
      .replaceAll('⊂', r'\subset ')
      .replaceAll('⊃', r'\supset ')
      .replaceAll('∪', r'\cup ')
      .replaceAll('∩', r'\cap ')
      .replaceAll('∀', r'\forall ')
      .replaceAll('∃', r'\exists ')
      .replaceAll('∄', r'\nexists ')
      .replaceAll('∅', r'\emptyset ')
      .replaceAll('⇔', r'\Leftrightarrow ');
  }

  Future<String> _fetchPhraseLogic(String content, {required bool isLatex}) async {
    try {
      final List<String> parts = content.split(',').map((s) => s.trim()).toList();
      if (parts.isEmpty) return "";
      
      String option = '1';
      if (parts.length > 1 && RegExp(r'^-?[0123]$').hasMatch(parts.last)) {
        option = parts.removeLast();
      }

      final String locsRaw = parts.join(', ');
      final List<BibleLocation> locList = BibleLogic.parseMultipleLocations(locsRaw);
      if (locList.isEmpty) return isLatex ? r"\text{INVALID\_LOC}" : "INVALID_LOC";
      
      if (option == '3') {
        final escaped = locsRaw.replaceAll('_', r'\_').replaceAll('&', r'\&').replaceAll('\u0024', r'\$');
        return isLatex ? "\\text{$escaped}" : locsRaw;
      }

      BibleViewStyle styleToUse = currentStyle;
      if (option == '-2' || option == '0') styleToUse = BibleViewStyle.standard;
      if (option == '-1') styleToUse = BibleViewStyle.superscript;

      final db = DatabaseService();
      final StringBuffer sb = StringBuffer();

      for (var loc in locList) {
        final verse = await db.getSpecificVerseByAbbr(loc.bookAbbr, loc.chapter, loc.verse);
        if (verse != null) {
          final int wordCount = verse.wordCount;
          if (wordCount == 0) continue;
          int end = (loc.endWord <= 0 || loc.endWord > wordCount) ? wordCount : loc.endWord;
          int start = loc.startWord.clamp(1, end);
          final List<int> idxs = List.generate(end - start + 1, (j) => start + j);
          
          if (option == '0') {
            for (int idx in idxs) {
              final String p = isLatex 
                ? BibleLogic.getLatexStyledPhrase(verse, [idx], styleToUse, continuityMap, parenthesesMap)
                : BibleLogic.getStyledPhrase(verse, [idx], styleToUse, continuityMap, parenthesesMap);
              
              final String wordLoc = "${loc.bookAbbr}${loc.chapter}:${loc.verse}:$idx";
              
              if (isLatex) {
                if (sb.isNotEmpty) sb.write(r"\ ");
                final escapedWordLoc = wordLoc.replaceAll('_', r'\_').replaceAll('&', r'\&').replaceAll('\u0024', r'\$');
                sb.write("${p}\\text{($escapedWordLoc)}");
              } else {
                if (sb.isNotEmpty) sb.write(" ");
                sb.write("${p}($wordLoc)");
              }
            }
          } else {
            final String p = isLatex 
              ? BibleLogic.getLatexStyledPhrase(verse, idxs, styleToUse, continuityMap, parenthesesMap)
              : BibleLogic.getStyledPhrase(verse, idxs, styleToUse, continuityMap, parenthesesMap);
            
            if (sb.isNotEmpty) {
               if (isLatex) sb.write(r"\ "); else sb.write(" ");
            }
            sb.write(p);
          }
        }
      }

      String result = sb.toString();
      if (isLatex) {
         result = result
            .replaceAll(RegExp(r'(?<!\\)_'), r'\_')
            .replaceAll(RegExp(r'(?<!\\)\$'), r'\$')
            .replaceAll(RegExp(r'(?<!\\)%'), r'\%')
            .replaceAll(RegExp(r'(?<!\\)&'), r'\&');
      }
      
      if (option == '2') {
         final escapedLocs = locsRaw.replaceAll('_', r'\_').replaceAll('&', r'\&').replaceAll('\u0024', r'\$');
         result = isLatex ? "${result}\\text{($escapedLocs)}" : "${result}($locsRaw)";
      }
      return result;
    } catch (e) {
      return isLatex ? r"\text{Error}" : "Error";
    }
  }
}

class InlineLatexBuilder extends MarkdownElementBuilder {
  final BibleViewStyle currentStyle;
  final Map<String, String> continuityMap;
  final Map<String, String> parenthesesMap;
  final bool isDarkMode;

  InlineLatexBuilder({
    required this.currentStyle,
    required this.continuityMap,
    required this.parenthesesMap,
    required this.isDarkMode,
  });

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return FutureBuilder<String>(
      future: _process(element.textContent, isLatex: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
           return const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1));
        }
        final String text = snapshot.data ?? "";
        if (text.isEmpty) return const SizedBox.shrink();

        return Math.tex(
          text,
          textStyle: TextStyle(
            fontSize: 16,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
          onErrorFallback: (err) => Text(text, style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87, fontSize: 10, fontFamily: 'monospace')),
        );
      }
    );
  }

  Future<String> _process(String raw, {required bool isLatex}) async {
    try {
      String processed = raw;
      final reg = RegExp(r'Phrase\(([^)]+)\)');
      final List<Match> matches = reg.allMatches(processed).toList();
      for (var m in matches.reversed) {
        final String inner = m.group(1) ?? '';
        final String phraseResult = await _fetchPhraseLogic(inner, isLatex: isLatex);
        processed = processed.replaceRange(m.start, m.end, phraseResult);
      }
      if (isLatex) {
        processed = _sanitizeLatex(processed);
      }
      return processed;
    } catch (_) { return raw; }
  }

  String _sanitizeLatex(String input) {
    return input
      .replaceAll('↦', r'\text{↦}')
      .replaceAll('↤', r'\text{↤}')
      .replaceAll('≤', r'\le ')
      .replaceAll('≥', r'\ge ')
      .replaceAll('≡', r'\equiv ')
      .replaceAll('≈', r'\approx ')
      .replaceAll('±', r'\pm ')
      .replaceAll('≠', r'\ne ')
      .replaceAll('∑', r'\sum ')
      .replaceAll('→', r'\to ')
      .replaceAll('∞', r'\infty ')
      .replaceAll('∂', r'\partial ')
      .replaceAll('∆', r'\Delta ')
      .replaceAll('∇', r'\nabla ')
      .replaceAll('∈', r'\in ')
      .replaceAll('∉', r'\notin ')
      .replaceAll('⊂', r'\subset ')
      .replaceAll('⊃', r'\supset ')
      .replaceAll('∪', r'\cup ')
      .replaceAll('∩', r'\cap ')
      .replaceAll('∀', r'\forall ')
      .replaceAll('∃', r'\exists ')
      .replaceAll('∄', r'\nexists ')
      .replaceAll('∅', r'\emptyset ')
      .replaceAll('⇔', r'\Leftrightarrow ');
  }

  Future<String> _fetchPhraseLogic(String content, {required bool isLatex}) async {
    try {
      final List<String> parts = content.split(',').map((s) => s.trim()).toList();
      if (parts.isEmpty) return "";
      String option = '1';
      if (parts.length > 1 && RegExp(r'^-?[0123]$').hasMatch(parts.last)) option = parts.removeLast();

      final String locsRaw = parts.join(', ');
      final List<BibleLocation> locList = BibleLogic.parseMultipleLocations(locsRaw);
      if (locList.isEmpty) return isLatex ? r"\text{INVALID\_LOC}" : "INVALID_LOC";
      
      if (option == '3') {
        final escaped = locsRaw.replaceAll('_', r'\_').replaceAll('&', r'\&').replaceAll('\u0024', r'\$');
        return isLatex ? "\\text{$escaped}" : locsRaw;
      }

      BibleViewStyle styleToUse = currentStyle;
      if (option == '-2' || option == '0') styleToUse = BibleViewStyle.standard;
      if (option == '-1') styleToUse = BibleViewStyle.superscript;

      final db = DatabaseService();
      final StringBuffer sb = StringBuffer();
      for (var loc in locList) {
        final verse = await db.getSpecificVerseByAbbr(loc.bookAbbr, loc.chapter, loc.verse);
        if (verse != null) {
          final int wordCount = verse.wordCount;
          if (wordCount == 0) continue;
          int end = (loc.endWord <= 0 || loc.endWord > wordCount) ? wordCount : loc.endWord;
          int start = loc.startWord.clamp(1, end);
          final List<int> idxs = List.generate(end - start + 1, (j) => start + j);
          
          if (option == '0') {
            for (int idx in idxs) {
              final String p = isLatex 
                ? BibleLogic.getLatexStyledPhrase(verse, [idx], styleToUse, continuityMap, parenthesesMap)
                : BibleLogic.getStyledPhrase(verse, [idx], styleToUse, continuityMap, parenthesesMap);
              
              final String wordLoc = "${loc.bookAbbr}${loc.chapter}:${loc.verse}:$idx";
              
              if (isLatex) {
                if (sb.isNotEmpty) sb.write(r"\ ");
                final escapedWordLoc = wordLoc.replaceAll('_', r'\_').replaceAll('&', r'\&').replaceAll('\u0024', r'\$');
                sb.write("${p}\\text{($escapedWordLoc)}");
              } else {
                if (sb.isNotEmpty) sb.write(" ");
                sb.write("${p}($wordLoc)");
              }
            }
          } else {
            final String p = isLatex 
              ? BibleLogic.getLatexStyledPhrase(verse, idxs, styleToUse, continuityMap, parenthesesMap)
              : BibleLogic.getStyledPhrase(verse, idxs, styleToUse, continuityMap, parenthesesMap);
            
            if (sb.isNotEmpty) {
              if (isLatex) sb.write(r"\ "); else sb.write(" ");
            }
            sb.write(p);
          }
        }
      }
      String result = sb.toString();
      if (isLatex) {
         result = result
            .replaceAll(RegExp(r'(?<!\\)_'), r'\_')
            .replaceAll(RegExp(r'(?<!\\)\$'), r'\$')
            .replaceAll(RegExp(r'(?<!\\)%'), r'\%')
            .replaceAll(RegExp(r'(?<!\\)&'), r'\&');
      }
      if (option == '2') {
        final escapedLocs = locsRaw.replaceAll('_', r'\_').replaceAll('&', r'\&').replaceAll('\u0024', r'\$');
        result = isLatex ? "${result}\\text{(${escapedLocs})}" : "${result}(${locsRaw})";
      }
      return result;
    } catch (_) { return "!"; }
  }
}

class PhraseBuilder extends MarkdownElementBuilder {
  final BibleViewStyle currentStyle;
  final Map<String, String> continuityMap;
  final Map<String, String> parenthesesMap;
  final bool isDarkMode;

  PhraseBuilder({
    required this.currentStyle,
    required this.continuityMap,
    required this.parenthesesMap,
    required this.isDarkMode,
  });

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final content = element.textContent;
    return FutureBuilder<String>(
      future: _fetchPhrase(content),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text("!", style: const TextStyle(color: Colors.red));
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1));
        return Text(snapshot.data ?? '', style: preferredStyle ?? const TextStyle());
      },
    );
  }

  Future<String> _fetchPhrase(String content) async {
    try {
      final List<String> parts = content.split(',').map((s) => s.trim()).toList();
      if (parts.isEmpty) return "";
      String option = '1';
      if (parts.length > 1 && RegExp(r'^-?[0123]$').hasMatch(parts.last)) option = parts.removeLast();

      final String locsRaw = parts.join(', ');
      final List<BibleLocation> locList = BibleLogic.parseMultipleLocations(locsRaw);
      if (locList.isEmpty) return "INVALID_LOC: $content";
      
      if (option == '3') return locsRaw;

      BibleViewStyle styleToUse = currentStyle;
      if (option == '-2' || option == '0') styleToUse = BibleViewStyle.standard;
      if (option == '-1') styleToUse = BibleViewStyle.superscript;

      final db = DatabaseService();
      final StringBuffer sb = StringBuffer();
      for (var loc in locList) {
        final verse = await db.getSpecificVerseByAbbr(loc.bookAbbr, loc.chapter, loc.verse);
        if (verse != null) {
          final int wordCount = verse.wordCount;
          if (wordCount == 0) continue;
          int end = (loc.endWord <= 0 || loc.endWord > wordCount) ? wordCount : loc.endWord;
          int start = loc.startWord.clamp(1, end);
          final List<int> idxs = List.generate(end - start + 1, (j) => start + j);
          
          if (option == '0') {
            for (int idx in idxs) {
              final String p = BibleLogic.getStyledPhrase(verse, [idx], styleToUse, continuityMap, parenthesesMap);
              if (sb.isNotEmpty) sb.write(" ");
              sb.write("$p(${loc.bookAbbr}${loc.chapter}:${loc.verse}:$idx)");
            }
          } else {
            final String p = BibleLogic.getStyledPhrase(verse, idxs, styleToUse, continuityMap, parenthesesMap);
            if (sb.isNotEmpty) sb.write(" ");
            sb.write(p);
          }
        }
      }
      String result = sb.toString();
      if (option == '2') result = "$result($locsRaw)";
      return result;
    } catch (e) { return "[ERR]"; }
  }
}
