import 'package:flutter/material.dart';
import 'database_service.dart';
import 'download_service.dart';
import 'bible_service.dart';

class StudyHubView extends StatefulWidget {
  final Function(String) onJumpToLocation;
  const StudyHubView({super.key, required this.onJumpToLocation});

  @override
  State<StudyHubView> createState() => _StudyHubViewState();
}

class _StudyHubViewState extends State<StudyHubView> {
  final DatabaseService _dbService = DatabaseService();
  final DownloadService _downloadService = DownloadService();
  final BibleService _bibleService = BibleService();

  final Map<String, double> _downloadProgress = {};

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.library_books), text: "Audio Books"),
              Tab(icon: Icon(Icons.note), text: "Study Notes"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildBooksList(),
                _buildNotesList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBooksList() {
    final List<Map<String, String>> books = _bibleService.getBooks(); 
    
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final String bookName = book['name'] ?? 'Unknown';
        final String bookAbbr = book['abbr'] ?? '';
        
        final key = '${bookAbbr}1';

        return FutureBuilder<bool>(
          future: _downloadService.isBookDownloaded(bookAbbr, 1),
          builder: (context, snapshot) {
            final isDownloaded = snapshot.data ?? false;
            final progress = _downloadProgress[key];

            return ListTile(
              leading: Icon(
                isDownloaded ? Icons.check_circle : Icons.cloud_download,
                color: isDownloaded ? Colors.green : Colors.grey,
              ),
              title: Text(bookName),
              subtitle: progress != null && progress < 1.0
                  ? LinearProgressIndicator(value: progress)
                  : Text(isDownloaded ? "Downloaded" : "Available for Download"),
              trailing: isDownloaded
                  ? IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => widget.onJumpToLocation("${bookAbbr}1:1"),
                    )
                  : IconButton(
                      icon: const Icon(Icons.download),
                      onPressed: progress != null 
                        ? null 
                        : () => _handleDownload(bookAbbr, 1),
                    ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleDownload(String abbr, int ch) async {
    final key = '$abbr$ch';
    setState(() {
      _downloadProgress[key] = 0.1;
    });

    try {
      await _downloadService.downloadBook(
        abbr, 
        ch, 
        onProgress: (p) => setState(() => _downloadProgress[key] = p),
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Successfully downloaded $abbr Chapter $ch")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error downloading $abbr: $e")),
      );
    } finally {
      setState(() {
        _downloadProgress.remove(key);
      });
    }
  }

  Widget _buildNotesList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dbService.getNotes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final notes = snapshot.data!;
        if (notes.isEmpty) return const Center(child: Text('Dictionary Vector Space Construction...'));
        return ListView.builder(
          itemCount: notes.length,
          itemBuilder: (c, i) => ListTile(
            title: Text(notes[i]['title']?.toString() ?? ''),
            subtitle: Text(notes[i]['location']?.toString() ?? ''),
            onTap: () => widget.onJumpToLocation(notes[i]['location']?.toString() ?? ''),
          ),
        );
      },
    );
  }
}
