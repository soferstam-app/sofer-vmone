import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// A short offline click with a real, feature-specific volume control.
class MetronomeAudio {
  static const MethodChannel _channel = MethodChannel('sofer_vmone/metronome');
  bool _beatPlaying = false;
  bool _alertPlaying = false;
  DateTime? _alertUntil;

  MetronomeAudio();

  Future<bool> beat(int volumePercent) async {
    if (_beatPlaying ||
        volumePercent <= 0 ||
        _alertUntil?.isAfter(DateTime.now()) == true) {
      return false;
    }
    _beatPlaying = true;
    try {
      await _channel.invokeMethod<void>('beat', {
        'volume': volumePercent.clamp(0, 100),
      });
      return true;
    } catch (_) {
      // An optional working aid must never interrupt recording a sitting.
      return false;
    } finally {
      _beatPlaying = false;
    }
  }

  /// A deliberate, longer signal for a target or timer finishing.
  ///
  /// Flutter's SystemSound alert is ignored on Android, and its click is a
  /// no-op on Windows. This goes through the same native channel as the
  /// metronome so both supported platforms make an actual sound.
  Future<bool> alert() async {
    if (_alertPlaying) return false;
    _alertPlaying = true;
    // Do not let the next metronome beat cut the two-part signal short on
    // Windows, where PlaySound owns one asynchronous sound at a time.
    _alertUntil = DateTime.now().add(const Duration(milliseconds: 600));
    try {
      await _channel.invokeMethod<void>('alert');
      return true;
    } catch (_) {
      return false;
    } finally {
      _alertPlaying = false;
    }
  }

  Future<void> dispose() async {}
}

/// Builds a 24 ms PCM click. It starts sharply and decays immediately, so it
/// remains distinct at low volume without ringing under the writer's voice.
Uint8List buildMetronomeWav({
  int sampleRate = 44100,
  Duration duration = const Duration(milliseconds: 24),
}) {
  final samples = math.max(1, sampleRate * duration.inMicroseconds ~/ 1000000);
  const channels = 1;
  const bitsPerSample = 16;
  final dataLength = samples * channels * (bitsPerSample ~/ 8);
  final bytes = ByteData(44 + dataLength);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);

  var noise = 0x4d595df4;
  for (var i = 0; i < samples; i++) {
    final t = i / sampleRate;
    final decay = math.exp(-t * 185);
    noise = (1664525 * noise + 1013904223) & 0xffffffff;
    final random = ((noise / 0xffffffff) * 2) - 1;
    final tone = math.sin(2 * math.pi * 2350 * t);
    final shaped = ((tone * .72) + (random * .28)) * decay;
    final sample = (shaped * 30000).round().clamp(-32768, 32767);
    bytes.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// The shape mirrored by the native implementations for timer alerts.
Uint8List buildAlertWav({
  int sampleRate = 44100,
  Duration duration = const Duration(milliseconds: 420),
}) {
  final samples = math.max(1, sampleRate * duration.inMicroseconds ~/ 1000000);
  final dataLength = samples * 2;
  final bytes = ByteData(44 + dataLength);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);

  for (var i = 0; i < samples; i++) {
    final t = i / sampleRate;
    final first = t < .17;
    final second = t >= .23;
    final active = first || second;
    final frequency = first ? 880.0 : 1175.0;
    final edge = first
        ? math.min(t / .012, (.17 - t) / .018)
        : second
            ? math.min((t - .23) / .012, (.42 - t) / .025)
            : 0.0;
    final envelope = active ? edge.clamp(0.0, 1.0) : 0.0;
    final sample = (math.sin(2 * math.pi * frequency * t) * envelope * 28500)
        .round()
        .clamp(-32768, 32767);
    bytes.setInt16(44 + i * 2, sample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
