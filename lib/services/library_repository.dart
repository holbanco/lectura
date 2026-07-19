import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/book_document.dart';
import '../models/narration_preset.dart';
import 'document_importer.dart';
import 'narration_style_detector.dart';

class LibraryRepository {
  late final Directory _root;
  late final Directory _textDirectory;
  late final Directory _audioDirectory;
  late final Directory _coverDirectory;
  late final File _indexFile;
  final List<BookDocument> _books = [];

  List<BookDocument> get books => List.unmodifiable(_books);
  Directory get audioDirectory => _audioDirectory;

  Future<void> initialize() async {
    final documents = await getApplicationDocumentsDirectory();
    _root = Directory(path.join(documents.path, 'lectura'));
    _textDirectory = Directory(path.join(_root.path, 'texts'));
    _audioDirectory = Directory(path.join(_root.path, 'audio_cache'));
    _coverDirectory = Directory(path.join(_root.path, 'covers'));
    _indexFile = File(path.join(_root.path, 'library.json'));
    await Future.wait([
      _root.create(recursive: true),
      _textDirectory.create(recursive: true),
      _audioDirectory.create(recursive: true),
      _coverDirectory.create(recursive: true),
    ]);
    await _loadIndex();
  }

  Future<BookDocument> add(ImportedDocument imported) async {
    final now = DateTime.now();
    final id = '${now.microsecondsSinceEpoch}_${imported.text.hashCode.abs()}';
    final textFileName = '$id.txt';
    final detected = NarrationStyleDetector.detect(
      imported.text,
      imported.originalFileName,
    );
    final coverFileName = imported.coverBytes == null ? null : '$id.jpg';
    final book = BookDocument(
      id: id,
      title: imported.title,
      originalFileName: imported.originalFileName,
      format: imported.format,
      textFileName: textFileName,
      importedAt: now,
      lastOpenedAt: now,
      characterCount: imported.text.length,
      preset: detected,
      studioVoice: detected.recommendedVoice,
      colorSeed: imported.title.hashCode.abs() % 6,
      chapters: imported.chapters,
      coverFileName: coverFileName,
      usedOcr: imported.usedOcr,
    );
    await File(path.join(_textDirectory.path, textFileName))
        .writeAsString(imported.text, flush: true);
    if (coverFileName != null) {
      await File(path.join(_coverDirectory.path, coverFileName))
          .writeAsBytes(imported.coverBytes!, flush: true);
    }
    _books.insert(0, book);
    await _writeIndex();
    return book;
  }

  Future<String> readText(BookDocument book) async {
    final file = File(path.join(_textDirectory.path, book.textFileName));
    final original = await file.readAsString();
    final normalized = DocumentImporter.normalizeText(original);
    if (normalized != original) {
      await file.writeAsString(normalized, flush: true);
    }
    return normalized;
  }

  File? coverFile(BookDocument book) {
    final name = book.coverFileName;
    return name == null ? null : File(path.join(_coverDirectory.path, name));
  }

  Future<void> update(BookDocument updated) async {
    final index = _books.indexWhere((book) => book.id == updated.id);
    if (index < 0) return;
    _books[index] = updated;
    _books.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    await _writeIndex();
  }

  Future<void> remove(BookDocument book) async {
    _books.removeWhere((item) => item.id == book.id);
    final textFile = File(path.join(_textDirectory.path, book.textFileName));
    if (await textFile.exists()) await textFile.delete();
    final cover = coverFile(book);
    if (cover != null && await cover.exists()) await cover.delete();
    await for (final entity in _audioDirectory.list()) {
      if (entity is File && path.basename(entity.path).startsWith('${book.id}_')) {
        await entity.delete();
      }
    }
    await _writeIndex();
  }

  Future<int> clearAudioCache() async {
    var bytes = 0;
    await for (final entity in _audioDirectory.list()) {
      if (entity is File) {
        bytes += await entity.length();
        await entity.delete();
      }
    }
    return bytes;
  }

  Future<int> audioCacheSize() async {
    var bytes = 0;
    await for (final entity in _audioDirectory.list()) {
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }

  Future<void> _loadIndex() async {
    _books.clear();
    if (!await _indexFile.exists()) return;
    try {
      final decoded = jsonDecode(await _indexFile.readAsString()) as List<dynamic>;
      _books.addAll(decoded.map(
        (item) => BookDocument.fromJson((item as Map).cast<String, Object?>()),
      ));
      _books.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    } on Object {
      final backup = File('${_indexFile.path}.corrupt');
      await _indexFile.copy(backup.path);
      _books.clear();
    }
  }

  Future<void> _writeIndex() async {
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(_books.map((book) => book.toJson()).toList());
    final temporary = File('${_indexFile.path}.tmp');
    await temporary.writeAsString(encoded, flush: true);
    if (await _indexFile.exists()) await _indexFile.delete();
    await temporary.rename(_indexFile.path);
  }
}
