import 'dart:typed_data';

void downloadBrowserFile(String name, Uint8List bytes) =>
    throw UnsupportedError('Browser download is unavailable');

Future<void> playBrowserSound(String source, double volume) =>
    throw UnsupportedError('Browser audio is unavailable');
