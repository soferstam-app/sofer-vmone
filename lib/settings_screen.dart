import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backup_service.dart';
import 'hebrew_utils.dart';
import 'logic/hebrew_clock.dart';
import 'platform_support.dart';
import 'main.dart' show themeController;
import 'storage_service.dart';
import 'notification_service.dart';
import 'theme_settings_screen.dart';
import 'widgets/sofer_widgets.dart';
import 'work_calendar_settings_screen.dart';
import 'dart:io';
import 'theme/app_theme.dart';
import 'widgets/feedback.dart';
import 'logic/currency.dart';
import 'version.dart';
import 'update_service.dart';
import 'logic/version_check.dart';
import 'widgets/confirm.dart';
import 'package:file_picker/file_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;

  /// Whether the reminder follows the writer's own habits rather than the hour
  /// he named. Off until he asks — a reminder that moves on its own is a
  /// surprise, and a surprise from a reminder is never a good one.
  bool _smartReminder = false;
  TimeOfDay _notificationTime = const TimeOfDay(hour: 20, minute: 0);
  DayStart _dayStart = DayStart.midnight;
  bool _useGregorianDates = false;

  /// What the *next* amount is entered in. Every stored amount carries its own,
  /// so this settles nothing about what is already recorded.
  Currency _currency = Currency.ils;

  /// Every currency records are actually in. More than one means some figures
  /// cannot be added up, and the writer should hear that from the app rather
  /// than work it out from a total that looks wrong.
  Set<Currency> _inUse = const {};
  bool _isExporting = false;
  bool _checkingUpdate = false;

  /// Where a copy is left after every sitting, or null when the writer has not
  /// asked for one.
  String? _autoBackupFolder;
  String _soferName = '';

  /// Stored records this build cannot read. They are kept untouched and take no
  /// part in any figure, so the app has to say they are there rather than
  /// quietly reporting totals that are short.
  int _unreadable = 0;
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    final enabled = await _storage.getNotificationEnabled();
    final time = await _storage.getNotificationTime();
    final smartReminder = await _storage.getSmartReminder();
    final dayStart = await _storage.getDayStart();
    final useGregorian = await _storage.getUseGregorianDates();
    final soferName = await _storage.getSoferName();
    final unreadable = await _storage.unreadableRecordCount();
    final currency = await _storage.getCurrency();
    final inUse = await _storage.currenciesInUse();
    final autoFolder = await _storage.getAutoBackupFolder();
    if (mounted) {
      setState(() {
        _notificationsEnabled = enabled;
        _notificationTime = time;
        _smartReminder = smartReminder;
        _dayStart = dayStart;
        _useGregorianDates = useGregorian;
        _soferName = soferName;
        _unreadable = unreadable;
        _currency = currency;
        _inUse = inUse;
        _autoBackupFolder = autoFolder;
      });
    }
  }

  String get _themeSummary {
    final choice = themeController.choice.label;
    if (themeController.nightByClock) return "$choice · כרגע בערכת לילה";
    return themeController.autoNight
        ? "$choice · מעבר אוטומטי ללילה"
        : choice;
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

  /// Which currency new amounts are entered in.
  ///
  /// Deliberately says what it will not do. A writer changing this expects one
  /// of two things, and only one of them is true: it does not convert anything,
  /// and it does not relabel anything. What is already recorded keeps the
  /// currency it was entered in, for ever.
  Future<void> _pickCurrency() async {
    final chosen = await showDialog<Currency>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מטבע"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "המטבע שבו יוזנו סכומים חדשים.\n\n"
              "סכומים שכבר נרשמו נשארים במטבע שבו הוזנו — האפליקציה אינה "
              "ממירה ואינה משנה אותם למפרע.",
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            for (final option in Currency.offered)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text("${option.name} (${option.symbol})"),
                trailing: option == _currency
                    ? Icon(Icons.check, color: SoferTokens.of(ctx).accent)
                    : null,
                onTap: () => Navigator.pop(ctx, option),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ביטול")),
        ],
      ),
    );
    if (chosen == null) return;
    await _storage.setCurrency(chosen);
    if (mounted) setState(() => _currency = chosen);
  }

  /// What to say beside the setting: the currency, and a warning when the
  /// records are not all in it.
  String get _currencyNote {
    final others = _inUse.where((c) => c != _currency).toList();
    if (others.isEmpty) return "";
    return "יש רשומות גם ב-${others.map((c) => c.name).join(', ')}. "
        "סכומים ממטבעות שונים אינם מחוברים זה לזה.";
  }

  /// Chooses the folder a copy is left in after every sitting.
  ///
  /// The point is a folder the writer already syncs. He gets automatic backup
  /// without this app ever holding an account, a server, or a copy of his work
  /// anywhere he cannot see.
  Future<void> _pickAutoBackupFolder() async {
    if (_autoBackupFolder != null) {
      final off = await confirmAction(
        context,
        title: "גיבוי אוטומטי",
        message: "התיקייה הנוכחית:\n$_autoBackupFolder\n\n"
            "לכבות את הגיבוי האוטומטי? הקבצים שכבר נכתבו יישארו במקומם.",
        confirmLabel: "כבה",
        danger: true,
      );
      if (!off || !mounted) return;
      await _storage.setAutoBackupFolder(null);
      if (mounted) setState(() => _autoBackupFolder = null);
      return;
    }

    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'בחר תיקייה לגיבוי אוטומטי',
    );
    if (picked == null || !mounted) return;

    await _storage.setAutoBackupFolder(picked);
    if (!mounted) return;
    setState(() => _autoBackupFolder = picked);
    // Written at once rather than waiting for the next sitting, so the writer
    // can go and look at the file instead of taking it on trust.
    final ok = await BackupService.instance.writeAutoBackup();
    if (!mounted) return;
    ok
        ? showAppSuccess(context, "גיבוי אוטומטי הופעל, ונכתב קובץ ראשון")
        : showAppError(context, "לא הצלחתי לכתוב לתיקייה שנבחרה");
  }

  Future<void> _updateNotificationSettings(bool enabled) async {
    if (mounted) {
      setState(() => _notificationsEnabled = enabled);
    }
    await _storage.setNotificationEnabled(enabled);
    await NotificationService().scheduleDailyReminder();
  }

  Future<void> _setSmartReminder(bool value) async {
    await _storage.setSmartReminder(value);
    if (mounted) setState(() => _smartReminder = value);
    // Re-books the week at once, so the change is real before he closes the
    // screen rather than at some point he cannot observe.
    await NotificationService().scheduleDailyReminder();
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

  /// Asks GitHub whether there is a newer release, when the writer asks.
  ///
  /// Never on its own: this is the only request the app makes that nobody asked
  /// for by name, and a good part of this audience is behind content filtering
  /// where an unbidden call to an API is at best noise and at worst a hang.
  ///
  /// Three answers, and all three are said plainly. Failing is ordinary here —
  /// it means the check could not be made, not that anything is wrong.
  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);
    final status = await const UpdateService().check();
    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    switch (status) {
      case UpToDate(:final running):
        showAppSuccess(context, "אתה מריץ את הגרסה האחרונה ($running)");

      case UpdateCheckFailed(:final reason):
        showAppError(context, reason);

      case UpdateAvailable(:final version, :final pageUrl, :final publishedAt):
        final when = publishedAt == null
            ? ""
            : " (פורסמה ${formatDisplayDate(publishedAt, _useGregorianDates)})";
        final open = await confirmAction(
          context,
          title: "יש גרסה חדשה",
          // Says what will happen. The app does not download and does not
          // install — on Android it may not, and anywhere else it should not
          // pretend to more than it does.
          message: "גרסה $version פורסמה$when.\n\n"
              "לפתוח את דף השחרור בדפדפן?",
          confirmLabel: "פתח",
        );
        if (open) await launchUrl(Uri.parse(pageUrl));
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
      if (message != null) showAppError(context, message);
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

    showAppSuccess(context, summary);
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
              leading: Icon(Icons.save_alt, color: SoferTokens.of(context).accent),
              title: const Text("שמור במכשיר"),
              subtitle: Text(PlatformSupport.isDesktop
                  ? "בחירת תיקייה לשמירת הקובץ"
                  : "בחירת מיקום בזיכרון המכשיר"),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: Icon(Icons.share, color: SoferTokens.of(context).accent),
              title: const Text("שיתוף"),
              subtitle: const Text(
                  "שליחה לוואטסאפ, מייל, או כל אפליקציה אחרת במכשיר"),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            const Divider(),
            ListTile(
              leading:
                  Icon(Icons.restore_page, color: SoferTokens.of(context).accent),
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
        showAppSuccess(
            context,
            choice == 'save' && result.path != null
                ? "הגיבוי נשמר:\n${result.path}"
                : "הגיבוי נוצר בהצלחה");
      case BackupOutcome.cancelled:
        break;
      case BackupOutcome.failed:
        showAppError(
            context, "הגיבוי נכשל: ${result.error ?? 'שגיאה לא ידועה'}");
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
              Text('גרסה: $appVersion'),
              const SizedBox(height: 12),
              const Text('אתר האפליקציה:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              InkWell(
                child: Text(
                  'https://soferstam-app.github.io/sofer-vmone/',
                  style: TextStyle(
                    color: SoferTokens.of(context).accent,
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
                child: Text(
                  'https://github.com/soferstam-app/sofer-vmone',
                  style: TextStyle(
                    color: SoferTokens.of(context).accent,
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
                    Icon(Icons.coffee, size: 20, color: SoferTokens.of(context).accent),
                    const SizedBox(width: 6),
                    Text(
                      'https://buymeacoffee.com/soferstam',
                      style: TextStyle(
                        color: SoferTokens.of(context).accent,
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
          // The fonts are under the SIL Open Font License, which asks that the
          // licence travel with them. Bundling it is not enough on its own —
          // there has to be a way to read it.
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'סופר ומונה',
              applicationLegalese: '© סופר ומונה',
            ),
            child: const Text("רישיונות"),
          ),
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
      body: SoferTokens.of(context).isRules
          ? SoferPage(maxWidth: 720, child: _ruledSettings())
          : _cardSettings(),
    );
  }

  /// Settings as a specification sheet.
  ///
  /// Every entry states its current value on the right, in the serif, because
  /// the value is what the writer came to check — in the Material layout it is
  /// buried in a subtitle under the name. No leading icons and no chevrons: a
  /// row that can be tapped is one that has a value to change.
  Widget _ruledSettings() {
    return ListView(
      children: [
        // Android only, and hidden rather than shown disabled. A setting that
        // cannot do anything on the platform it is displayed on is worse than
        // an absent one: the writer sets it, and nothing ever happens.
        if (NotificationService.isSupported) ...[
          const SoferSectionTitle("תזכורות"),
          _toggle(
            "התראות יומיות",
            "תזכורת יומית לרישום העבודה",
            _notificationsEnabled,
            _updateNotificationSettings,
          ),
          if (_notificationsEnabled) ...[
            _toggle(
              "תזכורת לפי ההרגלים שלי",
              "לפי השעה שבה אתה בדרך כלל מתחיל, במקום שעה קבועה",
              _smartReminder,
              _setSmartReminder,
            ),
            if (!_smartReminder)
              _entry("שעת תזכורת", _notificationTime.format(context),
                  onTap: _pickNotificationTime),
          ],
          const SoferRule(strong: true),
        ],

        _entry(
            "גיבוי אוטומטי",
            _autoBackupFolder == null ? "כבוי" : "פעיל",
            note: _autoBackupFolder ??
                "בחר תיקייה שאתה מסנכרן ממילא — עותק ייכתב אחרי כל ישיבה",
            onTap: _pickAutoBackupFolder),
        const SoferRule(strong: true),

        const SoferSectionTitle("לוח ותאריכים"),
        _entry("עיצוב", themeController.choice.label,
            note: themeController.nightByClock
                ? "כרגע בערכת לילה"
                : themeController.autoNight
                    ? "מעבר אוטומטי ללילה"
                    : null,
            onTap: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ThemeSettingsScreen()));
              if (mounted) setState(() {});
            }),
        // Stated without a value on purpose. A summary here — Friday in
        // particular — read as though Friday were set on this screen, which is
        // the one thing this row must not imply. The rules are stated where
        // they are changed.
        _entry("ימי עבודה", "", onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const WorkCalendarSettingsScreen()));
        }),
        _entry("מעבר יום", _dayStart.summary,
            note: _dayStartSummary, onTap: _pickDayStart),
        _entry("מטבע", "${_currency.name} (${_currency.symbol})",
            note: _currencyNote, onTap: _pickCurrency),
        _toggle(
          "תאריכים לועזיים",
          "תצוגה בלבד — החישוב תמיד לפי הלוח העברי",
          _useGregorianDates,
          (v) async {
            await _storage.setUseGregorianDates(v);
            if (mounted) setState(() => _useGregorianDates = v);
          },
        ),
        const SoferRule(strong: true),

        const SoferSectionTitle("הנתונים"),
        _entry("שם הסופר", _soferName.isEmpty ? "לא הוגדר" : _soferName,
            note: "לחתימה בעדכונים ללקוחות", onTap: _editSoferName),
        _entry("גיבוי הנתונים", _isExporting ? "מייצא…" : "ייצוא / שחזור",
            note: "פרויקטים, היסטוריה, הוצאות והגדרות בקובץ אחד",
            onTap: _isExporting ? null : _showBackupOptions),
        if (_unreadable > 0)
          _entry("רשומות שגרסה זו אינה מבינה", "$_unreadable",
              note: "נשמרות כמו שהן ואינן נכנסות לאף חישוב. "
                  "גרסה חדשה יותר תדע לקרוא אותן"),
        if (Platform.isWindows || Platform.isMacOS)
          _entry("בדוק עדכונים", _checkingUpdate ? "בודק…" : "",
            onTap: _checkingUpdate ? null : _checkForUpdates),
        const SoferRule(strong: true),
        const SizedBox(height: 24),
      ],
    );
  }

  /// One line of the sheet: what it is, and what it is set to.
  Widget _entry(String label, String value,
      {String? note, VoidCallback? onTap}) {
    final t = SoferTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontFamily: t.labelFamily,
                          fontSize: 14,
                          color: t.ink)),
                  if (note != null) ...[
                    const SizedBox(height: 3),
                    Text(note,
                        style: TextStyle(
                            fontFamily: t.labelFamily,
                            fontSize: 12,
                            height: 1.5,
                            color: t.inkMuted)),
                  ],
                ],
              ),
            ),
            if (value.isNotEmpty) ...[
              const SizedBox(width: 14),
              // Flexible, not fixed: a sofer's name or a long value would
              // otherwise push the row off the edge of a phone.
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 17,
                        color: onTap == null ? t.inkMuted : t.accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toggle(
      String label, String note, bool value, ValueChanged<bool> onChanged) {
    final t = SoferTokens.of(context);
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 14,
                        color: t.ink)),
                const SizedBox(height: 3),
                Text(note,
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        height: 1.5,
                        color: t.inkMuted)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _cardSettings() {
    return SingleChildScrollView(
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
                    // See the ruled layout: hidden where it cannot work.
                    if (NotificationService.isSupported) ...[
                      SwitchListTile(
                        title: const Text("התראות יומיות"),
                        subtitle:
                            const Text("תזכורת יומית לרישום העבודה"),
                        value: _notificationsEnabled,
                        onChanged: _updateNotificationSettings,
                        secondary: Icon(Icons.notifications_active,
                            color: SoferTokens.of(context).accent),
                      ),
                      if (_notificationsEnabled) ...[
                        SwitchListTile(
                          title: const Text("תזכורת לפי ההרגלים שלי"),
                          subtitle: const Text(
                              "לפי השעה שבה אתה בדרך כלל מתחיל"),
                          value: _smartReminder,
                          onChanged: _setSmartReminder,
                          secondary: Icon(Icons.auto_awesome,
                              color: SoferTokens.of(context).accent),
                        ),
                        if (!_smartReminder)
                          ListTile(
                            title: const Text("שעת תזכורת"),
                            subtitle: Text(_notificationTime.format(context)),
                            leading: Icon(Icons.access_time,
                                color: SoferTokens.of(context).accent),
                            onTap: _pickNotificationTime,
                          ),
                      ],
                      const Divider(),
                    ],
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
                      secondary: Icon(Icons.calendar_month,
                          color: SoferTokens.of(context).accent),
                    ),
                    // The smart/plain workflow switch used to live here. It is
                    // something the writer flips between sittings, not once at
                    // setup, so it sits on the home screen next to the tools
                    // button instead.
                    const Divider(),
                    ListTile(
                      title: const Text("עיצוב"),
                      subtitle: Text(_themeSummary),
                      leading: Icon(Icons.palette_outlined,
                          color: SoferTokens.of(context).accent),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ThemeSettingsScreen(),
                        ),
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      // No subtitle, for the same reason as the ruled sheet:
                      // naming the Friday rule here implied it was set here.
                      title: const Text("ימי עבודה"),
                      leading: Icon(Icons.calendar_today,
                          color: SoferTokens.of(context).accent),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WorkCalendarSettingsScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text("מעבר יום"),
                      subtitle: Text(_dayStartSummary),
                      leading:
                          Icon(Icons.schedule, color: SoferTokens.of(context).accent),
                      onTap: _pickDayStart,
                    ),
                    ListTile(
                      title: const Text("מטבע"),
                      subtitle: Text(_currencyNote.isEmpty
                          ? "${_currency.name} (${_currency.symbol})"
                          : "${_currency.name} · $_currencyNote"),
                      leading: Icon(Icons.payments,
                          color: SoferTokens.of(context).accent),
                      onTap: _pickCurrency,
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text("שם הסופר"),
                      subtitle: Text(_soferName.isEmpty
                          ? "לחתימה בעדכונים ללקוחות (לא הוגדר)"
                          : _soferName),
                      leading: Icon(Icons.badge,
                          color: SoferTokens.of(context).accent),
                      onTap: _editSoferName,
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text("גיבוי הנתונים"),
                      subtitle: const Text(
                          "ייצוא כל הנתונים לקובץ אחד – פרויקטים, היסטוריה, הוצאות והגדרות"),
                      leading: Icon(Icons.backup,
                          color: SoferTokens.of(context).accent),
                      trailing: _isExporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_left),
                      onTap: _isExporting ? null : _showBackupOptions,
                    ),
                    if (_unreadable > 0)
                      ListTile(
                        leading: Icon(Icons.help_outline,
                            color: SoferTokens.of(context).caution),
                        title: Text("$_unreadable רשומות שגרסה זו אינה מבינה"),
                        subtitle: const Text(
                            "נשמרות כמו שהן ואינן נכנסות לאף חישוב. "
                            "גרסה חדשה יותר תדע לקרוא אותן",
                            style: TextStyle(fontSize: 12)),
                      ),
                    if (Platform.isWindows || Platform.isMacOS)
                      ListTile(
                        title: const Text("בדוק עדכונים"),
                        leading:
                            Icon(Icons.update, color: SoferTokens.of(context).accent),
                        onTap: _checkForUpdates,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
  }
}
