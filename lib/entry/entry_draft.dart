import 'package:flutter/material.dart';

/// A form that has not yet crossed the durable-history boundary.
///
/// This is deliberately device-local and transient. It exists only so a
/// stopped timer, a rejected field, or a storage error cannot turn closing the
/// app into lost work. It is removed after history is durably written or after
/// the writer explicitly discards the form.
class EntryDraft {
  final String projectId;
  final String entryId;
  final bool isManual;
  final Duration measuredTime;
  final DateTime? measuredEnd;
  final DateTime? date;
  final bool includeTime;
  final bool byDuration;
  final Duration worked;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String pageFrom;
  final String pageTo;
  final String lineFrom;
  final String lineTo;
  final String amount;
  final String partialLine;
  final int? mezuzaIndex;
  final String tefillinMode;
  final String tefillinPart;
  final int tefillinParshiya;
  final String tefillinPair;
  final bool tefillinWords;
  final int? tefillinUntilWord;
  final int? tefillinBaselineWord;
  final String? tefillinScript;

  const EntryDraft({
    required this.projectId,
    required this.entryId,
    required this.isManual,
    this.measuredTime = Duration.zero,
    this.measuredEnd,
    this.date,
    this.includeTime = true,
    this.byDuration = true,
    this.worked = const Duration(hours: 1),
    this.startTime = const TimeOfDay(hour: 9, minute: 0),
    this.endTime = const TimeOfDay(hour: 10, minute: 0),
    this.pageFrom = '',
    this.pageTo = '',
    this.lineFrom = '',
    this.lineTo = '',
    this.amount = '',
    this.partialLine = '',
    this.mezuzaIndex,
    this.tefillinMode = 'set',
    this.tefillinPart = 'head',
    this.tefillinParshiya = 1,
    this.tefillinPair = '',
    this.tefillinWords = false,
    this.tefillinUntilWord,
    this.tefillinBaselineWord,
    this.tefillinScript,
  });

  factory EntryDraft.timed({
    required String projectId,
    required String entryId,
    required Duration measuredTime,
    required DateTime measuredEnd,
  }) =>
      EntryDraft(
        projectId: projectId,
        entryId: entryId,
        isManual: false,
        measuredTime: measuredTime,
        measuredEnd: measuredEnd,
      );

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'entryId': entryId,
        'isManual': isManual,
        'measuredTimeMs': measuredTime.inMilliseconds,
        'measuredEnd': measuredEnd?.toIso8601String(),
        'date': date?.toIso8601String(),
        'includeTime': includeTime,
        'byDuration': byDuration,
        'workedMs': worked.inMilliseconds,
        'startMinutes': startTime.hour * 60 + startTime.minute,
        'endMinutes': endTime.hour * 60 + endTime.minute,
        'pageFrom': pageFrom,
        'pageTo': pageTo,
        'lineFrom': lineFrom,
        'lineTo': lineTo,
        'amount': amount,
        'partialLine': partialLine,
        'mezuzaIndex': mezuzaIndex,
        'tefillinMode': tefillinMode,
        'tefillinPart': tefillinPart,
        'tefillinParshiya': tefillinParshiya,
        'tefillinPair': tefillinPair,
        'tefillinWords': tefillinWords,
        'tefillinUntilWord': tefillinUntilWord,
        'tefillinBaselineWord': tefillinBaselineWord,
        'tefillinScript': tefillinScript,
      };

  factory EntryDraft.fromJson(Map<String, dynamic> json) {
    int number(String key, int fallback) => switch (json[key]) {
          final num value => value.toInt(),
          _ => fallback,
        };
    String text(String key, [String fallback = '']) => switch (json[key]) {
          final String value => value,
          _ => fallback,
        };
    DateTime? dateValue(String key) => switch (json[key]) {
          final String value => DateTime.tryParse(value),
          _ => null,
        };
    TimeOfDay clock(String key, int fallback) {
      final minutes = number(key, fallback).clamp(0, 24 * 60 - 1);
      return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    }

    final projectId = text('projectId');
    final entryId = text('entryId');
    if (projectId.isEmpty || entryId.isEmpty) {
      throw const FormatException('pending entry without an identity');
    }
    final mode = text('tefillinMode', 'set');
    final part = text('tefillinPart', 'head');
    return EntryDraft(
      projectId: projectId,
      entryId: entryId,
      isManual: json['isManual'] == true,
      measuredTime:
          Duration(milliseconds: number('measuredTimeMs', 0).clamp(0, 1 << 53)),
      measuredEnd: dateValue('measuredEnd'),
      date: dateValue('date'),
      includeTime: json['includeTime'] != false,
      byDuration: json['byDuration'] != false,
      worked: Duration(
          milliseconds: number('workedMs', 60 * 60 * 1000)
              .clamp(0, 7 * 24 * 60 * 60 * 1000)),
      startTime: clock('startMinutes', 9 * 60),
      endTime: clock('endMinutes', 10 * 60),
      pageFrom: text('pageFrom'),
      pageTo: text('pageTo'),
      lineFrom: text('lineFrom'),
      lineTo: text('lineTo'),
      amount: text('amount'),
      partialLine: text('partialLine'),
      mezuzaIndex: switch (json['mezuzaIndex']) {
        final num value when value >= 1 => value.toInt(),
        _ => null,
      },
      tefillinMode: const {'set', 'head', 'hand', 'parshiya'}.contains(mode)
          ? mode
          : 'set',
      tefillinPart: const {'head', 'hand'}.contains(part) ? part : 'head',
      tefillinParshiya: number('tefillinParshiya', 1).clamp(1, 4),
      tefillinPair: text('tefillinPair'),
      tefillinWords: json['tefillinWords'] == true,
      tefillinUntilWord: json['tefillinUntilWord'] is int
          ? json['tefillinUntilWord'] as int
          : null,
      tefillinBaselineWord: json['tefillinBaselineWord'] is int
          ? json['tefillinBaselineWord'] as int
          : null,
      tefillinScript: json['tefillinScript'] is String
          ? json['tefillinScript'] as String
          : null,
    );
  }
}
