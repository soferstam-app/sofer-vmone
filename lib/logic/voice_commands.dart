import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

enum VoiceCommand {
  start('התחל כתיבה'),
  line('סיימתי שורה'),
  takeBreak('צא להפסקה');

  const VoiceCommand(this.phrase);

  final String phrase;
}

typedef VoiceTemplate = List<List<double>>;

const voiceSampleRate = 16000;
const _coefficients = 12;
const _minFrames = 12;
const _maxFrames = 180;

/// Suppresses a repeat of the same successful voice action on this project.
/// The window begins on the first dispatch. A failed save can be retried and a
/// repeat does not move the original deadline.
class VoiceCommandRepeatGuard {
  static const window = Duration(seconds: 30);

  final Map<(String, VoiceCommand), Duration> _last = {};
  final Set<(String, VoiceCommand)> _pending = {};

  Future<bool> run(
    VoiceCommand command, {
    required String projectId,
    required Duration heardAt,
    required Future<bool> Function() apply,
  }) async {
    final key = (projectId, command);
    _last.removeWhere((_, firstAt) => heardAt - firstAt >= window);
    if (_last.containsKey(key) || !_pending.add(key)) {
      return false;
    }
    try {
      if (!await apply()) return false;
      _last[key] = heardAt;
      return true;
    } finally {
      _pending.remove(key);
    }
  }
}

class VoiceCommandProfile {
  static const samplesPerCommand = 3;
  static const empty = VoiceCommandProfile({});

  const VoiceCommandProfile(this.samples, {this.enabled = false});

  final Map<VoiceCommand, List<VoiceTemplate>> samples;
  final bool enabled;

  bool get ready => VoiceCommand.values
      .every((command) => samples[command]?.length == samplesPerCommand);

  VoiceCommandProfile withEnabled(bool value) =>
      VoiceCommandProfile(samples, enabled: value && ready);

  String encode() => jsonEncode({
        'version': 1,
        'enabled': enabled,
        for (final entry in samples.entries) entry.key.name: entry.value,
      });

  static VoiceCommandProfile decode(String? raw) {
    if (raw == null) return empty;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1) return empty;
      final samples = <VoiceCommand, List<VoiceTemplate>>{};
      for (final command in VoiceCommand.values) {
        final clips = data[command.name] as List<dynamic>? ?? [];
        if (clips.length > samplesPerCommand) return empty;
        samples[command] = clips.map((clip) {
          final frames = clip as List<dynamic>;
          if (frames.length < _minFrames || frames.length > _maxFrames) {
            throw const FormatException('Invalid voice sample duration');
          }
          return frames.map((frame) {
            final values = (frame as List<dynamic>)
                .map((value) => (value as num).toDouble())
                .toList();
            if (values.length != _coefficients ||
                values.any((value) => !value.isFinite)) {
              throw const FormatException('Invalid voice sample features');
            }
            return values;
          }).toList();
        }).toList();
      }
      return VoiceCommandProfile(samples).withEnabled(data['enabled'] == true);
    } on FormatException {
      return empty;
    } on TypeError {
      return empty;
    }
  }
}

/// Chops a PCM16 mono stream into short utterances using 20 ms energy frames.
/// Input can be split at any byte boundary. A long utterance is discarded
/// until the speaker stops, so a phrase inside a long reading is not accepted.
class VoiceSegments {
  static const _frameSamples = voiceSampleRate ~/ 50;
  static const _quietFrames = 20;
  static const _headSamples = 6 * _frameSamples;
  static const _maxSpeechFrames = 165;

  final _bytes = Uint8List(_frameSamples * 2);
  final List<int> _samples = [];
  final List<int> _leadIn = [];
  int _offset = 0;
  int _loud = 0;
  int _trailingQuiet = 0;
  bool _discarding = false;
  double _noise = 0.003;

  Iterable<Int16List> add(Uint8List chunk) sync* {
    var start = 0;
    while (start < chunk.length) {
      final count = math.min(chunk.length - start, _bytes.length - _offset);
      _bytes.setRange(_offset, _offset + count, chunk, start);
      _offset += count;
      start += count;
      if (_offset != _bytes.length) continue;
      _offset = 0;
      final phrase = _addFrame();
      if (phrase != null) yield phrase;
    }
  }

