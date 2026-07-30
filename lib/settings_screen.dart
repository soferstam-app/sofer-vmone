import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backup_service.dart';
import 'hebrew_utils.dart';
import 'logic/hebrew_clock.dart';
import 'logic/hebrew_work_calendar.dart';
import 'platform_support.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'work_calendar_settings_screen.dart';
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
  DayStart _dayStart = DayStart.midnight;
  WorkCalendarRules _workRules = WorkCalendarRules.standard;
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
    final dayStart = await _storage.getDayStart();
    final workRules = await _storage.getWorkCalendarRules();
    final useGregorian = await _storage.getUseGregorianDates();
    final soferName = await _storage.getSoferName();
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _notificationTime = time;
        _smartWorkflowEnabled = smart;
        _dayStart = dayStart;
        _workRules = workRules;
        _useGregorianDates = useGregorian;
        _soferName = soferName;
      });
    }
  }

  /// A one-line read of the work-day rules, so the setting is legible without
  /// opening it.
  String get _workCalendarSummary {
    String weight(String name, DayWeight w) => switch (w) {
          DayWeight.full => "$name יום מלא",
          DayWeight.half => "$name חצי יום",
          DayWeight.none => "$name חופש",
        };

    final fastsOff = [
      _workRules.fastSeventeenTammuz,
      _workRules.fastGedalya,
      _workRules.fastTenthTevet,
      _workRules.fastEsther,
    ].where((w) => w != DayWeight.full).length;

    final parts = <String>[
      weight("שישי", _workRules.friday),
      if (_workRules.motzeiShabbat == DayWeight.half) "מוצ״ש חצי יום",
      if (_workRules.chanukah != DayWeight.full)
        weight("חנוכה", _workRules.chanukah),
      if (fastsOff > 0) "$fastsOff צומות",
    ];
    return "${parts.join(" · ")} — משפיע על כל צפי סיום";
  }

  String get _dayStartSummary => switch (_dayStart.boundary) {
        DayBoundary.midnight => "יום חדש מתחיל בחצות (00:00)",
        DayBoundary.sunset => "יום חדש מתחיל בשקיעה — לפי ממוצע ארץ ישראל",
        DayBoundary.nightfall =>
          "יום חדש מתחיל בצאת הכוכבים — לפי ממוצע ארץ ישראל",
        DayBoundary.fixedHour =>
          "יום חדש מתחיל ב-${_dayStart.hour.toString().padLeft(2, '0')}:00",
      };

  /// Boundary choice plus, for a fixed hour, which hour.
  ///
  /// The hour picker only appears for the fixed-hour option, since it means
  /// nothing for the other three.
  Future<void> _pickDayStart() async {
    final result = await showDialog<DayStart>(
      context: context,
      builder: (ctx) {
        var draft = _dayStart;
        return AlertDialog(
          title: const Text("מעבר יום"),
          content: StatefulBuilder(
            builder: (ctx, setDialog) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioGroup<DayBoundary>(
                    groupValue: draft.boundary,
                    onChanged: (v) => v == null
                        ? null
                        : setDialog(() => draft = draft.copyWith(boundary: v)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final option in DayBoundary.values)
                          RadioListTile<DayBoundary>(
                            value: option,
                            title: Text(option.label),
                            subtitle: Text(option.explanation,
                                style: const TextStyle(fontSize: 12)),
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  if (draft.boundary == DayBoundary.fixedHour)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DropdownButton<int>(
                        value: draft.hour,
                        isExpanded: true,
                        items: List.generate(
                          24,
                          (i) => DropdownMenuItem(
                            value: i,
                            child:
                                Text("${i.toString().padLeft(2, '0')}:00"),
                          ),
                        ),
                        onChanged: (v) => v == null
                            ? null
                            : setDialog(() => draft = draft.copyWith(hour: v)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("ביטול")),
            TextButton(
                onPressed: () => Navigator.pop(ctx, draft),
                child: const Text("אישור")),
          ],
        );
      },
    );

    if (result == null) return;
    await _storage.setDayStart(result);
    if (mounted) setState(() => _dayStart = result);
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

  /// Reads a backup file, shows what it holds, and merges it once confirmed.
  Future<void> _importBackup() async {
    setState(() => _isExporting = true);
    final read = await BackupService.instance.readBackupFile();
    if (!mounted) return;
    setState(() => _isExporting = false);

    if (!read.isOk) {
      final message = switch (read.error!) {
        BackupReadError.cancelled => null,
        BackupReadError.unreadable => "לא ניתן לקרוא את הקובץ",
        BackupReadError.notOurFormat =>
          "הקובץ אינו קובץ גיבוי של סופר ומונה",
        BackupReadError.tooNew =>
          "הקובץ נוצר בגרסה חדשה יותר של האפליקציה. יש לעדכן את האפליקציה כדי לשחזר אותו.",
      };
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final p = read.preview!;
    final exported = p.exportedAt == null
        ? "לא ידוע"
        : formatDisplayDate(p.exportedAt!, _useGregorianDates);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("שחזור מגיבוי"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.fileName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text("נוצר בתאריך: $exported",
                style: const TextStyle(fontSize: 13)),
            const Divider(height: 20),
            Text("פרויקטים בקובץ: ${p.projects.length}"),
            Text("רשומות עבודה: ${p.history.length}"),
            Text("הוצאות: ${p.expenses.length}"),
            const SizedBox(height: 14),
            const Text(
              "הנתונים יאוחדו עם הקיימים במכשיר. רשומה שקיימת בשניהם תישמר "
              "בגרסה שנערכה לאחרונה. שום דבר מהמכשיר לא יימחק.",
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("ביטול")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("שחזר")),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isExporting = true);
    final outcome = await BackupService.instance.applyBackup(p);
    if (!mounted) return;
    setState(() => _isExporting = false);

    final summary = outcome.changedAnything
        ? "נוספו: ${outcome.projectStats.added} פרויקטים, "
            "${outcome.historyStats.added} רשומות, "
            "${outcome.expenseStats.added} הוצאות.\n"
            "עודכנו: ${outcome.projectStats.updated + outcome.historyStats.updated + outcome.expenseStats.updated} פריטים."
        : "כל הנתונים בקובץ כבר קיימים במכשיר – לא בוצע שינוי.";

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 8),
      ),
    );
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
            const Divider(),
            ListTile(
              leading:
                  const Icon(Icons.restore_page, color: Colors.deepPurple),
              title: const Text("שחזור מקובץ גיבוי"),
              subtitle: const Text(
                  "הנתונים מהקובץ יתווספו לקיימים – שום דבר לא נמחק"),
              onTap: () => Navigator.pop(ctx, 'import'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'import') {
      await _importBackup();
      return;
    }

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
    return Scaffold(
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
                          "תצוגה בלבד. החישוב — ימי עבודה, חגים וצפי סיום — "
                          "נעשה תמיד לפי הלוח העברי"),
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
                    ListTile(
                      title: const Text("ימי עבודה"),
                      subtitle: Text(_workCalendarSummary),
                      leading: const Icon(Icons.calendar_today,
                          color: Colors.deepPurple),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WorkCalendarSettingsScreen(),
                          ),
                        );
                        // The estimates on every other screen read these rules,
                        // so the summary here has to reflect a change made
                        // inside.
                        await _loadNotificationSettings();
                      },
                    ),
                    ListTile(
                      title: const Text("מעבר יום"),
                      subtitle: Text(_dayStartSummary),
                      leading:
                          const Icon(Icons.schedule, color: Colors.deepPurple),
                      onTap: _pickDayStart,
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
