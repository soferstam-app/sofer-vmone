import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const voiceModelIncluded = true;
const _assets = 'packages/sofer_voice_model/assets';
const _files = {
  'encoder.int8.onnx': 70478964,
  'decoder.int8.onnx': 1049105,
  'joiner.int8.onnx': 771805,
  'tokens.txt': 17086,
};
const _sampleRate = 16000;
Future<SendPort>? _worker;

Future<String> transcribeVoiceCommand(Int16List pcm) async {
  final worker = await (_worker ??= _startWorker());
  final result = ReceivePort();
  try {
    worker.send((pcm, result.sendPort));
    final text = await result.first.timeout(const Duration(seconds: 5));
    if (text is! String) throw StateError('Hebrew speech decoding failed');
    return text;
  } finally {
    result.close();
  }
}

Future<String> _modelDirectory() async {
  if (Platform.isWindows) {
    final app = File(Platform.resolvedExecutable).parent.path;
    return '$app/data/flutter_assets/$_assets';
  }

  final cache = await getApplicationCacheDirectory();
  final directory = await Directory('${cache.path}/zipformer-he-6c6febcb')
      .create(recursive: true);
  for (final entry in _files.entries) {
    final file = File('${directory.path}/${entry.key}');
    if (await file.exists() && await file.length() == entry.value) continue;
    final data = await rootBundle.load('$_assets/${entry.key}');
    if (data.lengthInBytes != entry.value) {
      throw StateError('Incorrect bundled Hebrew model file: ${entry.key}');
    }
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    await temporary.rename(file.path);
  }
  return directory.path;
}

Future<SendPort> _startWorker() async {
  final model = await _modelDirectory();
  final ready = ReceivePort();
  try {
    final isolate = await Isolate.spawn(
      _recognizeInWorker,
      (model, ready.sendPort),
      onError: ready.sendPort,
      onExit: ready.sendPort,
      debugName: 'Hebrew voice model',
    );
    try {
      final result = await ready.first.timeout(const Duration(seconds: 8));
      if (result is! SendPort) throw StateError('Hebrew model failed: $result');
      return result;
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
  } finally {
    ready.close();
  }
}

void _recognizeInWorker((String, SendPort) input) {
  final (model, ready) = input;
  sherpa.initBindings(Platform.isWindows
      ? File(Platform.resolvedExecutable).parent.path
      : null);
  final recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
    model: sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(
        encoder: '$model/encoder.int8.onnx',
        decoder: '$model/decoder.int8.onnx',
        joiner: '$model/joiner.int8.onnx',
      ),
      tokens: '$model/tokens.txt',
      modelType: 'zipformer2',
      numThreads: 2,
      debug: false,
    ),
    enableEndpoint: false,
  ));
  final requests = ReceivePort();
  ready.send(requests.sendPort);
  requests.listen((message) {
    final (pcm, reply) = message as (Int16List, SendPort);
    try {
      final stream = recognizer.createStream();
      try {
        // A short silent tail lets the streaming encoder finish a short phrase.
        final waveform = Float32List(pcm.length + 24000);
        for (var i = 0; i < pcm.length; i++) {
          waveform[i] = pcm[i] / 32768;
        }
        stream.acceptWaveform(samples: waveform, sampleRate: _sampleRate);
        stream.inputFinished();
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }
        reply.send(recognizer.getResult(stream).text);
      } finally {
        stream.free();
      }
    } catch (_) {
      reply.send(null);
    }
  });
}
