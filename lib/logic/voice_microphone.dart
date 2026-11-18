import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

import '../platform_support.dart';
import 'voice_commands.dart';

class VoiceMicrophone {
  static bool get supported =>
      PlatformSupport.isAndroid || PlatformSupport.isWindows;

  AudioRecorder? _recorder;

  Future<bool> hasPermission({required bool request}) =>
      (_recorder ??= AudioRecorder()).hasPermission(request: request);

  Future<Stream<Uint8List>> open() =>
      (_recorder ??= AudioRecorder()).startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: voiceSampleRate,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.none,
        androidConfig: AndroidRecordConfig(manageBluetooth: false),
      ));

  Future<void> close() async {
    final recorder = _recorder;
    _recorder = null;
    await recorder?.dispose();
  }
}

// Audio templates are kept separately from the account and backup stores.
class VoiceProfileStore {
  static const _key = 'offline_voice_command_profile';
  final _preferences = SharedPreferencesAsync(
    options: PlatformSupport.isAndroid
        ? const SharedPreferencesAsyncAndroidOptions(
            backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
            originalSharedPreferencesOptions:
                AndroidSharedPreferencesStoreOptions(
                    fileName: 'voice_commands'),
          )
        : const SharedPreferencesOptions(),
  );

  Future<VoiceCommandProfile> load() async =>
      VoiceCommandProfile.decode(await _preferences.getString(_key));

  Future<void> save(VoiceCommandProfile profile) =>
      _preferences.setString(_key, profile.encode());
}
