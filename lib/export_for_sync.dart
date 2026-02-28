import 'dart:convert';
import 'dart:io';
import 'bible_model.dart';

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart export_for_sync.dart [BookAbbr] [Chapter]');
    return;
  }

  final targetBook = args[0];
  final targetChapter = int.parse(args[1]);

  final file = File('assets/Bible.json');
  final jsonString = await file.readAsString();
  final List<dynamic> data = json.decode(jsonString);

  final verses = data
      .map((j) => BibleVerse.fromJson(j))
      .where((v) => v.bookAbbreviation == targetBook && v.chapter == targetChapter)
      .toList();

  if (verses.isEmpty) {
    print('No verses found for $targetBook $targetChapter');
    return;
  }

  final outputFile = File('assets/sync/$targetBook${targetChapter}_words.txt');
  final sink = outputFile.openWrite();

  for (var v in verses) {
    for (var w in v.styledWords) {
      // One word per line.
      // TIP: If the audio starts with "Genesis Chapter 1",
      // ensure Verse 0 in your JSON contains those words.
      sink.writeln(w.text);
    }
  }

  await sink.close();
  print('Success! Created word list: ${outputFile.path}');
}
