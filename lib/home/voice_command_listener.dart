import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../logic/voice_commands.dart';
import '../logic/voice_microphone.dart';
import '../logic/voice_recognition.dart';

enum VoiceTimerMode {
  idle,
  paused,
  writing,
  writingByWord;

  bool allows(VoiceCommand command) => switch (command) {
        VoiceCommand.start => this == idle || this == paused,
        VoiceCommand.line => this == writing,
        VoiceCommand.takeBreak => this == writing || this == writingByWord,
      };
}

/// Owns the microphone only while the timer screen can use voice commands.
class VoiceCommandListener extends StatefulWidget {
  const VoiceCommandListener({
    super.key,
    required this.profile,
    required this.mode,
    required this.projectId,
    required this.onCommand,
    required this.onMicrophoneError,
    required this.child,
  });

  final VoiceCommandProfile profile;
  final VoiceTimerMode? mode;
  final String? projectId;
  final Future<void> Function(VoiceCommand) onCommand;
  final VoidCallback onMicrophoneError;
  final Widget child;

  @override
  State<VoiceCommandListener> createState() => _VoiceCommandListenerState();
}

class _VoiceCommandListenerState extends State<VoiceCommandListener>
    with WidgetsBindingObserver {
  final _microphone = VoiceMicrophone();
  VoiceSegments _segments = VoiceSegments();
  late bool _foreground;
  bool _wanted = false;
  bool _failed = false;
  int _captureVersion = 0;
  int _phraseVersion = 0;
  bool _processing = false;
  StreamSubscription<Uint8List>? _subscription;
  Future<void> _pending = Future<void>.value();

  bool _canListen(AppLifecycleState? state) =>
      state == null ||
      state == AppLifecycleState.resumed ||
      (defaultTargetPlatform == TargetPlatform.windows &&
          state == AppLifecycleState.inactive);

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    final lifecycle = binding.lifecycleState;
    _foreground = _canListen(lifecycle);
    binding.addObserver(this);
    _updateCapture();
  }

  @override
  void didUpdateWidget(VoiceCommandListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode ||
        widget.projectId != oldWidget.projectId ||
        widget.profile != oldWidget.profile) {
      _phraseVersion++;
      _segments = VoiceSegments();
    }
    _updateCapture();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _canListen(state);
    _updateCapture();
  }

  void _updateCapture() {
    final eligible =
        _foreground && widget.profile.enabled && widget.mode != null;
    if (!eligible) _failed = false;
    _setCapture(eligible && !_failed);
  }

  void _setCapture(bool wanted) {
    if (wanted == _wanted) return;
    _wanted = wanted;
    _phraseVersion++;
    _segments = VoiceSegments();
    final version = ++_captureVersion;
    _pending = _pending.then((_) async {
      try {
        await _subscription?.cancel();
        _subscription = null;
        await _microphone.close();
        if (!wanted || version != _captureVersion || !mounted) return;
        final granted = await _microphone.hasPermission(request: false);
        if (version != _captureVersion || !mounted) return;
        if (!granted) {
          _captureFailed(version);
          return;
        }
        final stream = await _microphone.open();
        if (version != _captureVersion || !mounted) return;
        _subscription = stream.listen(
          (chunk) {
            if (version != _captureVersion) return;
            for (final phrase in _segments.add(chunk)) {
              unawaited(_recognize(phrase));
            }
          },
          onError: (Object _) => _captureFailed(version),
          onDone: () => _captureFailed(version),
        );
      } catch (_) {
        _captureFailed(version);
      }
    });
  }

  void _captureFailed(int version) {
    if (version != _captureVersion || !mounted) return;
    _failed = true;
    _setCapture(false);
    widget.onMicrophoneError();
  }

  Future<void> _recognize(Int16List phrase) async {
    if (_processing) return;
    _processing = true;
    final version = _phraseVersion;
    try {
      final recognized = await recognizeVoiceCommand(widget.profile, phrase);
      if (!mounted || !_wanted || version != _phraseVersion) return;
      final command = recognized?.command;
      if (command != null && widget.mode?.allows(command) == true) {
        await widget.onCommand(command);
        _segments = VoiceSegments();
      }
    } catch (error) {
      debugPrint('Voice command failed: $error');
    } finally {
      _processing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setCapture(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
