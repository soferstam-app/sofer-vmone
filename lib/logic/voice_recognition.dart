import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sofer_voice_model/sofer_voice_model.dart';

import 'voice_commands.dart';

export 'package:sofer_voice_model/sofer_voice_model.dart'
    show voiceModelIncluded;

typedef RecognizedVoiceCommand = ({VoiceCommand command, bool fromModel});

final class VoiceModelUnavailable implements Exception {
  const VoiceModelUnavailable(this.cause);

  final Object cause;
}

Future<RecognizedVoiceCommand?> recognizeVoiceCommand(
  VoiceCommandProfile profile,
  Int16List pcm,
) async {
  if (profile.ready) {
    final command = await compute(matchVoiceCommand, (profile, pcm));
    if (command != null) return (command: command, fromModel: false);
  }
  if (!voiceModelIncluded) return null;
  final String transcript;
  try {
    transcript = await transcribeVoiceCommand(pcm);
  } catch (error) {
    throw VoiceModelUnavailable(error);
  }
  final command = voiceCommandFromTranscript(transcript);
  return command == null ? null : (command: command, fromModel: true);
}

VoiceCommand? voiceCommandFromTranscript(String transcript) {
  final words = transcript
      .replaceAll(RegExp(r'[\u0591-\u05BD\u05BF-\u05C2\u05C4-\u05C7]'), '')
      .trim()
      .replaceFirst(RegExp(r'[.!?…]+$'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (words == 'סימתי שורה' ||
      words == 'סיימתי את השורה' ||
      words == 'סיום שורה') {
    return VoiceCommand.line;
  }
  for (final command in VoiceCommand.values) {
    if (words == command.phrase) return command;
  }
  return null;
}
