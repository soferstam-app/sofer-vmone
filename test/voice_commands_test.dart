import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sofer_vmone/home/voice_command_listener.dart';
import 'package:sofer_vmone/logic/voice_commands.dart';
import 'package:sofer_vmone/logic/voice_microphone.dart';
import 'package:sofer_vmone/logic/voice_recognition.dart';
import 'package:sofer_vmone/settings/voice_commands_screen.dart';

class _TestMicrophone extends VoiceMicrophone {
  final audio = StreamController<Uint8List>();
  final permission = Completer<bool>();
  int starts = 0;
  int closes = 0;

  @override
  Future<bool> hasPermission({required bool request}) => permission.future;

  @override
  Future<Stream<Uint8List>> open() async {
    starts++;
    return audio.stream;
  }

  @override
  Future<void> close() async {
    closes++;
    unawaited(audio.close());
  }
}

// Synthetic sounds exercise the signal pipeline without recording real voices.
Int16List phrase(List<int> pitches,
    {double speed = 1,
    int gain = 6500,
    int backgroundNoise = 0,
    int seed = 0}) {
  final noise = math.Random(seed);
  final partSize = (voiceSampleRate * .18 / speed).round();
  return Int16List.fromList([
    for (final pitch in pitches)
      for (var i = 0; i < partSize; i++)
        (gain *
                    math.sin(2 * math.pi * pitch * i / voiceSampleRate) *
                    math.sin(math.pi * i / partSize))
                .round() +
            noise.nextInt(backgroundNoise * 2 + 1) -
            backgroundNoise,
  ]);
}

