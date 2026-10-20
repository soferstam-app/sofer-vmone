import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/version_check.dart';
import 'package:sofer_vmone/update_service.dart';

void main() {
  UpdateAvailable release(Uri url, List<int> bytes, {String? digest}) =>
      UpdateAvailable(
        version: const Version(0, 6, 0),
        pageUrl: 'https://example.invalid/release',
        asset: ReleaseAsset(
          name: 'sofer-vmone-0.6.0-windows.zip',
          downloadUrl: url,
          size: bytes.length,
          sha256Hex: digest ?? sha256.convert(bytes).toString(),
        ),
      );

  test('download keeps only a complete file with the published digest',
      () async {
    final bytes = utf8.encode('a small stand-in for a release artifact');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });

    final update = release(
      Uri.parse('http://${server.address.host}:${server.port}/update.zip'),
      bytes,
    );
    final seen = <UpdateDownloadProgress>[];
    final downloaded = await const UpdateService().download(
      update,
      onProgress: seen.add,
    );
    addTearDown(() async {
      if (await downloaded.workingDirectory.exists()) {
        await downloaded.workingDirectory.delete(recursive: true);
      }
    });

    expect(await downloaded.file.readAsBytes(), bytes);
    expect(seen.first.received, 0);
    expect(seen.last.received, bytes.length);
    expect(seen.last.fraction, 1);
  });

  test('a file whose digest differs is deleted and never returned', () async {
    final bytes = utf8.encode('tampered');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.add(bytes);
      await request.response.close();
    });

    final update = release(
      Uri.parse('http://${server.address.host}:${server.port}/update.zip'),
      bytes,
      digest: List<String>.filled(64, '0').join(),
    );
    await expectLater(
      const UpdateService().download(update),
      throwsA(
        isA<UpdateException>().having(
          (error) => error.message,
          'message',
          contains('אימות'),
        ),
      ),
    );
  });
}
