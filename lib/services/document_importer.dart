import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../models/document_chapter.dart';

class ImportProgress {
  const ImportProgress({
    required this.message,
    this.current,
    this.total,
  });

  final String message;
  final int? current;
  final int? total;

  String get label {
    if (current == null || total == null) return message;
    return '$message $current/$total';
  }
}

class ImportedDocument {
  const ImportedDocument({
    required this.title,
    required this.originalFileName,
    required this.format,
    required this.text,
    this.chapters = const [],
    this.coverBytes,
    this.usedOcr = false,
  });

  final String title;
  final String originalFileName;
  final String format;
  final String text;
  final List<DocumentChapter> chapters;
  final Uint8List? coverBytes;
  final bool usedOcr;
}

class DocumentImportException implements Exception {
  const DocumentImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DocumentImporter {
  static const supportedExtensions = <String>[
    'pdf',
    'epub',
    'docx',
    'txt',
    'md',
    'html',
    'htm',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
  ];

  Future<ImportedDocument?> pickAndExtract({
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return extract(result.files.single, onProgress: onProgress);
  }

  Future<ImportedDocument> extractPath(
    String filePath, {
    String? displayName,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const DocumentImportException(
        'Fișierul primit de la cealaltă aplicație nu mai este disponibil.',
      );
    }
    return extract(
      PlatformFile(
        name: displayName ?? path.basename(filePath),
        path: filePath,
        size: await file.length(),
      ),
      onProgress: onProgress,
    );
  }

  Future<ImportedDocument> extract(
    PlatformFile file, {
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final suffix = path.extension(file.name);
    final extension = (file.extension ??
            (suffix.startsWith('.') && suffix.length > 1 ? suffix.substring(1) : ''))
        .toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw DocumentImportException('Formatul .$extension nu este încă acceptat.');
    }
    onProgress?.call(const ImportProgress(message: 'Se citește documentul…'));
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      throw const DocumentImportException('Fișierul este gol sau nu poate fi citit.');
    }

    late final _ExtractedContent extracted;
    switch (extension) {
      case 'pdf':
        extracted = await _extractPdf(bytes, file.name, onProgress);
        break;
      case 'docx':
        extracted = _ExtractedContent(text: _extractDocx(bytes));
        break;
      case 'epub':
        extracted = _extractEpub(bytes);
        break;
      case 'html':
      case 'htm':
        extracted = _ExtractedContent(text: _extractHtml(_decodeText(bytes)));
        break;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'heic':
        extracted = await _extractImage(bytes, extension, onProgress);
        break;
      default:
        extracted = _ExtractedContent(text: _decodeText(bytes));
        break;
    }
    onProgress?.call(const ImportProgress(message: 'Se organizează capitolele…'));
    final normalized = normalizeText(extracted.text);
    if (normalized.length < 20) {
      throw const DocumentImportException(
        'Nu am găsit suficient text lizibil în acest fișier.',
      );
    }

    return ImportedDocument(
      title: _titleFromFileName(file.name),
      originalFileName: file.name,
      format: extension.toUpperCase(),
      text: normalized,
      chapters: detectChapters(normalized),
      coverBytes: extracted.coverBytes,
      usedOcr: extracted.usedOcr,
    );
  }

  Future<_ExtractedContent> _extractPdf(
    Uint8List bytes,
    String sourceName,
    void Function(ImportProgress progress)? onProgress,
  ) async {
    final document = await PdfDocument.openData(bytes, sourceName: sourceName);
    TextRecognizer? recognizer;
    var usedOcr = false;
    Uint8List? coverBytes;
    try {
      final output = StringBuffer();
      final pages = document.pages.toList();
      for (var index = 0; index < pages.length; index++) {
        final page = pages[index];
        onProgress?.call(ImportProgress(
          message: 'Se citește pagina',
          current: index + 1,
          total: pages.length,
        ));
        if (index == 0) {
          coverBytes = await _renderPdfCover(page);
        }
        final pageText = await page.loadText();
        var text = pageText?.fullText.trim() ?? '';
        if (text.length < 20) {
          recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
          onProgress?.call(ImportProgress(
            message: 'OCR local · pagina',
            current: index + 1,
            total: pages.length,
          ));
          final recognized = await _recognizePdfPage(page, recognizer);
          if (recognized.trim().isNotEmpty) {
            text = recognized.trim();
            usedOcr = true;
          }
        }
        if (text.isNotEmpty) {
          output
            ..writeln(text)
            ..writeln();
        }
      }
      return _ExtractedContent(
        text: output.toString(),
        coverBytes: coverBytes,
        usedOcr: usedOcr,
      );
    } finally {
      await recognizer?.close();
      document.dispose();
    }
  }

  Future<String> _recognizePdfPage(
    PdfPage page,
    TextRecognizer recognizer,
  ) async {
    const targetWidth = 1800;
    final targetHeight = (page.height / page.width * targetWidth)
        .round()
        .clamp(1, 3200);
    final rendered = await page.render(
      width: targetWidth,
      height: targetHeight,
      fullWidth: targetWidth.toDouble(),
      fullHeight: targetHeight.toDouble(),
    );
    if (rendered == null) return '';
    final temporaryDirectory = await getTemporaryDirectory();
    final temporary = File(path.join(
      temporaryDirectory.path,
      'lectura_ocr_${DateTime.now().microsecondsSinceEpoch}_${page.pageNumber}.png',
    ));
    try {
      final image = rendered.createImageNF();
      await temporary.writeAsBytes(img.encodePng(image), flush: true);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(temporary.path),
      );
      return recognized.text;
    } finally {
      rendered.dispose();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Uint8List?> _renderPdfCover(PdfPage page) async {
    const targetWidth = 420;
    final targetHeight = (page.height / page.width * targetWidth)
        .round()
        .clamp(1, 760);
    final rendered = await page.render(
      width: targetWidth,
      height: targetHeight,
      fullWidth: targetWidth.toDouble(),
      fullHeight: targetHeight.toDouble(),
    );
    if (rendered == null) return null;
    try {
      return Uint8List.fromList(
        img.encodeJpg(rendered.createImageNF(), quality: 82),
      );
    } finally {
      rendered.dispose();
    }
  }

  Future<_ExtractedContent> _extractImage(
    Uint8List bytes,
    String extension,
    void Function(ImportProgress progress)? onProgress,
  ) async {
    onProgress?.call(const ImportProgress(message: 'OCR local · se citește imaginea…'));
    final temporaryDirectory = await getTemporaryDirectory();
    final temporary = File(path.join(
      temporaryDirectory.path,
      'lectura_image_${DateTime.now().microsecondsSinceEpoch}.$extension',
    ));
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(temporary.path),
      );
      return _ExtractedContent(
        text: recognized.text,
        coverBytes: _imageCover(bytes),
        usedOcr: true,
      );
    } finally {
      await recognizer.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _extractDocx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = _findArchiveFile(archive, 'word/document.xml');
    if (entry == null) {
      throw const DocumentImportException('Documentul DOCX este invalid.');
    }
    final xml = XmlDocument.parse(
      utf8.decode(_archiveBytes(entry), allowMalformed: true),
    );
    final output = StringBuffer();
    for (final paragraph in xml.descendantElements.where(
      (element) => element.name.local == 'p',
    )) {
      final paragraphText = paragraph.descendantElements
          .where((element) => element.name.local == 't')
          .map((element) => element.innerText)
          .join();
      if (paragraphText.trim().isNotEmpty) output.writeln(paragraphText.trim());
    }
    return output.toString();
  }

  _ExtractedContent _extractEpub(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final container = _findArchiveFile(archive, 'META-INF/container.xml');
    if (container == null) {
      throw const DocumentImportException('Fișierul EPUB este invalid.');
    }
    final containerXml = XmlDocument.parse(
      utf8.decode(_archiveBytes(container), allowMalformed: true),
    );
    final rootFile = containerXml.descendantElements
        .where((element) => element.name.local == 'rootfile')
        .firstOrNull
        ?.getAttribute('full-path');
    if (rootFile == null) {
      throw const DocumentImportException('Nu am găsit structura cărții EPUB.');
    }
    final packageFile = _findArchiveFile(archive, rootFile);
    if (packageFile == null) {
      throw const DocumentImportException('Cuprinsul EPUB nu poate fi citit.');
    }

    final packageXml = XmlDocument.parse(
      utf8.decode(_archiveBytes(packageFile), allowMalformed: true),
    );
    final manifest = <String, String>{};
    final properties = <String, String>{};
    for (final item in packageXml.descendantElements.where(
      (element) => element.name.local == 'item',
    )) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) {
        manifest[id] = href;
        properties[id] = item.getAttribute('properties') ?? '';
      }
    }
    final base = path.posix.dirname(rootFile);
    final output = StringBuffer();
    for (final ref in packageXml.descendantElements.where(
      (element) => element.name.local == 'itemref',
    )) {
      final id = ref.getAttribute('idref');
      final href = id == null ? null : manifest[id];
      if (href == null) continue;
      final decodedHref = Uri.decodeComponent(href.split('#').first);
      final fullPath = path.posix.normalize(path.posix.join(base, decodedHref));
      final contentFile = _findArchiveFile(archive, fullPath);
      if (contentFile == null) continue;
      final chapter = _extractHtml(
        utf8.decode(_archiveBytes(contentFile), allowMalformed: true),
      );
      if (chapter.trim().isNotEmpty) {
        output
          ..writeln(chapter.trim())
          ..writeln();
      }
    }

