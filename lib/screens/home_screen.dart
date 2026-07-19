import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/book_document.dart';
import '../models/narration_preset.dart';
import '../services/document_importer.dart';
import '../services/library_repository.dart';
import '../services/shared_import_service.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.repository, super.key});
  final LibraryRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DocumentImporter _importer = DocumentImporter();
  StreamSubscription<SharedDocument>? _sharedSubscription;
  bool _importing = false;
  String _importStatus = '';

  @override
  void initState() {
    super.initState();
    _sharedSubscription = SharedImportService.instance.documents.listen(
      _importSharedDocument,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pending = await SharedImportService.instance.initialize();
        if (pending != null) await _importSharedDocument(pending);
      } on Object {
        // The native import channel is Android-only; the file picker still works.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.repository.books;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_rounded, color: AppColors.gold),
            SizedBox(width: 10),
            Text('Lectura'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Setări',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _importDocument,
        icon: _importing
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_rounded),
        label: Text(
          _importing && _importStatus.isNotEmpty
              ? _importStatus
              : _importing
                  ? 'Se importă…'
                  : 'Adaugă document',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: books.isEmpty ? _emptyLibrary(context) : _library(context, books),
    );
  }

  Widget _emptyLibrary(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(30, 24, 30, 120),
        child: Column(
          children: [
            Container(
              width: 150,
              height: 180,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(36),
              ),
              child: const Icon(Icons.menu_book_rounded, size: 72),
            ),
            const SizedBox(height: 30),
            Text(
              'Prima ta carte, citită frumos',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Adaugă un PDF, EPUB, DOCX, fișier text sau o fotografie. Inclusiv documentele scanate sunt citite local cu OCR.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _importDocument,
              icon: const Icon(Icons.file_open_rounded),
              label: const Text('Alege un document'),
            ),
            const SizedBox(height: 16),
            Text(
              'PDF · EPUB · DOCX · TXT · MD · HTML · IMAGINI',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _library(BuildContext context, List<BookDocument> books) {
    final current = books.first;
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          Text('Continuă să asculți', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          _ContinueCard(
            book: current,
            cover: widget.repository.coverFile(current),
            onTap: () => _openBook(current),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Text('Biblioteca ta', style: Theme.of(context).textTheme.titleLarge),
              ),
              Text('${books.length} ${books.length == 1 ? 'titlu' : 'titluri'}'),
            ],
          ),
          const SizedBox(height: 10),
          for (final book in books)
            _BookTile(
              book: book,
              cover: widget.repository.coverFile(book),
              onTap: () => _openBook(book),
              onDelete: () => _confirmDelete(book),
            ),
        ],
      ),
    );
  }

  Future<void> _importDocument() async {
    setState(() {
      _importing = true;
      _importStatus = 'Se importă…';
    });
    try {
      final imported = await _importer.pickAndExtract(
        onProgress: (progress) {
          if (mounted) setState(() => _importStatus = progress.label);
        },
      );
      if (imported == null || !mounted) return;
      final book = await widget.repository.add(imported);
      if (!mounted) return;
      setState(() {});
      await _openBook(book);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importStatus = '';
        });
      }
    }
  }

  Future<void> _importSharedDocument(SharedDocument shared) async {
    if (_importing || !mounted) return;
    setState(() {
      _importing = true;
      _importStatus = 'Se deschide…';
    });
    try {
      final imported = await _importer.extractPath(
        shared.path,
        displayName: shared.name,
        onProgress: (progress) {
          if (mounted) setState(() => _importStatus = progress.label);
        },
      );
      final book = await widget.repository.add(imported);
      if (!mounted) return;
      setState(() {});
      await _openBook(book);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importStatus = '';
        });
      }
    }
  }

  Future<void> _openBook(BookDocument book) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(repository: widget.repository, book: book),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(repository: widget.repository),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete(BookDocument book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ștergi documentul?'),
        content: Text('„${book.title}” și progresul său vor fi eliminate de pe telefon.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Șterge'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.repository.remove(book);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    unawaited(_sharedSubscription?.cancel());
    super.dispose();
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.cover,
    required this.onTap,
  });
  final BookDocument book;
  final File? cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              _BookCover(book: book, cover: cover, compact: true),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text('${book.format} · ${book.preset.shortLabel}'),
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: book.progress,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(height: 7),
                    Text('${(book.progress * 100).round()}% ascultat'),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const CircleAvatar(child: Icon(Icons.play_arrow_rounded)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.cover,
    required this.onTap,
    required this.onDelete,
  });
  final BookDocument book;
  final File? cover;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _BookCover(book: book, cover: cover),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 5),
                    Text('${book.format} · ${(book.progress * 100).round()}%'),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: book.progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Șterge')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book, required this.cover, this.compact = false});
  final BookDocument book;
  final File? cover;
  final bool compact;

  static const colors = [
    Color(0xFF315343),
    Color(0xFF71483D),
    Color(0xFF47506F),
    Color(0xFF6A5936),
    Color(0xFF435F69),
    Color(0xFF624A66),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 72 : 58,
      height: compact ? 94 : 76,
      decoration: BoxDecoration(
        color: colors[book.colorSeed % colors.length],
        borderRadius: BorderRadius.circular(compact ? 16 : 13),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: cover != null && cover!.existsSync()
          ? Image.file(cover!, fit: BoxFit.cover)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  book.title.isEmpty ? 'L' : book.title[0].toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 34 : 27,
                  ),
                ),
              ),
            ),
    );
  }
}
