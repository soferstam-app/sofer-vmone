import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../logic/voice_commands.dart';
import '../logic/voice_microphone.dart';
import '../logic/voice_recognition.dart';
import '../widgets/confirm.dart';
import '../widgets/feedback.dart';

class VoiceCommandsScreen extends StatefulWidget {
  const VoiceCommandsScreen({super.key, this.microphone});

  final VoiceMicrophone? microphone;

  @override
  State<VoiceCommandsScreen> createState() => _VoiceCommandsScreenState();
}

class _VoiceCommandsScreenState extends State<VoiceCommandsScreen>
    with WidgetsBindingObserver {
  final _store = VoiceProfileStore();
  late final _microphone = widget.microphone ?? VoiceMicrophone();
  VoiceCommandProfile? _profile;
  bool _busy = false;
  bool _listening = false;
  String? _result;
  Completer<void>? _resumed;

  bool _canRecord(AppLifecycleState? state) =>
      state == AppLifecycleState.resumed ||
      (defaultTargetPlatform == TargetPlatform.windows &&
          (state == null || state == AppLifecycleState.inactive));

  bool get _foreground => _canRecord(WidgetsBinding.instance.lifecycleState);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final profile = await _store.load();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      if (mounted) {
        setState(() => _result = context.l10n.pick(
            he: 'לא הצלחתי לטעון את דוגמאות הקול.',
            en: 'Could not load the voice samples.'));
      }
    }
  }

  Future<void> _save(VoiceCommandProfile profile) async {
    await _store.save(profile);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _changeProfile(VoiceCommandProfile profile,
      {String? message}) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await _save(profile);
      if (mounted && message != null) setState(() => _result = message);
    } catch (_) {
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'הגדרת הפקודות לא נשמרה.',
                en: 'Voice settings could not be saved.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetCommand(VoiceCommand command) async {
    final profile = _profile;
    if (_busy || profile == null) return;
    final l10n = context.l10n;
    final phrase = command.phrase;
    final confirmed = await confirmAction(
      context,
      title: l10n.pick(he: 'איפוס דוגמאות', en: 'Reset examples'),
      message: l10n.pick(
        he: 'למחוק את דוגמאות הקול של ״$phrase״?',
        en: 'Delete the voice examples for “$phrase”?',
      ),
      confirmLabel: l10n.pick(he: 'אפס דוגמאות', en: 'Reset examples'),
      danger: true,
    );
    if (!confirmed || !mounted) return;
    final remaining = {...profile.samples}..remove(command);
    await _changeProfile(
      VoiceCommandProfile(remaining),
      message: l10n.pick(
        he: 'הדוגמאות של ״$phrase״ אופסו. הקליטו את הפקודה מחדש כדי להפעיל את הזיהוי בטיימר.',
        en: 'Examples for “$phrase” were reset. Record the phrase again to enable recognition on the timer.',
      ),
    );
  }

  Future<void> _capture([VoiceCommand? command]) async {
    final profile = _profile;
    if (_busy || profile == null) return;
    setState(() {
      _busy = true;
      _result = context.l10n
          .pick(he: 'פותח את המיקרופון…', en: 'Opening the microphone…');
    });
    var receivedAudio = false;
    var receivedPhrase = false;
    try {
      final granted = await _microphone.hasPermission(request: true);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (!granted) {
        setState(() => _result = context.l10n.pick(
            he: 'נדרשת הרשאת מיקרופון.', en: 'Microphone access is required.'));
        return;
      }
      // Android can report the permission result before the dialog lets the
      // activity resume. Wait for the screen before activating the microphone.
      if (!_foreground) {
        final resumed = _resumed = Completer<void>();
        await resumed.future
            .timeout(const Duration(seconds: 3), onTimeout: () {});
        _resumed = null;
      }
      if (!_checkRecordingScreen()) return;
      final stream = await _microphone.open();
      if (!_checkRecordingScreen()) return;
      setState(() {
        _listening = true;
        _result = context.l10n.pick(
            he: 'מחכה לשמע מהמיקרופון…', en: 'Waiting for microphone audio…');
      });
      final segments = VoiceSegments();
      final phrases = stream.expand((chunk) {
        if (!mounted || !_listening) return const <Int16List>[];
        if (!receivedAudio && chunk.isNotEmpty) {
          receivedAudio = true;
          setState(() => _result = context.l10n.pick(
                he: command == null
                    ? 'מקשיב… אמרו את הפקודה.'
                    : 'מקשיב… אמרו ״${command.phrase}״.',
                en: command == null
                    ? 'Listening… Say the command.'
                    : 'Listening… Say “${command.phrase}”.',
              ));
        }
        return segments.add(chunk);
      });
      const timeLimit = Duration(seconds: 9);
      if (command == null) {
        final recognized = await phrases
            .asyncMap((pcm) {
              receivedPhrase = true;
              return recognizeVoiceCommand(profile, pcm);
            })
            .firstWhere((candidate) => candidate != null)
            .timeout(timeLimit);
        if (!mounted || !_listening) return;
        final phrase = recognized!.command.phrase;
        final l10n = context.l10n;
        final source = !voiceModelIncluded
            ? ''
            : recognized.fromModel
                ? l10n.pick(he: ' · המודל העברי', en: ' · Hebrew model')
                : l10n.pick(he: ' · דוגמאות הקול', en: ' · Voice samples');
        setState(() => _result = l10n.pick(
            he: 'זוהתה הפקודה ״$phrase״$source',
            en: 'Detected “$phrase”$source'));
      } else {
        final pcm = await phrases.first.timeout(timeLimit);
        await _microphone.close();
        if (!mounted || !_listening) return;
        setState(() {
          _listening = false;
          _result = context.l10n.pick(he: 'מעבד את הדוגמה…', en: 'Processing…');
        });
        final sample = await compute(extractVoiceTemplate, pcm);
        if (!mounted) return;
        if (sample.isEmpty) {
          setState(() => _result = context.l10n.pick(
              he: 'אמרו את המשפט המלא ונסו שוב.',
              en: 'Say the entire phrase and try again.'));
          return;
        }
        final examples = [...?profile.samples[command]];
        if (examples.length == VoiceCommandProfile.samplesPerCommand) {
          examples[voiceExampleToReplace(examples)] = sample;
        } else {
          examples.add(sample);
        }
        await _save(VoiceCommandProfile(
          {...profile.samples, command: examples},
          enabled: profile.enabled,
        ));
        if (mounted) {
          setState(() => _result = context.l10n
              .pick(he: 'דוגמת הקול נשמרה.', en: 'Voice example saved.'));
        }
      }
    } on VoiceModelUnavailable catch (error) {
      if (mounted) {
        debugPrint('Voice model failed: ${error.cause}');
        setState(() => _result = context.l10n.pick(
            he: 'המודל העברי לא זמין. נסו לפתוח מחדש את התוכנה.',
            en: 'The Hebrew model is unavailable. Try reopening the app.'));
      }
    } on TimeoutException {
      if (mounted) {
        setState(
            () => _result = _timeoutMessage(receivedAudio, receivedPhrase));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _result = context.l10n.pick(
            he: 'לא הצלחתי להשלים את ההקלטה. בדקו את המיקרופון ונסו שוב.',
            en: 'Could not complete recording. Check the microphone and try again.'));
      }
    } finally {
      await _closeMicrophone();
      if (mounted) {
        setState(() {
          _listening = false;
          _busy = false;
        });
      }
    }
  }

  String _timeoutMessage(bool receivedAudio, bool receivedPhrase) {
    final l10n = context.l10n;
    if (receivedPhrase) {
      return l10n.pick(
        he: 'לא זוהתה פקודה. אפשר להחליף דוגמה במיקרופון או לאפס את הדוגמאות של אותה פקודה.',
        en: 'No command detected. Replace an example with the microphone button or reset that command’s examples.',
      );
    }
    if (receivedAudio) {
      return l10n.pick(
          he: 'לא נקלט משפט קצר. נסו שוב.',
          en: 'No short phrase was captured. Try again.');
    }
    return l10n.pick(
        he: 'לא התקבל שמע מהמיקרופון. בדקו את התקן הקלט ואת ההרשאות.',
        en: 'No microphone audio received. Check the input device and permissions.');
  }

  bool _checkRecordingScreen() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    if (_foreground) return true;
    setState(() => _result = context.l10n.pick(
        he: 'חזרו לחלון התוכנה ולחצו שוב על ההקלטה.',
        en: 'Return to the app window and start recording again.'));
    return false;
  }

  Future<void> _closeMicrophone() async {
    try {
      await _microphone.close();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_canRecord(state)) {
      _finishPermissionDialog();
    } else if (_listening) {
      setState(() => _listening = false);
      unawaited(_closeMicrophone());
    }
  }

  void _finishPermissionDialog() {
    final resumed = _resumed;
    if (resumed != null && !resumed.isCompleted) resumed.complete();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finishPermissionDialog();
    unawaited(_closeMicrophone());
    super.dispose();
  }

  Widget _commandTile(VoiceCommandProfile profile, VoiceCommand command) {
    final l10n = context.l10n;
    final count = profile.samples[command]?.length ?? 0;
    return ListTile(
      title: Text(command.phrase),
      subtitle: Text(l10n.pick(he: '$count מתוך 3', en: '$count of 3')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: count == VoiceCommandProfile.samplesPerCommand
                ? l10n.pick(he: 'החלף דוגמה', en: 'Replace an example')
                : l10n.pick(he: 'הקלט דוגמה', en: 'Record example'),
            icon: const Icon(Icons.mic_none),
            onPressed: _busy ? null : () => _capture(command),
          ),
          IconButton(
            tooltip: l10n.pick(
                he: 'אפס דוגמאות של ${command.phrase}',
                en: 'Reset examples for ${command.phrase}'),
            icon: const Icon(Icons.restart_alt),
            onPressed:
                _busy || count == 0 ? null : () => _resetCommand(command),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
          title: Text(l10n.pick(
              he: 'פקודות קוליות (ניסוי)',
              en: 'Voice commands (experimental)'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(voiceModelIncluded
              ? l10n.pick(
                  he: 'המודל העברי עובד במכשיר. אפשר לבדוק פקודה מיד. להפעלה בטיימר הקליטו שלוש דוגמאות לכל משפט.',
                  en: 'The Hebrew model runs on this device. You can test a command now. Record three examples per phrase to use commands on the timer.')
              : l10n.pick(
                  he: 'הקליטו שלוש דוגמאות לכל משפט, ואז בדקו את הזיהוי. '
                      'דוגמאות הקול והזיהוי נשארים במכשיר.',
                  en: 'Record three examples of each phrase, then try recognition. '
                      'Voice samples and recognition stay on this device.')),
          if (_result case final result?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Semantics(liveRegion: true, child: Text(result)),
            ),
          if (profile == null && _result == null)
            const Center(child: CircularProgressIndicator()),
          if (profile != null) ...[
            for (final command in VoiceCommand.values)
              _commandTile(profile, command),
            FilledButton.tonalIcon(
              onPressed: !_busy && (profile.ready || voiceModelIncluded)
                  ? () => _capture()
                  : null,
              icon: const Icon(Icons.hearing),
              label: Text(l10n.pick(he: 'בדוק פקודה', en: 'Test a command')),
            ),
            SwitchListTile(
              value: profile.enabled,
              onChanged: !_busy && profile.ready
                  ? (value) => _changeProfile(profile.withEnabled(value))
                  : null,
              title: Text(l10n.pick(
                  he: 'הפעל פקודות במסך הטיימר',
                  en: 'Enable on the timer screen')),
            ),
            TextButton(
              onPressed: !_busy &&
                      profile.samples.values
                          .any((samples) => samples.isNotEmpty)
                  ? () => _changeProfile(VoiceCommandProfile.empty)
                  : null,
              child: Text(l10n.pick(
                  he: 'מחק את דוגמאות הקול', en: 'Delete voice samples')),
            ),
          ],
        ],
      ),
    );
  }
}
