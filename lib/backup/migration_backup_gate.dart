import 'package:flutter/material.dart';

import '../backup_service.dart';
import '../l10n/app_localizations.dart';
import '../logic/demo_data.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';

/// Kept independent of the app version: every installation of the transition
/// build must be covered, including users who already ran 0.6.0 and new users.
/// Disable this gate in the destination build after the signing migration.
const externalBackupMigrationEnabled = true;

class MigrationBackupGate extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final BackupService? backupService;
  const MigrationBackupGate({
    super.key,
    required this.child,
    this.enabled = externalBackupMigrationEnabled,
    this.backupService,
  });

  @override
  State<MigrationBackupGate> createState() => _MigrationBackupGateState();
}

class _MigrationBackupGateState extends State<MigrationBackupGate> {
  bool _ready = false;
  bool _checking = true;
  BackupService get _backup => widget.backupService ?? BackupService.instance;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled || DemoData.enabled) {
      _ready = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkBackup());
    }
  }

  Future<void> _checkBackup() async {
    String? folder;
    var failed = false;
    try {
      folder = await StorageService().getAutoBackupFolder();
      if (folder != null) {
        // A remembered path or an old success timestamp is not proof that the
        // destination is still accessible. Verify an actual current snapshot.
        final saved = await _backup.writeAutoBackup();
        if (!mounted) return;
        if (saved) {
          setState(() => _ready = true);
          return;
        }
        failed = true;
      }
    } catch (error) {
      debugPrint('Could not verify migration backup: $error');
      failed = true;
    }
    if (!mounted) return;
    setState(() => _checking = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MigrationBackupDialog(
          folder: folder, failed: failed, backup: _backup),
    );
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) => _ready
      ? widget.child
      : Scaffold(
          backgroundColor: SoferTokens.of(context).paper,
          body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_checking) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(context.l10n.pick(
                  he: 'בודק גיבוי חיצוני לקראת המעבר',
                  en: 'Checking external backup before the migration')),
            ]),
          ),
        );
}

class _MigrationBackupDialog extends StatefulWidget {
  final BackupService backup;
  final String? folder;
  final bool failed;
  const _MigrationBackupDialog(
      {this.folder, required this.failed, required this.backup});

  @override
  State<_MigrationBackupDialog> createState() => _MigrationBackupDialogState();
}

class _MigrationBackupDialogState extends State<_MigrationBackupDialog> {
  final _storage = StorageService();
  bool _busy = false;
  late String? _folder = widget.folder;
  late bool _failed = widget.failed;
  bool _cancelled = false;

  Future<void> _save({required bool pickFolder}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _cancelled = false;
    });
    try {
      if (pickFolder) {
        final folder = await widget.backup.pickAutoBackupFolder(
            title: context.l10n.pick(
                he: 'בחירת תיקייה חיצונית לגיבוי הנתונים',
                en: 'Choose an external folder for your backup'));
        if (!mounted) return;
        if (folder == null || folder.trim().isEmpty) {
          setState(() => _cancelled = true);
          return;
        }
        await _storage.setAutoBackupFolder(folder);
        if (!mounted) return;
        setState(() => _folder = folder);
      }
      final saved = _folder != null && await widget.backup.writeAutoBackup();
      if (!mounted) return;
      if (!saved) {
        setState(() => _failed = true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
        context.l10n.pick(
          he: 'הגיבוי החיצוני נכתב ואומת. הוא יתעדכן אחרי כל שמירה.',
          en: 'External backup written and verified. It will update after every save.',
        ),
      )));
      Navigator.pop(context);
    } catch (error) {
      debugPrint('Migration backup setup failed: $error');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          key: const ValueKey('backup-migration-dialog'),
          scrollable: true,
          title: Text(context.l10n.pick(
              he: 'גיבוי חיצוני לפני המעבר',
              en: 'External backup before migration')),
          content:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.l10n.pick(
              he: 'לקראת המעבר לגרסה עם חתימה קבועה, בחר תיקייה חיצונית שבה יישמרו נתוני הכתיבה, הפרויקטים, ההזמנות, התשלומים, ההוצאות, ההגהות וההגדרות. הקובץ יתעדכן אחרי כל שמירה.\n\n'
                  'בחר תיקיית מסמכים, תיקייה מסונכרנת או כונן נפרד שתוכל לפתוח גם מהאפליקציה החדשה. אין לבחור את תיקיית הנתונים הפרטית של האפליקציה.\n\n'
                  'אפשר להמשיך בלי להגדיר עכשיו; במקרה כזה נזכיר שוב בפתיחה הבאה. ניתן לנהל את הגיבוי בהגדרות.',
              en: 'Before moving to a version with permanent signing, choose an external folder for writing records, projects, orders, payments, expenses, proofreading and settings. The file will update after every save.\n\n'
                  'Choose a Documents folder, a synced folder or a separate drive that you can also open from the new app. Do not choose the app’s private data folder.\n\n'
                  'You can continue without setting this up now; we will remind you at the next launch. Manage backups in Settings.',
            )),
            if (_folder != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(context.l10n.pick(
                    he: 'התיקייה השמורה: $_folder',
                    en: 'Saved folder: $_folder')),
              ),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    widget.backup.autoBackupStatus.value['needsImport'] == true
                        ? context.l10n.pick(
                            he: 'בתיקייה כבר קיים גיבוי המכיל רשומות שאינן במכשיר הזה, או קובץ שאינו ניתן לאימות. כדי לשמור עליו, הוא לא הוחלף. אפשר לבחור „לא עכשיו” ולייבא אותו דרך ההגדרות, או לבחור תיקייה אחרת.',
                            en: 'This folder already contains a backup with records missing from this device, or a file that cannot be verified. It has not been replaced. Choose Not now and import it in Settings, or choose another folder.')
                        : context.l10n.pick(
                            he: 'לא נוצר גיבוי חיצוני מאומת. בדוק את התיקייה ואת הרשאת הכתיבה, ונסה שוב או בחר תיקייה אחרת. הנתונים המקומיים נשמרו.',
                            en: 'No verified external backup was created. Check the folder and write permission, then retry or choose another folder. Local data is retained.',
                          ),
                    style: TextStyle(color: SoferTokens.of(context).danger)),
              ),
            if (_cancelled)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(context.l10n.pick(
                  he: 'לא נבחרה תיקייה. הגיבוי עדיין לא הוגדר.',
                  en: 'No folder was selected. Backup has not been set up.',
                )),
              ),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator()),
          ]),
          actions: [
            TextButton(
              key: const ValueKey('backup-migration-defer'),
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(context.l10n.pick(he: 'לא עכשיו', en: 'Not now')),
            ),
            if (_folder != null)
              OutlinedButton(
                key: const ValueKey('backup-migration-retry'),
                onPressed: _busy ? null : () => _save(pickFolder: false),
                child: Text(context.l10n.pick(he: 'נסה שוב', en: 'Retry')),
              ),
            FilledButton(
              key: const ValueKey('backup-migration-choose'),
              onPressed: _busy ? null : () => _save(pickFolder: true),
              child: Text(context.l10n.pick(
                  he: _folder == null
                      ? 'בחירת תיקייה חיצונית'
                      : 'בחירת תיקייה אחרת',
                  en: _folder == null
                      ? 'Choose external folder'
                      : 'Choose another folder')),
            ),
          ],
        ),
      );
}