    Uint8List? coverBytes;
    String? coverId = packageXml.descendantElements
        .where((element) =>
            element.name.local == 'meta' && element.getAttribute('name') == 'cover')
        .firstOrNull
        ?.getAttribute('content');
    coverId ??= properties.entries
        .where((entry) => entry.value.split(' ').contains('cover-image'))
        .firstOrNull
        ?.key;
    final coverHref = coverId == null ? null : manifest[coverId];
    if (coverHref != null) {
      final fullPath = path.posix.normalize(path.posix.join(
        base,
        Uri.decodeComponent(coverHref.split('#').first),
      ));
      final coverFile = _findArchiveFile(archive, fullPath);
      if (coverFile != null) coverBytes = _imageCover(_archiveBytes(coverFile));
    }
    return _ExtractedContent(text: output.toString(), coverBytes: coverBytes);
  }

  String _extractHtml(String source) {
    final document = html_parser.parse(source);
    for (final element in document.querySelectorAll('script, style, nav')) {
      element.remove();
    }
    final blocks = document.querySelectorAll(
      'h1, h2, h3, h4, h5, h6, p, li, blockquote, pre',
    );
    if (blocks.isNotEmpty) {
      return blocks
          .map((element) => element.text.trim())
          .where((text) => text.isNotEmpty)
          .join('\n\n');
    }
    return document.body?.text ?? document.documentElement?.text ?? '';
  }

  static Uint8List? _imageCover(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = decoded.width > 420
        ? img.copyResize(decoded, width: 420, interpolation: img.Interpolation.average)
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 84));
  }

  static ArchiveFile? _findArchiveFile(Archive archive, String requestedName) {
    final wanted = path.posix.normalize(requestedName).replaceAll('\\', '/');
    return archive.files.where((file) {
      final candidate = path.posix.normalize(file.name).replaceAll('\\', '/');
      return candidate == wanted;
    }).firstOrNull;
  }

  static Uint8List _archiveBytes(ArchiveFile file) {
    final bytes = file.readBytes();
    if (bytes == null) {
      throw const DocumentImportException(
        'Arhiva documentului conține un fișier care nu poate fi citit.',
      );
    }
    return bytes;
  }

  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    }
    return utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
  }

  static String normalizeText(String input) {
    var normalized = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAllMapped(
          RegExp(r'([A-Za-zÀ-žĂÂÎȘȚăâîșț])-\n([a-zà-žăâîșț])'),
          (match) => '${match[1]}${match[2]}',
        )
        .trim();
    if (_looksLikeLegacyRomanian(normalized)) {
      normalized = normalized
          .replaceAll('Ń', 'ț')
          .replaceAll('ń', 'ț')
          .replaceAll('Ţ', 'Ț')
          .replaceAll('ţ', 'ț')
          .replaceAll('Ş', 'Ș')
          .replaceAll('ş', 'ș')
          .replaceAll('Ã', 'ă')
          .replaceAll('ã', 'ă');
    }
    return normalized;
  }

  static List<DocumentChapter> detectChapters(String text) {
    if (text.isEmpty) return const [];
    final chapters = <DocumentChapter>[];
    final heading = RegExp(
      r'^(?:(?:capitol(?:ul)?|chapter|partea|part)\s+[\divxlcdm]+(?:\s*[:.\-–—]\s*[^\n]{1,70})?|(?:\d{1,3}|[ivxlcdm]{1,8})[.)]\s+[A-ZĂÂÎȘȚ][^\n]{2,70})\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    for (final match in heading.allMatches(text)) {
      final title = match.group(0)!.trim();
      if (title.length < 3 || title.length > 90) continue;
      if (chapters.isNotEmpty && match.start - chapters.last.start < 120) continue;
      chapters.add(DocumentChapter(title: title, start: match.start));
      if (chapters.length >= 250) break;
    }
    if (chapters.isEmpty) {
      return const [DocumentChapter(title: 'Document', start: 0)];
    }
    if (chapters.first.start < 200) {
      chapters[0] = DocumentChapter(title: chapters.first.title, start: 0);
    } else {
      chapters.insert(0, const DocumentChapter(title: 'Început', start: 0));
    }
    return chapters;
  }

  static bool _looksLikeLegacyRomanian(String text) {
    if (!RegExp('[ŃńŢţŞşÃã]').hasMatch(text)) return false;
    final sample = ' ${text.toLowerCase()} ';
    const markers = [
      ' și ',
      ' şi ',
      ' este ',
      ' sunt ',
      ' pentru ',
      ' care ',
      ' din ',
      ' cu ',
      ' la ',
      ' în ',
    ];
    return markers.where(sample.contains).length >= 3;
  }

  static String _titleFromFileName(String fileName) {
    final base = path.basenameWithoutExtension(fileName)
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (base.isEmpty) return 'Document fără titlu';
    return '${base[0].toUpperCase()}${base.substring(1)}';
  }
}

class _ExtractedContent {
  const _ExtractedContent({
    required this.text,
    this.coverBytes,
    this.usedOcr = false,
  });

  final String text;
  final Uint8List? coverBytes;
  final bool usedOcr;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
