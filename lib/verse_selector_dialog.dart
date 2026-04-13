import 'package:flutter/material.dart';
import 'database_service.dart';

class VerseSelectorDialog extends StatefulWidget {
  const VerseSelectorDialog({super.key});
  @override
  State<VerseSelectorDialog> createState() => _VerseSelectorDialogState();
}

class _VerseSelectorDialogState extends State<VerseSelectorDialog> {
  final DatabaseService _dbService = DatabaseService();
  String? _selectedBook;
  int? _selectedChapter;
  int? _selectedVerse;
  List<String> _books = [];
  List<int> _chapters = [];
  List<int> _verses = [];

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  void _loadBooks() async {
    final books = await _dbService.getBooks();
    setState(() => _books = books);
  }

  void _loadChapters(String book) async {
    final chapters = await _dbService.getChapters(book);
    setState(() { _chapters = chapters; _selectedChapter = null; _verses = []; _selectedVerse = null; });
  }

  void _loadVerses(String book, int chapter) async {
    final verses = await _dbService.getVerseNumbers(book, chapter);
    setState(() { _verses = verses; _selectedVerse = null; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Change Verse"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButton<String>(
            hint: const Text("Select Book"),
            value: _selectedBook,
            isExpanded: true,
            items: _books.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (v) { if (v != null) { setState(() => _selectedBook = v); _loadChapters(v); } },
          ),
          DropdownButton<int>(
            hint: const Text("Select Chapter"),
            value: _selectedChapter,
            isExpanded: true,
            items: _chapters.map((c) => DropdownMenuItem(value: c, child: Text(c.toString()))).toList(),
            onChanged: (v) { if (v != null) { setState(() => _selectedChapter = v); _loadVerses(_selectedBook!, v); } },
          ),
          DropdownButton<int>(
            hint: const Text("Select Verse"),
            value: _selectedVerse,
            isExpanded: true,
            items: _verses.map((v) => DropdownMenuItem(value: v, child: Text(v.toString()))).toList(),
            onChanged: (v) => setState(() => _selectedVerse = v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: (_selectedBook != null && _selectedChapter != null && _selectedVerse != null)
              ? () => Navigator.pop(context, {'book': _selectedBook, 'chapter': _selectedChapter, 'verse': _selectedVerse})
              : null,
          child: const Text("Compare"),
        ),
      ],
    );
  }
}