  Int16List? _addFrame() {
    final data = ByteData.sublistView(_bytes);
    var energy = 0.0;
    for (var i = 0; i < _bytes.length; i += 2) {
      final sample = data.getInt16(i, Endian.little) / 32768;
      energy += sample * sample;
    }
    final rms = math.sqrt(energy / _frameSamples);
    final voiced = rms > math.max(0.007, _noise * (_loud == 0 ? 2.8 : 2.0));
    _trailingQuiet = voiced ? 0 : _trailingQuiet + 1;
    if (_discarding) {
      if (_trailingQuiet >= _quietFrames) _discarding = false;
      return null;
    }
    if (_loud == 0 && !voiced) {
      _noise = _noise * 0.95 + rms * 0.05;
      for (var i = 0; i < _bytes.length; i += 2) {
        _leadIn.add(data.getInt16(i, Endian.little));
      }
      if (_leadIn.length > _headSamples) {
        _leadIn.removeRange(0, _leadIn.length - _headSamples);
      }
      return null;
    }
    if (_loud == 0) {
      _samples.addAll(_leadIn);
      _leadIn.clear();
    }
    if (voiced) _loud++;
    for (var i = 0; i < _bytes.length; i += 2) {
      _samples.add(data.getInt16(i, Endian.little));
    }
    if (_samples.length > _maxSpeechFrames * _frameSamples) {
      _samples.clear();
      _loud = 0;
      _discarding = true;
    } else if (_trailingQuiet >= _quietFrames) {
      final phrase = _loud >= 8
          ? Int16List.fromList(_samples.sublist(
              0, _samples.length - (_quietFrames - 2) * _frameSamples))
          : null;
      _samples.clear();
      _loud = 0;
      return phrase;
    }
    return null;
  }
}

/// Mel-frequency cepstral coefficients with per-utterance mean normalization,
/// so gain and constant differences between microphones matter less.
VoiceTemplate extractVoiceTemplate(Int16List pcm) {
  pcm = _shortenWordPauses(pcm);
  const size = 512;
  const hop = 320;
  const bands = 24;
  final fft = FFT(size);
  final window = List.generate(
      size, (i) => 0.54 - 0.46 * math.cos(2 * math.pi * i / (size - 1)));
  double mel(double hz) => 2595 * math.log(1 + hz / 700) / math.ln10;
  final edges = List.generate(bands + 2, (i) {
    final melValue = mel(120) + (mel(7000) - mel(120)) * i / (bands + 1);
    return (700 * (math.pow(10, melValue / 2595) - 1) * size / voiceSampleRate)
        .round();
  });
  final weights = List.generate(
      _coefficients,
      (k) => List.generate(
          bands,
          (j) =>
              math.sqrt(2 / bands) *
              math.cos(math.pi * (k + 1) * (j + 0.5) / bands)));
  final input = Float64List(size);
  final frames = <List<double>>[];
  for (var start = 0; start + size <= pcm.length; start += hop) {
    for (var i = 0; i < size; i++) {
      input[i] = pcm[start + i] / 32768 * window[i];
    }
    final power = fft.realFft(input).discardConjugates().squareMagnitudes();
    final logs = List.generate(bands, (i) {
      final left = edges[i], peak = edges[i + 1], right = edges[i + 2];
      var value = 0.0;
      for (var bin = left + 1; bin < right; bin++) {
        final weight = bin <= peak
            ? (bin - left) / (peak - left)
            : (right - bin) / (right - peak);
        value += weight * power[bin];
      }
      return math.log(value + 0.0001);
    });
    frames.add(List.generate(_coefficients, (k) {
      var value = 0.0;
      for (var i = 0; i < bands; i++) {
        value += logs[i] * weights[k][i];
      }
      return value;
    }));
  }
  if (frames.length < _minFrames || frames.length > _maxFrames) return [];
  for (var k = 0; k < _coefficients; k++) {
    final mean =
        frames.fold(0.0, (sum, frame) => sum + frame[k]) / frames.length;
    for (final frame in frames) {
      frame[k] -= mean;
    }
  }
  return frames;
}

