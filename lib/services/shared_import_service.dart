import 'dart:async';

import 'package:flutter/services.dart';

class SharedDocument {
  const SharedDocument({required this.path, required this.name});

  final String path;
  final String name;

  factory SharedDocument.fromMap(Map<Object?, Object?> value) {
    return SharedDocument(
      path: value['path']?.toString() ?? '',
      name: value['name']?.toString() ?? 'document',
    );
  }
}

class SharedImportService {
  SharedImportService._();

  static final instance = SharedImportService._();
  static const _channel = MethodChannel('ro.holban.lectura/import');
  final StreamController<SharedDocument> _controller =
      StreamController<SharedDocument>.broadcast();
  bool _configured = false;

  Stream<SharedDocument> get documents => _controller.stream;

  Future<SharedDocument?> initialize() async {
    if (!_configured) {
      _configured = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'importDocument' || call.arguments is! Map) return;
        final document = SharedDocument.fromMap(
          (call.arguments as Map).cast<Object?, Object?>(),
        );
        if (document.path.isNotEmpty) _controller.add(document);
      });
    }
    final result = await _channel.invokeMethod<Object?>('takePendingImport');
    if (result is! Map) return null;
    final document = SharedDocument.fromMap(result.cast<Object?, Object?>());
    return document.path.isEmpty ? null : document;
  }
}