Uint8List pcmBytes(Int16List samples, {int silence = 0}) {
  final bytes = ByteData((samples.length + silence) * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  test('Hebrew model requires a complete command', () {
    expect(voiceCommandFromTranscript(' סִיַּמְתִּי  שׁוּרָה. '),
        VoiceCommand.line);
    expect(voiceCommandFromTranscript('התחל כתיבה'), VoiceCommand.start);
    expect(voiceCommandFromTranscript('סיום שורה'), VoiceCommand.line);
    expect(voiceCommandFromTranscript('סיימתי את השורה'), VoiceCommand.line);
    expect(voiceCommandFromTranscript('צא להפסקה!'), VoiceCommand.takeBreak);
    for (final speech in [
      '',
      'עוד לא סיימתי שורה',
      'סיימתי שורה אחת',
      'שורה',
      'הוא אמר צא להפסקה',
    ]) {
      expect(voiceCommandFromTranscript(speech), isNull, reason: speech);
    }
  });
  const pitches = {
    VoiceCommand.start: [400, 690, 900, 1200, 510],
    VoiceCommand.line: [900, 340, 460, 690, 1400],
    VoiceCommand.takeBreak: [1200, 1020, 510, 470, 450],
  };

  void useMemoryPreferences() {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
  }

  testWidgets('Windows starts a requested capture when the window is visible',
      (tester) async {
    useMemoryPreferences();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final microphone = _TestMicrophone();
    await tester.pumpWidget(
        MaterialApp(home: VoiceCommandsScreen(microphone: microphone)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic_none).first);
    await tester.pump();
    expect(find.text('פותח את המיקרופון…'), findsOneWidget);
    microphone.permission.complete(true);
    await tester.pump();
    expect(microphone.starts, 1);
    expect(find.text('מחכה לשמע מהמיקרופון…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(find.textContaining('לא התקבל שמע מהמיקרופון'), findsOneWidget);
    expect(microphone.closes, 1);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('Android waits for foreground after granting permission',
      (tester) async {
    useMemoryPreferences();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final microphone = _TestMicrophone();
    await tester.pumpWidget(
        MaterialApp(home: VoiceCommandsScreen(microphone: microphone)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic_none).first);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    microphone.permission.complete(true);
    await tester.pump();
    expect(microphone.starts, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(microphone.starts, 1);
    microphone.audio.add(Uint8List(640));
    await tester.pump();
    expect(find.text('מקשיב… אמרו ״התחל כתיבה״.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('לא נקלט משפט קצר. נסו שוב.'), findsOneWidget);
    expect(microphone.closes, 1);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('resetting one command preserves every other recording',
      (tester) async {
    useMemoryPreferences();
    final store = VoiceProfileStore();
    final initial = VoiceCommandProfile({
      for (final entry in pitches.entries)
        entry.key: [
          for (final speed in [0.94, 1.0, 1.06])
            extractVoiceTemplate(phrase(entry.value, speed: speed)),
        ],
    }).withEnabled(true);
    await store.save(initial);
    await tester.pumpWidget(const MaterialApp(home: VoiceCommandsScreen()));
    await tester.pumpAndSettle();
    final reset = find.byTooltip('אפס דוגמאות של סיימתי שורה');
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();
    expect((await store.load()).encode(), initial.encode());

    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'אפס דוגמאות'));
    await tester.pumpAndSettle();
    final saved = await store.load();
    expect(saved.samples[VoiceCommand.line], isEmpty);
    expect(
        saved.samples[VoiceCommand.start], initial.samples[VoiceCommand.start]);
    expect(
      saved.samples[VoiceCommand.takeBreak],
      initial.samples[VoiceCommand.takeBreak],
    );
    expect(saved.enabled, isFalse);
    expect(find.text('0 מתוך 3'), findsOneWidget);
    expect(find.text('3 מתוך 3'), findsNWidgets(2));
  });

  test('local profile matches unseen variants and rejects other sounds', () {
    final profile = VoiceCommandProfile({
      for (final entry in pitches.entries)
        entry.key: [
          for (final speed in [0.9, 1.0, 1.1])
            extractVoiceTemplate(phrase(entry.value, speed: speed)),
        ],
    }).withEnabled(true);
    final restored = VoiceCommandProfile.decode(profile.encode());
    expect(restored.enabled, isTrue);
    for (final entry in pitches.entries) {
      expect(
        matchVoiceCommand(
            (restored, phrase(entry.value, speed: 1.03, gain: 4700))),
        entry.key,
      );
    }
    expect(matchVoiceCommand((restored, phrase([250, 530, 140, 900, 680]))),
        isNull);
    expect(matchVoiceCommand((restored, Int16List(voiceSampleRate))), isNull);
    expect(VoiceCommandProfile.decode('broken').enabled, isFalse);
    expect(const VoiceCommandProfile({}).withEnabled(true).enabled, isFalse);
  });

  test('microphone frames reject noise bursts and long reading', () {
    final segmenter = VoiceSegments();
    final pcm = phrase(pitches[VoiceCommand.line]!);
    final bytes = pcmBytes(pcm, silence: voiceSampleRate ~/ 2);
    // Audio packets need not respect frame or sample boundaries.
    expect(segmenter.add(Uint8List.sublistView(bytes, 0, 1771)), isEmpty);
    final captured = segmenter.add(Uint8List.sublistView(bytes, 1771)).single;
    expect(captured.length / voiceSampleRate, closeTo(0.9, 0.12));
    final reading = Int16List.fromList([
      for (var i = 0; i < voiceSampleRate * 5; i++) i.isEven ? 3000 : -3000,
      ...pcm,
    ]);
    expect(segmenter.add(pcmBytes(reading, silence: voiceSampleRate ~/ 2)),
        isEmpty);
    expect(
        segmenter.add(pcmBytes(Int16List(640)..fillRange(0, 640, 2000),
            silence: voiceSampleRate ~/ 2)),
        isEmpty);
    expect(segmenter.add(bytes), hasLength(1));
  });

  test('keeps a quiet onset and a normal pause between words', () {
    final quietOnset = Int16List(1600)..fillRange(0, 1600, 120);
    final line = pitches[VoiceCommand.line]!;
    final spoken = Int16List.fromList([
      ...quietOnset,
      ...phrase(line.sublist(0, 2)),
      ...Int16List(voiceSampleRate * 32 ~/ 100),
      ...phrase(line.sublist(2)),
    ]);
    final utterance = VoiceSegments()
        .add(pcmBytes(spoken, silence: voiceSampleRate ~/ 2))
        .single;
    expect(utterance.take(quietOnset.length), orderedEquals(quietOnset));
    expect(utterance.length, greaterThanOrEqualTo(spoken.length));
    final profile = VoiceCommandProfile({
      for (final entry in pitches.entries)
        entry.key: [
          for (final speed in [0.94, 1.0, 1.06])
            extractVoiceTemplate(phrase(entry.value, speed: speed)),
        ],
    });
    expect(matchVoiceCommand((profile, utterance)), VoiceCommand.line);
  });

  test('voice repeats keep the original 30-second deadline', () async {
    final guard = VoiceCommandRepeatGuard();
    final first = Completer<bool>();
    final appliedAt = <int>[];
    Future<bool> recognize(int second,
            {String project = 'a',
            VoiceCommand command = VoiceCommand.line,
            Completer<bool>? save}) =>
        guard.run(
          command,
          projectId: project,
          heardAt: Duration(seconds: second),
          apply: () async {
            appliedAt.add(second);
            return save == null || await save.future;
          },
        );

    final saving = recognize(0, save: first);
    expect(appliedAt, [0]);
    expect(await recognize(1), isFalse);
    first.complete(true);
    expect(await saving, isTrue);
    expect(await recognize(5), isFalse);
    expect(await recognize(9, command: VoiceCommand.takeBreak), isTrue);
    expect(await recognize(12, project: 'b'), isTrue);
    expect(await recognize(29), isFalse);
    expect(await recognize(30), isTrue);
    expect(appliedAt, [0, 9, 12, 30]);
  });

  test('a voice action whose save failed can be retried immediately', () async {
    final guard = VoiceCommandRepeatGuard();
    Future<bool> recognize(int second, bool saved) => guard.run(
          VoiceCommand.line,
          projectId: 'a',
          heardAt: Duration(seconds: second),
          apply: () async => saved,
        );
    expect(await recognize(0, false), isFalse);
    expect(await recognize(1, true), isTrue);
    expect(await recognize(2, true), isFalse);
  });

  test('calibration accepts a clear phrase after noisier enrollment', () {
    final profile = VoiceCommandProfile({
      for (final entry in pitches.entries)
        entry.key: [
          for (final (index, speed) in [0.92, 1.0, 1.08].indexed)
            extractVoiceTemplate(phrase(
              entry.value,
              speed: speed,
              backgroundNoise: 120 + index * 15,
              seed: index,
            )),
        ],
    });
    for (final entry in pitches.entries) {
      final spoken =
          phrase(entry.value, speed: 1.04, backgroundNoise: 15, seed: 13);
      expect(matchVoiceCommand((profile, spoken)), entry.key);
    }
    final unrelated = phrase([250, 530, 140, 900, 680], backgroundNoise: 15);
    expect(matchVoiceCommand((profile, unrelated)), isNull);
  });

  test('replacing one recording preserves the closest pair', () {
    final line = pitches[VoiceCommand.line]!;
    final samples = [
      extractVoiceTemplate(phrase(line, speed: .97)),
      extractVoiceTemplate(phrase(pitches[VoiceCommand.takeBreak]!)),
      extractVoiceTemplate(phrase(line, speed: 1.03)),
    ];
    expect(voiceExampleToReplace(samples), 1);
  });

  test('timer mode only permits applicable commands', () {
    for (final mode in VoiceTimerMode.values) {
      final enabled = VoiceCommand.values.where(mode.allows);
      expect(
          enabled,
          switch (mode) {
            VoiceTimerMode.idle || VoiceTimerMode.paused => [
                VoiceCommand.start
              ],
            VoiceTimerMode.writing => [
                VoiceCommand.line,
                VoiceCommand.takeBreak
              ],
            VoiceTimerMode.writingByWord => [VoiceCommand.takeBreak],
          });
    }
  });
}
