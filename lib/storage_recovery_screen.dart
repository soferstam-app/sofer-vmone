import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'backup_service.dart';
import 'platform_support.dart';
import 'storage_service.dart';

/// Works without loading preferences: a damaged journal must not prevent the
/// user from exporting the original bytes or selecting a known-good backup.
class StorageRecoveryScreen extends StatefulWidget {
  final Future<void> Function() onRetry;
  final bool english;
  const StorageRecoveryScreen(
      {super.key, required this.onRetry, required this.english});

  @override
  State<StorageRecoveryScreen> createState() => _StorageRecoveryScreenState();
}

class _StorageRecoveryScreenState extends State<StorageRecoveryScreen> {
  bool _busy = false;
  bool _savedExternalCopy = false;
  String? _message;
  bool get _english => widget.english;
  String _text(String he, String en) => _english ? en : he;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _message = _text(
              'הפעולה לא הושלמה. הנתונים המקוריים נשמרו. אפשר לנסות שוב.',
              'The operation did not complete. Original data is retained. You can retry.',
            ));
      }
      debugPrint('Storage recovery failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final data = await StorageService().exportRecoveryData();
    final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: _text('שמירת עותק לחילוץ נתונים', 'Save recovery copy'),
      fileName:
          'sofer-vmone-recovery-${DateTime.now().millisecondsSinceEpoch}.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: PlatformSupport.isMobile ? bytes : null,
    );
    if (path == null) return;
    if (!PlatformSupport.isMobile) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    if (mounted) {
      setState(() {
        _savedExternalCopy = true;
        _message = _text(
          'עותק החילוץ נשמר. הוא מכיל גם את הנתונים שאינם ניתנים לקריאה.',
          'Recovery copy saved, including data this version cannot read.',
        );
      });
    }
  }

  Future<void> _restore() async {
    // Keep a user-accessible copy as well as the local archive, so newer work
    // remains available after the recovery screen has closed.
    if (!_savedExternalCopy) await _export();
    if (!_savedExternalCopy || !mounted) return;
    final read = await BackupService.instance.readBackupFile(english: _english);
    if (read.error == BackupReadError.cancelled || !mounted) return;
    final backup = read.preview;
    if (backup == null ||
        backup.unreadable > 0 ||
        (backup.projects.isEmpty && backup.history.isEmpty)) {
      setState(() => _message = _text(
            'הקובץ אינו גיבוי כתיבה מלא וקריא. בחר גיבוי אחר; נתוני האפליקציה לא שונו.',
            'This file is not a fully readable writing backup. Choose another file; app data was not changed.',
          ));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(_text('שחזור נתוני הכתיבה', 'Restore writing data')),
        content: Text(_text(
          'הקובץ: ${backup.fileName}\n'
              '${backup.projects.length} פרויקטים, ${backup.history.length} רשומות כתיבה.\n\n'
              'הפרויקטים, ההיסטוריה ומיקומי הכתיבה יוחלפו בעותק שבקובץ. '
              'לפני כן יישמר במכשיר עותק חילוץ של כל הנתונים הנוכחיים, כולל ישיבה פתוחה ויומן השחזור הפגום. '
              'ישיבה פתוחה לא תופעל מחדש אוטומטית אחרי השחזור. הוצאות, תשלומים והזמנות יישארו כפי שהם. '
              'עבודה חדשה יותר מהגיבוי תהיה בעותק החילוץ ותדרוש בדיקה.',
          'File: ${backup.fileName}\n'
              '${backup.projects.length} projects, ${backup.history.length} writing records.\n\n'
              'Projects, history and writing positions will be replaced with this backup. '
              'A local recovery copy of all current data, including the open sitting and damaged journal, will be saved first. '
              'An open sitting will not resume automatically. Expenses, payments and orders will remain unchanged. '
              'Work newer than the backup will remain in the recovery copy for review.',
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_text('ביטול', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  Text(_text('שמור עותק ושחזר', 'Preserve copy and restore'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await StorageService().recoverWorkFromBackup(
      projects: backup.projects,
      history: backup.history,
      lastPositions: backup.lastPositions,
    );
    await widget.onRetry();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: _english ? TextDirection.ltr : TextDirection.rtl,
        child: Scaffold(
          appBar:
              AppBar(title: Text(_text('התאוששות נתונים', 'Data recovery'))),
          body: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                      _text('לא ניתן להשלים את שחזור נתוני הכתיבה',
                          'Writing data recovery could not complete'),
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(_text(
                    'הנתונים לא אופסו. כדי להימנע משמירת עבודה חלקית, הכתיבה נעצרה עד להתאוששות. '
                        'לפני שחזור תתבקש לשמור עותק לחילוץ ולבחור גיבוי תקין. אם אין גיבוי, שמור את העותק לצורך סיוע; אין צורך למחוק את נתוני האפליקציה. '
                        'עותק חילוץ הוא קובץ נפרד מגיבוי רגיל ומכיל נתונים אישיים.',
                    'Your data has not been reset. Writing is blocked until recovery to avoid saving an inconsistent state. '
                        'Before restoring, you will be asked to save a recovery copy and select a valid backup. If you have no backup, keep the recovery copy for assistance; do not clear app data. '
                        'A recovery copy is separate from a normal backup and contains personal data.',
                  )),
                  const SizedBox(height: 20),
                  OutlinedButton(
                      onPressed: _busy ? null : () => _run(_export),
                      child: Text(
                          _text('שמירת עותק לחילוץ', 'Save recovery copy'))),
                  FilledButton(
                      onPressed: _busy ? null : () => _run(_restore),
                      child: Text(_text('בחירת גיבוי לשחזור הכתיבה',
                          'Select writing backup'))),
                  TextButton(
                      onPressed: _busy ? null : () => _run(widget.onRetry),
                      child: Text(_text('ניסיון טעינה נוסף', 'Retry loading'))),
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_message!)),
                ]),
          )),
        ),
      );
}
