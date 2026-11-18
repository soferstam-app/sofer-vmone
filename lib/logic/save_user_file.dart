import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../platform_support.dart';
import 'browser_io_stub.dart'
    if (dart.library.js_interop) 'browser_io_web.dart';

Future<String?> saveUserFile({
  required String dialogTitle,
  required String fileName,
  required Uint8List bytes,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  if (kIsWeb) {
    downloadBrowserFile(fileName, bytes);
    return fileName;
  }
  final path = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: type,
    allowedExtensions: allowedExtensions,
    bytes: PlatformSupport.isMobile ? bytes : null,
  );
  if (path != null && !PlatformSupport.isMobile) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return path;
}