/// Keep a small gap between words. Long runs of silence otherwise dominate
/// both the average spectrum and the rate comparison against the examples.
Int16List _shortenWordPauses(Int16List pcm) {
  const frame = voiceSampleRate ~/ 50;
  final energies = <double>[];
  for (var start = 0; start + frame <= pcm.length; start += frame) {
    var squared = 0.0;
    for (var i = start; i < start + frame; i++) {
      squared += (pcm[i] * pcm[i]).toDouble();
    }
    energies.add(squared / frame);
  }
  final ceiling = energies.fold(0.0, math.max);
  final quiet = math.max(160.0 * 160.0, ceiling * 0.0016);
  final shortened = <int>[];
  var pauseStart = -1;
  var keepFrom = 0;
  for (var i = 0; i < energies.length; i++) {
    if (energies[i] < quiet) {
      if (pauseStart < 0) pauseStart = i;
      continue;
    }
    if (pauseStart > 0 && i - pauseStart >= 5) {
      shortened.addAll(pcm.getRange(keepFrom, (pauseStart + 1) * frame));
      keepFrom = (i - 1) * frame;
    }
    pauseStart = -1;
  }
  if (keepFrom == 0) return pcm;
  shortened.addAll(pcm.getRange(keepFrom, pcm.length));
  return Int16List.fromList(shortened);
}

// Dynamic time warping accepts moderate differences in speaking speed.
double _distance(VoiceTemplate a, VoiceTemplate b) {
  final n = a.length, m = b.length;
  if (n > m * 2.4 || m > n * 2.4) return double.infinity;
  final radius = (m * 0.28).ceil();
  var previous = Float64List(m + 1)..fillRange(1, m + 1, double.infinity);
  var current = Float64List(m + 1);
  for (var i = 1; i <= n; i++) {
    current.fillRange(0, m + 1, double.infinity);
    final middle = (i * m / n).round();
    for (var j = math.max(1, middle - radius);
        j <= math.min(m, middle + radius);
        j++) {
      final x = a[i - 1], y = b[j - 1];
      var squared = 0.0;
      for (var k = 0; k < _coefficients; k++) {
        final delta = x[k] - y[k];
        squared += delta * delta;
      }
      final cost = math.sqrt(squared / _coefficients);
      current[j] = math.min(previous[j - 1] + 2 * cost,
          cost + math.min(previous[j], current[j - 1]));
    }
    (previous, current) = (current, previous);
  }
  return previous[m] / (m + n);
}

VoiceCommand? matchVoiceCommand((VoiceCommandProfile, Int16List) input) {
  final (profile, pcm) = input;
  final spoken = extractVoiceTemplate(pcm);
  if (spoken.isEmpty || !profile.ready) return null;
  final ranked = [
    for (final entry in profile.samples.entries)
      (command: entry.key, match: _compareCommand(spoken, entry.value)),
  ]..sort((a, b) => a.match.distance.compareTo(b.match.distance));
  final best = ranked.first;
  // Search every command, including ones unavailable in the current timer
  // state. A phrase for an unavailable command must not match another action.
  if (best.match.distance >= best.match.limit ||
      best.match.distance >= ranked[1].match.distance * 0.88) {
    return null;
  }
  return best.command;
}

List<({int first, int second, double distance})> _examplePairs(
    List<VoiceTemplate> examples) {
  return [
    for (var first = 0; first < examples.length; first++)
      for (var second = first + 1; second < examples.length; second++)
        (
          first: first,
          second: second,
          distance: _distance(examples[first], examples[second]),
        ),
  ]..sort((a, b) => a.distance.compareTo(b.distance));
}

/// Keep the pair that agrees best when replacing one full-profile recording.
int voiceExampleToReplace(List<VoiceTemplate> examples) {
  final closest = _examplePairs(examples).first;
  return List.generate(examples.length, (index) => index)
      .firstWhere((index) => index != closest.first && index != closest.second);
}

({double distance, double limit}) _compareCommand(
    VoiceTemplate spoken, List<VoiceTemplate> examples) {
  final pairs = _examplePairs(examples);
  final closest = pairs.first;
  final typical = pairs[1].distance;
  // A clipped or otherwise different third recording must not set the
  // tolerance for the two recordings that agree with each other.
  final hasOutlier = typical > math.max(1.15, closest.distance * 1.35 + 0.15);
  final distances = [
    for (var i = 0; i < examples.length; i++)
      if (!hasOutlier || i == closest.first || i == closest.second)
        _distance(spoken, examples[i]),
  ]..sort();
  final baseline = hasOutlier ? closest.distance : typical;
  // A new utterance must match two recordings and be distinct from the
  // competing commands, even when enrollment was inconsistent.
  final limit = (baseline * 1.20 + 0.40).clamp(0.85, 1.95);
  return (distance: distances[1], limit: limit);
}
