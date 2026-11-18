import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void downloadBrowserFile(String name, Uint8List bytes) {
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(link);
  try {
    link.click();
  } finally {
    link.remove();
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }
}

Future<void> playBrowserSound(String source, double volume) async {
  final audio = web.HTMLAudioElement()
    ..src = source
    ..volume = volume;
  await audio.play().toDart;
}
