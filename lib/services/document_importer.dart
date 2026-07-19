import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

class ImportedDocument {
  const ImportedDocument({
    required this.title,
    required this.originalFileName,
    required this.format,
    required this.text,
  });

  final String title;
  final String originalFileName;
  final String format;
  final String text;
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
  ];

  Future<ImportedDocument?> pickAndExtract() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return extract(result.files.single);
  }

  Future<ImportedDocument> extract(PlatformFile file) async {
    final suffix = path.extension(file.name);
    final extension = (file.extension ??
            (suffix.startsWith('.') && suffix.length > 1 ? suffix.substring(1) : ''))
        .toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw DocumentImportException('Formatul .$extension nu este încă acceptat.');
    }
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      throw const DocumentImportException('Fișierul este gol sau nu poate fi citit.');
    }

    late final String extracted;
    switch (extension) {
      case 'pdf':
        extracted = await _extractPdf(bytes, file.name);
        break;
      case 'docx':
        extracted = _extractDocx(bytes);
        break;
      case 'epub':
        extracted = _extractEpub(bytes);
        break;
      case 'html':
      case 'htm':
        extracted = _extractHtml(_decodeText(bytes));
        break;
      default:
        extracted = _decodeText(bytes);
        break;
    }
    final normalized = normalizeText(extracted);
    if (normalized.length < 20) {
      if (extension == 'pdf') {
        throw const DocumentImportException(
          'PDF-ul nu conține text selectabil. Pare scanat; va necesita modulul OCR.',
        );
      }
      throw const DocumentImportException(
        'Nu am găsit suficient text lizibil în acest fișier.',
      );
    }

    return ImportedDocument(
      title: _titleFromFileName(file.name),
      originalFileName: file.name,
      format: extension.toUpperCase(),
      text: normalized,
    );
  }

  Future<String> _extractPdf(Uint8List bytes, String sourceName) async {
    final document = await PdfDocument.openData(bytes, sourceName: sourceName);
    try {
      final output = StringBuffer();
      for (final page in document.pages) {
        final pageText = await page.loadText();
        final text = pageText?.fullText.trim();
        if (text != null && text.isNotEmpty) {
          output
            ..writeln(text)
            ..writeln();
        }
      }
      return output.toString();
    } finally {
      document.dispose();
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

  String _extractEpub(Uint8List bytes) {
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
    for (final item in packageXml.descendantElements.where(
      (element) => element.name.local == 'item',
    )) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
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
    return output.toString();
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
