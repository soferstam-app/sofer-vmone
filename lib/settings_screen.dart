import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backup_service.dart';
import 'platform_support.dart';
import 'sync_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'package:auto_updater/auto_updater.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  TimeOfDay _notificationTime = const TimeOfDay(hour: 20, minute: 0);
  bool _smartWorkflowEnabled = false;
  int _dayRolloverHour = 0;
  bool _fridayMotzeiHalfDay = false;
  bool _useGregorianDates = false;
  bool _isExporting = false;
  String _soferName = '';
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final enabled = await _storage.getNotificationEnabled();
    final time = await _storage.getNotificationTime();
    final smart = await _storage.getSmartWorkflowEnabled();
    final rollover = await _storage.getDayRolloverHour();
    final fridayHalf = await _storage.getFridayMotzeiHalfDay();
    final useGregorian = await _storage.getUseGregorianDates();
    final soferName = await _storage.getSoferName();
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _notificationTime = time;
        _smartWorkflowEnabled = smart;
        _dayRolloverHour = rollover;
        _fridayMotzeiHalfDay = fridayHalf;
        _useGregorianDates = useGregorian;
        _soferName = soferName;
      });
    }
  }

  Future<void> _updateNotificationSettings(bool enabled) async {
    if (mounted) {
      setState(() => _notificationsEnabled = enabled);
    }
    await _storage.setNotificationEnabled(enabled);
    await NotificationService().scheduleDailyReminder();
  }

  Future<void> _updateSmartWorkflow(bool enabled) async {
    if (mounted) {
      setState(() => _smartWorkflowEnabled = enabled);
    }
    await _storage.setSmartWorkflowEnabled(enabled);
  }

  Future<void> _pickNotificationTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _notificationTime,
    );
    if (picked != null && picked != _notificationTime) {
      if (mounted) {
        setState(() => _notificationTime = picked);
      }
      await _storage.setNotificationTime(picked);
      await NotificationService().scheduleDailyReminder();
    }
  }

  Future<void> _checkForUpdates() async {
    // URL for the GitHub releases page.
    String feedURL = 'https://github.com/soferstam-app/sofer-vmone/releases';
    await autoUpdater.setFeedURL(feedURL);
    await autoUpdater.checkForUpdates();
  }

  Future<void> _handleSignIn() async {
    try {
      await SyncService.instance.signIn();
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      debugPrint("Sign in error: $error");
      String errorMessage = "שגיאה בהתחברות: $error";
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    await SyncService.instance.signOut();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _forceSync() async {
    if (!SyncService.instance.isSignedIn) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("מבצע סנכרון...")),
    );

    final status = await SyncService.instance.syncData();
    if (!mounted) return;
    setState(() {});

    switch (status) {
      case SyncStatus.success:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("הסנכרון הושלם בהצלחה!"),
            backgroundColor: Colors.green,
          ),
        );
      case SyncStatus.notSignedIn:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("יש להתחבר לחשבון Google תחילה")),
        );
      case SyncStatus.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "הסנכרון נכשל: ${SyncService.instance.lastSyncError ?? 'שגיאה לא ידועה'}"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }

  Future<void> _editSoferName() async {
    final ctrl = TextEditingController(text: _soferName);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("שם הסופר"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "השם שיופיע כחתימה בעדכוני ההתקדמות שנשלחים ללקוחות.",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "שם מלא",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text("שמור")),
        ],
      ),
    );
    ctrl.dispose();
    if (saved == null || !mounted) return;
    await _storage.setSoferName(saved);
    if (mounted) setState(() => _soferName = saved);
  }

  /// Lets the user choose between writing the backup to a location they pick
  /// and handing it to the OS share sheet. Both produce the same file.
  Future<void> _showBackupOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "גיבוי הנתונים",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, color: Colors.deepPurple),
              title: const Text("שמור במכשיר"),
              subtitle: Text(PlatformSupport.isDesktop
                  ? "בחירת תיקייה לשמירת הקובץ"
                  : "בחירת מיקום בזיכרון המכשיר"),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.deepPurple),
              title: const Text("שיתוף"),
              subtitle: const Text(
                  "שליחה לוואטסאפ, מייל, או כל אפליקציה אחרת במכשיר"),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    setState(() => _isExporting = true);
    final result = choice == 'save'
        ? await BackupService.instance.saveToDevice()
        : await BackupService.instance.shareBackup();
    if (!mounted) return;
    setState(() => _isExporting = false);

    switch (result.outcome) {
      case BackupOutcome.success:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(choice == 'save' && result.path != null
                ? "הגיבוי נשמר:\n${result.path}"
                : "הגיבוי נוצר בהצלחה"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
          ),
        );
      case BackupOutcome.cancelled:
        break;
      case BackupOutcome.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text("הגיבוי נכשל: ${result.error ?? 'שגיאה לא ידועה'}"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("אודות"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('שם האפליקציה: סופר ומונה'),
              const Text('גרסה: 0.3.0'),
              const SizedBox(height: 12),
              const Text('אתר האפליקציה:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              InkWell(
                child: const Text(
                  'https://soferstam-app.github.io/sofer-vmone/',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
                onTap: () => launchUrl(
                    Uri.parse('https://soferstam-app.github.io/sofer-vmone/')),
              ),
              const SizedBox(height: 8),
              const Text('גיטהאב:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              InkWell(
                child: const Text(
                  'https://github.com/soferstam-app/sofer-vmone',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
                onTap: () => launchUrl(
                    Uri.parse('https://github.com/soferstam-app/sofer-vmone')),
              ),
              const SizedBox(height: 16),
              const Text(
                'עלויות בניית האפליקציה והתחזוקה שלה הן רבות. למי שמעוניין לתמוך בפיתוח האפליקציה ובפרויקטים עתידיים – אפשר לתרום דרך הקישור הבא. תודה!',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              InkWell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.coffee, size: 20, color: Colors.brown.shade700),
                    const SizedBox(width: 6),
                    const Text(
                      'https://buymeacoffee.com/soferstam',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
                onTap: () =>
                    launchUrl(Uri.parse('https://buymeacoffee.com/soferstam')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("סגור"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isSignedIn = SyncService.instance.isSignedIn;
    final String displayName = SyncService.instance.userEmail;

    return Scaffold(
      persistentFooterButtons: [
        !isSignedIn
            ? ElevatedButton(
                onPressed: _handleSignIn,
                child: const Text("Sign In Google"),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(displayName),
                  if (SyncService.instance.lastSyncTime != null)
                    Text(
                      "סונכרן לאחרונה: ${TimeOfDay.fromDateTime(SyncService.instance.lastSyncTime!).format(context)}",
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ElevatedButton(
                    onPressed: _handleSignOut,
                    child: const Text("Sign Out Google"),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _forceSync,
                        child: const Text("סנכרון ידני"),
                      ),
                    ],
                  ),
                ],
              )
      ],
      appBar: AppBar(
        title: const Text("הגדרות"),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: "אודות",
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Card(
                margin: const EdgeInsets.all(10),
                elevation: 2,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text("התראות יומיות"),
                      subtitle: const Text("תזכורת יומית לעמידה ביעדי הכתיבה"),
                      value: _notificationsEnabled,
                      onChanged: _updateNotificationSettings,
                      secondary: const Icon(Icons.notifications_active,
                          color: Colors.deepPurple),
                    ),
                    if (_notificationsEnabled)
                      ListTile(
                        title: const Text("שעת תזכורת"),
                        subtitle: Text(_notificationTime.format(context)),
                        leading: const Icon(Icons.access_time,
                            color: Colors.deepPurple),
                        onTap: _pickNotificationTime,
                      ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text("תאריכים לועזיים"),
                      subtitle: const Text(
                          "הצגת כל התאריכים בתאריך לועזי (יום.חודש.שנה) במקום עברי"),
                      value: _useGregorianDates,
                      onChanged: (v) async {
                        await _storage.setUseGregorianDates(v);
                        if (mounted) setState(() => _useGregorianDates = v);
                      },
                      secondary: const Icon(Icons.calendar_month,
                          color: Colors.deepPurple),
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text("זרימת עבודה חכמה"),
                      subtitle: const Text("ממשק כתיבה בזמן אמת (כניסה/יציאה)"),
                      value: _smartWorkflowEnabled,
                      onChanged: _updateSmartWorkflow,
                      secondary:
                          const Icon(Icons.speed, color: Colors.deepPurple),
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text("ימי שישי ומוצאי שבת כחצי יום"),
                      subtitle: const Text(
                          "בחישוב ימי עבודה: שישי ומוצאי שבת נספרים כחצי יום כל אחד"),
                      value: _fridayMotzeiHalfDay,
                      onChanged: (v) async {
                        await _storage.setFridayMotzeiHalfDay(v);
                        if (mounted) setState(() => _fridayMotzeiHalfDay = v);
                      },
                      secondary: const Icon(Icons.calendar_today,
                          color: Colors.deepPurple),
                    ),
                    ListTile(
                      title: const Text("שעת מעבר יום"),
                      subtitle: Text(
                          "יום חדש מתחיל ב-${_dayRolloverHour.toString().padLeft(2, '0')}:00 (לטובת סופרים שמסיימים מאוחר)"),
                      leading:
                          const Icon(Icons.schedule, color: Colors.deepPurple),
                      onTap: () async {
                        final h = await showDialog<int>(
                          context: context,
                          builder: (ctx) {
                            int sel = _dayRolloverHour;
                            return AlertDialog(
                              title: const Text("שעת מעבר יום"),
                              content: StatefulBuilder(
                                builder: (ctx, setDialog) {
                                  return DropdownButton<int>(
                                    value: sel,
                                    isExpanded: true,
                                    items: List.generate(25, (i) {
                                      return DropdownMenuItem(
                                          value: i,
                                          child: Text(
                                              "${i.toString().padLeft(2, '0')}:00"));
                                    }),
                                    onChanged: (v) {
                                      if (v != null) {
                                        setDialog(() => sel = v);
                                      }
                                    },
                                  );
                                },
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("ביטול")),
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, sel),
                                    child: const Text("אישור")),
                              ],
                            );
                          },
                        );
                        if (h != null) {
                          await _storage.setDayRolloverHour(h);
                          if (mounted) setState(() => _dayRolloverHour = h);
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text("שם הסופר"),
                      subtitle: Text(_soferName.isEmpty
                          ? "לחתימה בעדכונים ללקוחות (לא הוגדר)"
                          : _soferName),
                      leading: const Icon(Icons.badge,
                          color: Colors.deepPurple),
                      onTap: _editSoferName,
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text("גיבוי הנתונים"),
                      subtitle: const Text(
                          "ייצוא כל הנתונים לקובץ אחד – פרויקטים, היסטוריה, הוצאות והגדרות"),
                      leading: const Icon(Icons.backup,
                          color: Colors.deepPurple),
                      trailing: _isExporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_left),
                      onTap: _isExporting ? null : _showBackupOptions,
                    ),
                    if (Platform.isWindows || Platform.isMacOS)
                      ListTile(
                        title: const Text("בדוק עדכונים"),
                        leading:
                            const Icon(Icons.update, color: Colors.deepPurple),
                        onTap: _checkForUpdates,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
