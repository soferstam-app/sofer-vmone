import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _notificationTime = time;
        _smartWorkflowEnabled = smart;
        _dayRolloverHour = rollover;
        _fridayMotzeiHalfDay = fridayHalf;
        _useGregorianDates = useGregorian;
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

    try {
      await SyncService.instance.syncData();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("הסנכרון הושלם בהצלחה!")),
        );
      }
    } catch (e) {
      debugPrint("Sync error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("שגיאה בסנכרון: $e")),
        );
      }
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
