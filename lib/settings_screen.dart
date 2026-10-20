import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backup_service.dart';
import 'hebrew_utils.dart';
import 'logic/hebrew_clock.dart';
import 'platform_support.dart';
import 'main.dart'
    show accessibilityController, localeController, themeController;
import 'l10n/app_localizations.dart';
import 'storage_service.dart';
import 'notification_service.dart';
import 'theme_settings_screen.dart';
import 'widgets/sofer_widgets.dart';
import 'work_calendar_settings_screen.dart';
import 'dart:io';
import 'theme/app_theme.dart';
import 'onboarding/onboarding_screen.dart';
import 'settings/shortcuts_screen.dart';
import 'settings/home_additions_screen.dart';
import 'settings/writing_journal_settings_screen.dart';
import 'settings/accessibility_screen.dart';
import 'widgets/feedback.dart';
import 'logic/currency.dart';
import 'version.dart';
import 'update_installer.dart';
import 'update_service.dart';
import 'logic/version_check.dart';
import 'widgets/confirm.dart';

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
  Map<String, dynamic> _autoBackupStatus = {};
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
    final backupStatus = await _storage.getAutoBackupStatus();
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
        _autoBackupStatus = backupStatus;
      });
    }
  }

  String get _themeSummary {
    final choice = context.l10n.isEnglish
        ? switch (themeController.choice) {
            AppTheme.modern => 'Modern',
            AppTheme.klaf => 'Parchment',
            AppTheme.layla => 'Night',
          }
        : themeController.choice.label;
    if (themeController.nightByClock) {
      return context.l10n.pick(
        he: "$choice · כרגע בערכת לילה",
        en: "$choice · night theme active",
      );
    }
    return themeController.autoNight
        ? context.l10n.pick(
            he: "$choice · מעבר אוטומטי ללילה",
            en: "$choice · automatic night mode",
          )
        : choice;
  }

  String get _languageLabel =>
      localeController.language == AppLanguage.hebrew ? 'עברית' : 'English';

  Future<void> _pickLanguage() async {
    final l10n = context.l10n;
    final selected = await showDialog<AppLanguage>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.interfaceLanguage),
        content: RadioGroup<AppLanguage>(
          groupValue: localeController.language,
          onChanged: (value) => Navigator.pop(ctx, value),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<AppLanguage>(
                value: AppLanguage.hebrew,
                title: Text('עברית'),
              ),
              RadioListTile<AppLanguage>(
                value: AppLanguage.english,
                title: Text('English'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await localeController.setLanguage(selected);
    if (mounted) setState(() {});
  }

  String get _dayStartSummary => switch (_dayStart.boundary) {
        DayBoundary.midnight => context.l10n.pick(
            he: "יום חדש מתחיל בחצות (00:00)",
            en: "A new day starts at midnight (00:00)",
          ),
        DayBoundary.sunset => context.l10n.pick(
            he: "יום חדש מתחיל בשקיעה — לפי ממוצע ארץ ישראל",
            en: "A new day starts at sunset — using the Israel average",
          ),
        DayBoundary.nightfall => context.l10n.pick(
            he: "יום חדש מתחיל בצאת הכוכבים — לפי ממוצע ארץ ישראל",
            en: "A new day starts at nightfall — using the Israel average",
          ),
        DayBoundary.fixedHour => context.l10n.pick(
            he: "יום חדש מתחיל ב-${_dayStart.hour.toString().padLeft(2, '0')}:00",
            en: "A new day starts at ${_dayStart.hour.toString().padLeft(2, '0')}:00",
          ),
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
          title: Text(context.l10n.pick(he: "מעבר יום", en: "Day boundary")),
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
                            title: Text(context.l10n.isEnglish
                                ? switch (option) {
                                    DayBoundary.midnight => 'Midnight',
                                    DayBoundary.sunset => 'Sunset',
                                    DayBoundary.nightfall => 'Nightfall',
                                    DayBoundary.fixedHour => 'Fixed hour',
                                  }
                                : option.label),
                            subtitle: Text(
                                context.l10n.isEnglish
                                    ? switch (option) {
                                        DayBoundary.midnight =>
                                          'The civil day changes at 00:00',
                                        DayBoundary.sunset =>
                                          'Uses the average sunset time in Israel',
                                        DayBoundary.nightfall =>
                                          'Uses the average nightfall time in Israel',
                                        DayBoundary.fixedHour =>
                                          'Choose the hour at which a new workday starts',
                                      }
                                    : option.explanation,
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
                            child: Text("${i.toString().padLeft(2, '0')}:00"),
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
                child: Text(context.l10n.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, draft),
                child: Text(context.l10n.confirm)),
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
        title: Text(context.l10n.pick(he: "מטבע", en: "Currency")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.pick(
                  he: "המטבע שבו יוזנו סכומים חדשים.\n\nסכומים שכבר נרשמו נשארים במטבע שבו הוזנו — האפליקציה אינה ממירה ואינה משנה אותם למפרע.",
                  en: "The currency used for new amounts.\n\nAmounts already recorded remain in their original currency; the app does not convert or change them retroactively."),
              style: const TextStyle(fontSize: 13, height: 1.5),
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
              child: Text(context.l10n.cancel)),
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
    return context.l10n.pick(
        he: "יש רשומות גם ב-${others.map((c) => c.name).join(', ')}. סכומים ממטבעות שונים אינם מחוברים זה לזה.",
        en: "Some records also use ${others.map((c) => c.name).join(', ')}. Amounts in different currencies are not added together.");
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
        title: context.l10n.pick(he: "גיבוי אוטומטי", en: "Automatic backup"),
        message: context.l10n.pick(
            he: "התיקייה הנוכחית:\n$_autoBackupFolder\n\nלכבות את הגיבוי האוטומטי? הקבצים שכבר נכתבו יישארו במקומם.",
            en: "Current folder:\n$_autoBackupFolder\n\nTurn off automatic backup? Existing files will remain in place."),
        confirmLabel: context.l10n.pick(he: "כבה", en: "Turn off"),
        danger: true,
      );
      if (!off || !mounted) return;
      try {
        await _storage.setAutoBackupFolder(null);
        if (mounted) setState(() => _autoBackupFolder = null);
      } catch (error) {
        if (mounted) {
          showAppError(
              context,
              context.l10n.pick(
                  he: 'כיבוי הגיבוי נכשל: $error',
                  en: 'Could not disable backup: $error'));
        }
      }
      return;
    }

    final picked = await BackupService.instance.pickAutoBackupFolder(
      title: context.l10n.pick(
          he: 'בחר תיקייה לגיבוי אוטומטי',
          en: 'Choose automatic-backup folder'),
    );
    if (picked == null || !mounted) return;

    try {
      await _storage.setAutoBackupFolder(picked);
    } catch (error) {
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'לא ניתן לשמור את תיקיית הגיבוי',
                en: 'Could not save the backup folder'));
      }
      return;
    }
    final succeeded = await BackupService.instance.writeAutoBackup();
    if (!mounted) return;
    setState(() => _autoBackupFolder = picked);
    // setAutoBackupFolder is observed by StorageService, so the first
    // snapshot is written as part of the same successful save.
    if (!mounted) return;
    if (!succeeded) {
      showAppError(
          context,
          context.l10n.pick(
              he: 'התיקייה נשמרה, אך הגיבוי הראשון נכשל. בדוק שהתיקייה זמינה ושיש הרשאת כתיבה.',
              en: 'The folder was saved, but the first backup failed. Check folder availability and write access.'));
      return;
    }
    showAppSuccess(
        context,
        context.l10n.pick(
            he: "גיבוי אוטומטי הופעל; הקובץ יתעדכן אחרי כל שמירה",
            en: "Automatic backup enabled; the file will update after each save"));
  }

  Future<void> _updateNotificationSettings(bool enabled) async {
    if (mounted) {
      setState(() => _notificationsEnabled = enabled);
    }
    await _storage.setNotificationEnabled(enabled);

    // Ask at the moment he says he wants reminders, and only then. Android 12
    // and later withhold exact alarms until asked, so the app used to save the
    // setting, fail to book anything, and show a switch that said reminders
    // were on.
    if (enabled) {
      final exact = await NotificationService().requestPermissions();
      if (!exact && mounted) {
        showAppNote(
          context,
          context.l10n.pick(
              he: "ייתכן שהתזכורת לא תוצג או תגיע בסמוך לשעה שנבחרה. יש לאשר התראות וכן 'התראות ותזכורות' בהגדרות המכשיר.",
              en: "The reminder may not appear or may arrive near the selected time. Allow notifications and 'Alarms and reminders' in device settings."),
        );
      }
    }

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

  /// Finds a platform package and, after explicit confirmation, installs it.
  /// Checks remain manual: downloading executable code is a separate second
  /// choice, and no network request is made merely because the app was opened.
  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);
    final status = await const UpdateService().check(
      english: context.l10n.isEnglish,
    );
    if (!mounted) return;
    setState(() => _checkingUpdate = false);

    switch (status) {
      case UpToDate(:final running):
        showAppSuccess(
            context,
            context.l10n.pick(
                he: "אתה מריץ את הגרסה האחרונה ($running)",
                en: "You are running the latest version ($running)"));

      case UpdateCheckFailed(:final reason):
        showAppError(context, reason);

      case UpdateAvailable(:final version, :final publishedAt):
        final when = publishedAt == null
            ? ""
            : context.l10n.pick(
                he: " (פורסמה ${formatDisplayDate(publishedAt, _useGregorianDates)})",
                en: " (published ${formatDisplayDate(publishedAt, _useGregorianDates, english: true)})");
        final install = await confirmAction(
          context,
          title: context.l10n
              .pick(he: "יש גרסה חדשה", en: "A new version is available"),
          message: context.l10n.pick(
              he: "גרסה $version פורסמה$when.\n\n${_updateInstallExplanation()}\n\nהנתונים וההגדרות הקיימים יישמרו.",
              en: "Version $version is available$when.\n\n${_updateInstallExplanation()}\n\nYour existing data and settings will be preserved."),
          confirmLabel:
              context.l10n.pick(he: "הורד ועדכן", en: "Download and update"),
        );
        if (install) await _downloadAndInstall(status);
    }
  }

  String _updateInstallExplanation() {
    if (Platform.isAndroid) {
      return context.l10n.pick(
          he: "התוכנה תוריד את קובץ העדכון המאומת, ו־Android יבקש ממך לאשר את ההתקנה.",
          en: "The app will download the verified update file, and Android will ask you to approve the installation.");
    }
    return context.l10n.pick(
        he: "התוכנה תוריד את העדכון המאומת, תיסגר, תחליף את קובצי התוכנה ותיפתח מחדש.",
        en: "The app will download the verified update, close, replace its application files, and reopen.");
  }

  Future<void> _downloadAndInstall(UpdateAvailable release) async {
    final english = context.l10n.isEnglish;
    final progress = ValueNotifier<UpdateDownloadProgress>(
      UpdateDownloadProgress(0, release.asset.size),
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogOpen = true;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDownloadDialog(
        version: release.version.toString(),
        progress: progress,
      ),
    );

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (navigator.mounted) navigator.pop();
    }

    try {
      final downloaded = await const UpdateService().download(
        release,
        onProgress: (value) => progress.value = value,
        english: english,
      );
      closeDialog();
      await dialogFuture;
      await const UpdateInstaller().install(downloaded, english: english);
      if (mounted && Platform.isAndroid) {
        showAppSuccess(
          context,
          context.l10n.pick(
              he: 'קובץ העדכון אומת. יש להשלים את האישור במסך של Android',
              en: 'The update file was verified. Complete the approval in the Android system screen.'),
        );
      }
    } on UpdateException catch (error) {
      closeDialog();
      await dialogFuture;
      if (mounted) showAppError(context, error.message);
    } catch (_) {
      closeDialog();
      await dialogFuture;
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'העדכון לא הושלם', en: 'The update was not completed'));
      }
    } finally {
      progress.dispose();
    }
  }

  Future<void> _editSoferName() async {
    final ctrl = TextEditingController(text: _soferName);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.pick(he: "שם הסופר", en: "Sofer name")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.pick(
                  he: "השם שיופיע כחתימה בעדכוני ההתקדמות שנשלחים ללקוחות.",
                  en: "The name used to sign progress updates sent to clients."),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.pick(he: "שם מלא", en: "Full name"),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(context.l10n.pick(he: "שמור", en: "Save"))),
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
    final read = await BackupService.instance
        .readBackupFile(english: context.l10n.isEnglish);
    if (!mounted) return;
    setState(() => _isExporting = false);

    if (!read.isOk) {
      final message = switch (read.error!) {
        BackupReadError.cancelled => null,
        BackupReadError.unreadable => context.l10n.pick(
            he: "לא ניתן לקרוא את הקובץ", en: "The file could not be read"),
        BackupReadError.notOurFormat => context.l10n.pick(
            he: "הקובץ אינו קובץ גיבוי של סופר ומונה",
            en: "This is not a Sofer v’Mone backup file"),
        BackupReadError.tooNew => context.l10n.pick(
            he: "הקובץ נוצר בגרסה חדשה יותר של האפליקציה. יש לעדכן את האפליקציה כדי לשחזר אותו.",
            en: "The file was created by a newer app version. Update the app before restoring it."),
      };
      if (message != null) showAppError(context, message);
      return;
    }

    final p = read.preview!;
    final exported = p.exportedAt == null
        ? context.l10n.pick(he: "לא ידוע", en: "Unknown")
        : formatDisplayDate(p.exportedAt!, _useGregorianDates,
            english: context.l10n.isEnglish);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(context.l10n.pick(he: "שחזור מגיבוי", en: "Restore backup")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.fileName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                context.l10n.pick(
                    he: "נוצר בתאריך: $exported", en: "Created: $exported"),
                style: const TextStyle(fontSize: 13)),
            const Divider(height: 20),
            Text(context.l10n.pick(
                he: "פרויקטים בקובץ: ${p.projects.length}",
                en: "Projects in file: ${p.projects.length}")),
            Text(context.l10n.pick(
                he: "רשומות עבודה: ${p.history.length}",
                en: "Work records: ${p.history.length}")),
            Text(context.l10n.pick(
                he: "הוצאות: ${p.expenses.length}",
                en: "Expenses: ${p.expenses.length}")),
            if (p.proofreads.isNotEmpty)
              Text(context.l10n.pick(
                  he: "הגהות: ${p.proofreads.length}",
                  en: "Proofreading records: ${p.proofreads.length}")),
            if (p.payments.isNotEmpty)
              Text(context.l10n.pick(
                  he: "תשלומים: ${p.payments.length}",
                  en: "Payments: ${p.payments.length}")),
            if (p.orders.isNotEmpty)
              Text(context.l10n.pick(
                  he: "הזמנות: ${p.orders.length}",
                  en: "Orders: ${p.orders.length}")),
            if (p.unreadable > 0) ...[
              const SizedBox(height: 8),
              // Skipping a record the build cannot read is right; doing it
              // without saying so is not. A partial restore looked complete,
              // and a writer who then deleted the original lost the rest.
              Text(
                context.l10n.pick(
                    he: "${p.unreadable} רשומות בקובץ אינן ניתנות לקריאה ולא ישוחזרו. מומלץ לשמור את הקובץ.",
                    en: "${p.unreadable} records in the file cannot be read and will not be restored. Keep the original file."),
                style:
                    TextStyle(fontSize: 13, color: SoferTokens.of(ctx).danger),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              context.l10n.pick(
                  he: "הנתונים יאוחדו עם הקיימים במכשיר. רשומה שקיימת בשניהם תישמר בגרסה שנערכה לאחרונה. שום דבר מהמכשיר לא יימחק.",
                  en: "The backup will be merged with data on this device. If a record exists in both, the most recently edited version is kept. Nothing on this device will be deleted."),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.pick(he: "שחזר", en: "Restore"))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isExporting = true);
    final outcome = await BackupService.instance.applyBackup(p);
    if (!mounted) return;
    setState(() => _isExporting = false);

    // The imported snapshot may carry portable user preferences. Reload the
    // app-wide controllers while this route is still open, so restoring a
    // backup does not leave the settings screen and the rest of the app
    // displaying the old language, theme, or text size until a restart.
    await localeController.load();
    await themeController.load();
    await accessibilityController.load();
    await _loadNotificationSettings();
    if (!mounted) return;

    final summary = outcome.changedAnything
        ? context.l10n.pick(
            he:
                "נוספו: ${outcome.projectStats.added} פרויקטים, ${outcome.historyStats.added} רשומות, ${outcome.expenseStats.added} הוצאות, ${outcome.orderStats.added} הזמנות.\nעודכנו: ${outcome.projectStats.updated + outcome.historyStats.updated + outcome.expenseStats.updated + outcome.orderStats.updated} פריטים.",
            en:
                "Added: ${outcome.projectStats.added} projects, ${outcome.historyStats.added} records, ${outcome.expenseStats.added} expenses, ${outcome.orderStats.added} orders.\nUpdated: ${outcome.projectStats.updated + outcome.historyStats.updated + outcome.expenseStats.updated + outcome.orderStats.updated} items.")
        : context.l10n.pick(
            he: "כל הנתונים בקובץ כבר קיימים במכשיר – לא בוצע שינוי.",
            en: "All data in the file already exists on this device; no changes were made.");

    showAppSuccess(context, summary);
  }

  /// Lets the user choose between writing the backup to a location they pick
  /// and handing it to the OS share sheet. Both produce the same file.
  /// Says where the old version keeps its file, then opens the same picker.
  ///
  /// The file is not called anything a writer would guess, and on Windows it
  /// lives under a folder named after a package rather than after the app. It
  /// is no use telling him he can import it without telling him what to look
  /// for — so the path is on the screen and can be copied.
  Future<void> _explainLegacyImport() async {
    const windowsPath =
        r'%APPDATA%\com.example\stamsofer\shared_preferences.json';

    final go = await confirmAction(
      context,
      title: context.l10n.pick(
          he: "ייבוא מהתקנה קודמת", en: "Import from an older installation"),
      message: Platform.isWindows
          ? context.l10n.pick(
              he:
                  "גרסאות עד 0.3.1 לא כללו מסך גיבוי, אבל הנתונים שמורים בקובץ רגיל על המחשב:\n\n$windowsPath\n\nאפשר להעתיק אותו מהמחשב הישן ולבחור אותו כאן. הנתונים יתווספו לקיימים ושום דבר לא יימחק.",
              en:
                  "Versions through 0.3.1 did not include a backup screen, but their data is stored in a regular file on the computer:\n\n$windowsPath\n\nCopy it from the old computer and select it here. Its data will be added to existing data and nothing will be deleted.")
          : context.l10n.pick(
              he: "אם יש לך קובץ נתונים מגרסה ישנה — גם כזה שאינו קובץ גיבוי — אפשר לבחור אותו כאן. הנתונים יתווספו לקיימים ושום דבר לא יימחק.",
              en: "If you have a data file from an older version, even if it is not a backup file, select it here. Its data will be added to existing data and nothing will be deleted."),
      confirmLabel: context.l10n.pick(he: "בחר קובץ", en: "Select file"),
    );
    if (!go || !mounted) return;
    await _importBackup();
  }

  Future<void> _showBackupOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.pick(he: "גיבוי הנתונים", en: "Data backup"),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: Icon(Icons.save_alt, color: SoferTokens.of(ctx).accent),
              title: Text(
                  context.l10n.pick(he: "שמור במכשיר", en: "Save on device")),
              subtitle: Text(PlatformSupport.isDesktop
                  ? context.l10n.pick(
                      he: "בחירת תיקייה לשמירת הקובץ",
                      en: "Choose a folder for the file")
                  : context.l10n.pick(
                      he: "בחירת מיקום בזיכרון המכשיר",
                      en: "Choose a location in device storage")),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: Icon(Icons.share, color: SoferTokens.of(ctx).accent),
              title: Text(context.l10n.pick(he: "שיתוף", en: "Share")),
              subtitle: Text(context.l10n.pick(
                  he: "שליחה לוואטסאפ, מייל, או כל אפליקציה אחרת במכשיר",
                  en: "Send through WhatsApp, email, or another app on this device")),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            const Divider(),
            ListTile(
              leading:
                  Icon(Icons.restore_page, color: SoferTokens.of(ctx).accent),
              title: Text(context.l10n.pick(
                  he: "שחזור מקובץ גיבוי", en: "Restore from backup file")),
              subtitle: Text(context.l10n.pick(
                  he: "הנתונים מהקובץ יתווספו לקיימים – שום דבר לא נמחק",
                  en: "File data will be added to existing data; nothing is deleted")),
              onTap: () => Navigator.pop(ctx, 'import'),
            ),
            // The same picker. Versions up to 0.3.1 had no backup screen, so
            // for those writers the app's own store file is the only thing
            // there is — and nothing told them it could be used.
            ListTile(
              leading: Icon(Icons.drive_file_move_outline,
                  color: SoferTokens.of(ctx).accent),
              title: Text(context.l10n.pick(
                  he: "ייבוא מהתקנה קודמת",
                  en: "Import from older installation")),
              subtitle: Text(context.l10n.pick(
                  he: "מגרסה שלא היה בה מסך גיבוי – ישירות מקובץ הנתונים שלה",
                  en: "Import directly from a version that had no backup screen")),
              onTap: () => Navigator.pop(ctx, 'legacy'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'legacy') {
      await _explainLegacyImport();
      return;
    }

    if (choice == 'import') {
      await _importBackup();
      return;
    }

    setState(() => _isExporting = true);
    final english = context.l10n.isEnglish;
    final result = choice == 'save'
        ? await BackupService.instance.saveToDevice(english: english)
        : await BackupService.instance.shareBackup(english: english);
    if (!mounted) return;
    setState(() => _isExporting = false);

    switch (result.outcome) {
      case BackupOutcome.success:
        showAppSuccess(
            context,
            choice == 'save' && result.path != null
                ? context.l10n.pick(
                    he: "הגיבוי נשמר:\n${result.path}",
                    en: "Backup saved:\n${result.path}")
                : context.l10n.pick(
                    he: "הגיבוי נוצר בהצלחה",
                    en: "Backup created successfully"));
      case BackupOutcome.cancelled:
        break;
      case BackupOutcome.failed:
        showAppError(
            context,
            context.l10n.pick(
                he: "הגיבוי נכשל: ${result.error ?? 'שגיאה לא ידועה'}",
                en: "Backup failed: ${result.error ?? 'Unknown error'}"));
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.pick(he: "אודות", en: "About")),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.pick(
                  he: 'שם האפליקציה: סופר ומונה',
                  en: 'App name: Sofer v’Mone')),
              Text(context.l10n
                  .pick(he: 'גרסה: $appVersion', en: 'Version: $appVersion')),
              const SizedBox(height: 12),
              Text(context.l10n.pick(he: 'אתר האפליקציה:', en: 'App website:'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
              Text(context.l10n.pick(he: 'גיטהאב:', en: 'GitHub:'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
              Text(
                context.l10n.pick(
                    he: 'עלויות בניית האפליקציה והתחזוקה שלה הן רבות. למי שמעוניין לתמוך בפיתוח האפליקציה ובפרויקטים עתידיים – אפשר לתרום דרך הקישור הבא. תודה!',
                    en: 'Building and maintaining the app has ongoing costs. If you would like to support its development and future projects, you can donate through the following link. Thank you!'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              InkWell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.coffee,
                        size: 20, color: SoferTokens.of(context).accent),
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
              applicationName: context.l10n.appName,
              applicationLegalese: '© ${context.l10n.appName}',
            ),
            child: Text(context.l10n.pick(he: "רישיונות", en: "Licenses")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.pick(he: "סגור", en: "Close")),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settings),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: context.l10n.pick(he: "אודות", en: "About"),
          ),
        ],
      ),
      body: SoferTokens.of(context).isRules
          ? SoferPage(maxWidth: 720, child: _ruledSettings())
          : _cardSettings(),
    );
  }

  Future<void> _openShortcuts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ShortcutsScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openOnboarding() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          // Opened for reference rather than for the first time, so the last
          // page closes instead of offering to create a first project.
          fromSettings: true,
          onDone: ({required createProject}) => Navigator.pop(context),
        ),
      ),
    );
    if (mounted) setState(() {});
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
          SoferSectionTitle(context.l10n.pick(he: "תזכורות", en: "Reminders")),
          _toggle(
            context.l10n.pick(he: "התראות יומיות", en: "Daily notifications"),
            context.l10n.pick(
              he: "תזכורת יומית לרישום העבודה",
              en: "A daily reminder to record your work",
            ),
            _notificationsEnabled,
            _updateNotificationSettings,
          ),
          if (_notificationsEnabled) ...[
            _toggle(
              context.l10n.pick(
                he: "תזכורת לפי ההרגלים שלי",
                en: "Reminder based on my habits",
              ),
              context.l10n.pick(
                he: "לפי השעה שבה אתה בדרך כלל מתחיל, במקום שעה קבועה",
                en: "Use the time you usually start instead of a fixed time",
              ),
              _smartReminder,
              _setSmartReminder,
            ),
            if (!_smartReminder)
              _entry(context.l10n.pick(he: "שעת תזכורת", en: "Reminder time"),
                  _notificationTime.format(context),
                  onTap: _pickNotificationTime),
          ],
          const SoferRule(strong: true),
        ],

        _autoBackupEntry(ruled: true),
        const SoferRule(strong: true),

        _entry(
          context.l10n.pick(
            he: "תוספות למסך הבית",
            en: "Home screen additions",
          ),
          context.l10n.pick(
            he: "חגיגה, יעדי זמן ומטרונום",
            en: "Celebration, time targets, and metronome",
          ),
          note: context.l10n.pick(
            he: "כל תוספת ניתנת להפעלה או לכיבוי בנפרד",
            en: "Each addition can be turned on or off separately",
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HomeAdditionsScreen()),
          ),
        ),
        const SoferRule(strong: true),

        _entry(
          context.l10n.pick(he: "יומן כתיבה", en: "Writing Journal"),
          context.l10n.pick(
            he: "מסך בית, תאריכים, לוח פרשיות ועמודות",
            en: "Home screen, dates, Parashah cycle, and columns",
          ),
          note: context.l10n.pick(
            he: "התאמת הטבלה השבועית למסך, להדפסה ול־Excel",
            en: "Configure the weekly table for screen, print, and Excel",
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const WritingJournalSettingsScreen(),
            ),
          ),
        ),
        const SoferRule(strong: true),

        SoferSectionTitle(context.l10n.pick(
          he: "לוח ותאריכים",
          en: "Calendar and dates",
        )),
        // Desktop only: a shortcut needs a keyboard, and offering the screen
        // on a phone would be offering a setting that cannot be used.
        if (PlatformSupport.isDesktop)
          _entry(
              context.l10n.pick(he: "קיצורי מקלדת", en: "Keyboard shortcuts"),
              context.l10n.pick(
                  he: "התחלה, הפסקה, סיום שורה",
                  en: "Start, break, finish line"),
              onTap: _openShortcuts),
        // Without a way back, the only way to read the explanation twice is to
        // reinstall the app.
        _entry(
            context.l10n.pick(he: "מסך הפתיחה", en: "Welcome screens"),
            context.l10n.pick(
                he: "ההסבר שמוצג בהפעלה הראשונה",
                en: "The explanation shown on first launch"),
            onTap: _openOnboarding),
        _entry(context.l10n.language, _languageLabel, onTap: _pickLanguage),
        _entry(
          context.l10n.pick(he: "נגישות", en: "Accessibility"),
          context.l10n.pick(
              he: "גודל הכיתוב בכל התוכנה", en: "Text size throughout the app"),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccessibilityScreen()),
          ),
        ),
        _entry(context.l10n.pick(he: "עיצוב", en: "Appearance"), _themeSummary,
            note: themeController.nightByClock
                ? "כרגע בערכת לילה"
                : themeController.autoNight
                    ? "מעבר אוטומטי ללילה"
                    : null, onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ThemeSettingsScreen()));
          if (mounted) setState(() {});
        }),
        // Stated without a value on purpose. A summary here — Friday in
        // particular — read as though Friday were set on this screen, which is
        // the one thing this row must not imply. The rules are stated where
        // they are changed.
        _entry(context.l10n.pick(he: "ימי עבודה", en: "Workdays"), "",
            onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const WorkCalendarSettingsScreen()));
        }),
        _entry(context.l10n.pick(he: "מעבר יום", en: "Day boundary"),
            _dayStartSummary,
            note: _dayStartSummary, onTap: _pickDayStart),
        _entry(context.l10n.pick(he: "מטבע", en: "Currency"),
            "${_currency.name} (${_currency.symbol})",
            note: _currencyNote, onTap: _pickCurrency),
        _toggle(
          context.l10n.pick(he: "תאריכים לועזיים", en: "Gregorian dates"),
          context.l10n.pick(
            he: "תצוגה בלבד — החישוב תמיד לפי הלוח העברי",
            en: "Display only — calculations always use the Hebrew calendar",
          ),
          _useGregorianDates,
          (v) async {
            await _storage.setUseGregorianDates(v);
            if (mounted) setState(() => _useGregorianDates = v);
          },
        ),
        const SoferRule(strong: true),

        SoferSectionTitle(context.l10n.pick(he: "הנתונים", en: "Data")),
        _entry(
            context.l10n.pick(he: "שם הסופר", en: "Sofer name"),
            _soferName.isEmpty
                ? context.l10n.pick(he: "לא הוגדר", en: "Not set")
                : _soferName,
            note: context.l10n.pick(
                he: "לחתימה בעדכונים ללקוחות",
                en: "Used to sign client updates"),
            onTap: _editSoferName),
        _entry(
            context.l10n.pick(he: "גיבוי הנתונים", en: "Data backup"),
            _isExporting
                ? context.l10n.pick(he: "מייצא…", en: "Exporting…")
                : context.l10n
                    .pick(he: "ייצוא / שחזור", en: "Export / restore"),
            note: context.l10n.pick(
                he: "פרויקטים, היסטוריה, הוצאות, הזמנות והגדרות בקובץ אחד",
                en: "Projects, history, expenses, orders, and settings in one file"),
            onTap: _isExporting ? null : _showBackupOptions),
        if (_unreadable > 0)
          _entry(
              context.l10n.pick(
                  he: "רשומות שגרסה זו אינה מבינה",
                  en: "Records this version cannot read"),
              "$_unreadable",
              note: context.l10n.pick(
                  he: "נשמרות כמו שהן ואינן נכנסות לאף חישוב. גרסה חדשה יותר תדע לקרוא אותן",
                  en: "They are preserved unchanged and excluded from calculations. A newer version may be able to read them.")),
        if (Platform.isWindows || Platform.isAndroid)
          _entry(
              context.l10n.pick(he: "בדוק ועדכן", en: "Check for updates"),
              _checkingUpdate
                  ? context.l10n.pick(he: "בודק…", en: "Checking…")
                  : "",
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
                        fontFamily: t.labelFamily, fontSize: 14, color: t.ink)),
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

  Widget _autoBackupEntry({bool ruled = false}) =>
      ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: BackupService.instance.autoBackupStatus,
        builder: (context, current, _) {
          final candidate = current.isEmpty ? _autoBackupStatus : current;
          final status = candidate['folder'] == _autoBackupFolder
              ? candidate
              : <String, dynamic>{};
          final rawSuccess = status['lastSuccess'];
          final success = rawSuccess is String
              ? DateTime.tryParse(rawSuccess)?.toLocal()
              : null;
          final successText = success == null
              ? null
              : '${formatDisplayDate(success, true, english: context.l10n.isEnglish)} ${success.hour.toString().padLeft(2, '0')}:${success.minute.toString().padLeft(2, '0')}';
          final failed = status['error'] != null;
          final value = _autoBackupFolder == null
              ? context.l10n.pick(he: 'כבוי', en: 'Off')
              : failed
                  ? context.l10n
                      .pick(he: 'הגיבוי האחרון נכשל', en: 'Last backup failed')
                  : success == null
                      ? context.l10n.pick(
                          he: 'טרם נוצר גיבוי', en: 'No successful backup yet')
                      : context.l10n.pick(he: 'פעיל', en: 'On');
          final note = _autoBackupFolder == null
              ? context.l10n.pick(
                  he: 'בחר תיקייה מסונכרנת לגיבוי אחרי כל שמירה',
                  en: 'Choose a synced folder for backup after each save')
              : '$_autoBackupFolder${successText == null ? '' : context.l10n.pick(he: '\nגיבוי מוצלח אחרון: $successText', en: '\nLast successful backup: $successText')}${failed ? context.l10n.pick(he: '\nכישלונות רצופים: ${status['failures']} · ${status['error']}', en: '\nConsecutive failures: ${status['failures']} · ${status['error']}') : ''}';
          final label =
              context.l10n.pick(he: 'גיבוי אוטומטי', en: 'Automatic backup');
          if (ruled) {
            return _entry(label, value,
                note: note, onTap: _pickAutoBackupFolder);
          }
          return ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: Text('$label · $value'),
              subtitle: Text(note),
              onTap: _pickAutoBackupFolder);
        },
      );

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
                      title: Text(context.l10n.pick(
                          he: "התראות יומיות", en: "Daily notifications")),
                      subtitle: Text(context.l10n.pick(
                          he: "תזכורת יומית לרישום העבודה",
                          en: "A daily reminder to record your work")),
                      value: _notificationsEnabled,
                      onChanged: _updateNotificationSettings,
                      secondary: Icon(Icons.notifications_active,
                          color: SoferTokens.of(context).accent),
                    ),
                    if (_notificationsEnabled) ...[
                      SwitchListTile(
                        title: Text(context.l10n.pick(
                            he: "תזכורת לפי ההרגלים שלי",
                            en: "Reminder based on my habits")),
                        subtitle: Text(context.l10n.pick(
                            he: "לפי השעה שבה אתה בדרך כלל מתחיל",
                            en: "Based on the time you usually start")),
                        value: _smartReminder,
                        onChanged: _setSmartReminder,
                        secondary: Icon(Icons.auto_awesome,
                            color: SoferTokens.of(context).accent),
                      ),
                      if (!_smartReminder)
                        ListTile(
                          title: Text(context.l10n
                              .pick(he: "שעת תזכורת", en: "Reminder time")),
                          subtitle: Text(_notificationTime.format(context)),
                          leading: Icon(Icons.access_time,
                              color: SoferTokens.of(context).accent),
                          onTap: _pickNotificationTime,
                        ),
                    ],
                    const Divider(),
                  ],
                  ListTile(
                    title: Text(context.l10n.pick(
                        he: "תוספות למסך הבית", en: "Home screen additions")),
                    subtitle: Text(context.l10n.pick(
                        he: "חגיגה, יעד לשורה, מטרונום וזמני כתיבה",
                        en: "Celebration, line target, metronome, and writing times")),
                    leading:
                        Icon(Icons.tune, color: SoferTokens.of(context).accent),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HomeAdditionsScreen()),
                    ),
                  ),
                  ListTile(
                    title: Text(context.l10n
                        .pick(he: "יומן כתיבה", en: "Writing Journal")),
                    subtitle: Text(context.l10n.pick(
                        he: "מסך בית, תאריכים, לוח פרשיות ועמודות",
                        en: "Home screen, dates, Parashah cycle, and columns")),
                    leading: Icon(Icons.table_chart_outlined,
                        color: SoferTokens.of(context).accent),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WritingJournalSettingsScreen(),
                      ),
                    ),
                  ),
                  if (PlatformSupport.isDesktop)
                    ListTile(
                      title: Text(context.l10n
                          .pick(he: "קיצורי מקלדת", en: "Keyboard shortcuts")),
                      subtitle: Text(context.l10n.pick(
                          he: "התחלה, הפסקה, סיום שורה",
                          en: "Start, break, finish line")),
                      leading: Icon(Icons.keyboard_outlined,
                          color: SoferTokens.of(context).accent),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: _openShortcuts,
                    ),
                  ListTile(
                    title: Text(context.l10n
                        .pick(he: "מסך הפתיחה", en: "Welcome screens")),
                    subtitle: Text(context.l10n.pick(
                        he: "ההסבר שמוצג בהפעלה הראשונה",
                        en: "The explanation shown on first launch")),
                    leading: Icon(Icons.slideshow_outlined,
                        color: SoferTokens.of(context).accent),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: _openOnboarding,
                  ),
                  ListTile(
                    title: Text(context.l10n.language),
                    subtitle: Text(_languageLabel),
                    leading: Icon(Icons.translate,
                        color: SoferTokens.of(context).accent),
                    trailing: Directionality.of(context) == TextDirection.rtl
                        ? const Icon(Icons.chevron_left)
                        : const Icon(Icons.chevron_right),
                    onTap: _pickLanguage,
                  ),
                  SwitchListTile(
                    title: Text(context.l10n
                        .pick(he: "תאריכים לועזיים", en: "Gregorian dates")),
                    subtitle: Text(context.l10n.pick(
                        he: "תצוגה בלבד. החישוב — ימי עבודה, חגים וצפי סיום — נעשה תמיד לפי הלוח העברי",
                        en: "Display only. Workdays, holidays, and completion estimates always use the Hebrew calendar.")),
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
                    title: Text(
                        context.l10n.pick(he: "נגישות", en: "Accessibility")),
                    subtitle: Text(context.l10n.pick(
                        he: "גודל הכיתוב בכל התוכנה",
                        en: "Text size throughout the app")),
                    leading: Icon(Icons.text_increase,
                        color: SoferTokens.of(context).accent),
                    trailing: Directionality.of(context) == TextDirection.rtl
                        ? const Icon(Icons.chevron_left)
                        : const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AccessibilityScreen()),
                    ),
                  ),
                  ListTile(
                    title:
                        Text(context.l10n.pick(he: "עיצוב", en: "Appearance")),
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
                    title: Text(
                        context.l10n.pick(he: "ימי עבודה", en: "Workdays")),
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
                    title: Text(
                        context.l10n.pick(he: "מעבר יום", en: "Day boundary")),
                    subtitle: Text(_dayStartSummary),
                    leading: Icon(Icons.schedule,
                        color: SoferTokens.of(context).accent),
                    onTap: _pickDayStart,
                  ),
                  ListTile(
                    title: Text(context.l10n.pick(he: "מטבע", en: "Currency")),
                    subtitle: Text(_currencyNote.isEmpty
                        ? "${_currency.name} (${_currency.symbol})"
                        : "${_currency.name} · $_currencyNote"),
                    leading: Icon(Icons.payments,
                        color: SoferTokens.of(context).accent),
                    onTap: _pickCurrency,
                  ),
                  const Divider(),
                  ListTile(
                    title: Text(
                        context.l10n.pick(he: "שם הסופר", en: "Sofer name")),
                    subtitle: Text(_soferName.isEmpty
                        ? context.l10n.pick(
                            he: "לחתימה בעדכונים ללקוחות (לא הוגדר)",
                            en: "Used to sign client updates (not set)",
                          )
                        : _soferName),
                    leading: Icon(Icons.badge,
                        color: SoferTokens.of(context).accent),
                    onTap: _editSoferName,
                  ),
                  const Divider(),
                  ListTile(
                    title: Text(context.l10n
                        .pick(he: "גיבוי הנתונים", en: "Data backup")),
                    subtitle: Text(context.l10n.pick(
                        he: "ייצוא כל הנתונים לקובץ אחד – פרויקטים, היסטוריה, הוצאות, הזמנות והגדרות",
                        en: "Export projects, history, expenses, orders, and settings to one file")),
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
                  _autoBackupEntry(),
                  if (_unreadable > 0)
                    ListTile(
                      leading: Icon(Icons.help_outline,
                          color: SoferTokens.of(context).caution),
                      title: Text(context.l10n.pick(
                          he: "$_unreadable רשומות שגרסה זו אינה מבינה",
                          en: "$_unreadable records this version cannot read")),
                      subtitle: Text(
                          context.l10n.pick(
                              he: "נשמרות כמו שהן ואינן נכנסות לאף חישוב. גרסה חדשה יותר תדע לקרוא אותן",
                              en: "They are preserved unchanged and excluded from calculations. A newer version may read them."),
                          style: TextStyle(fontSize: 12)),
                    ),
                  if (Platform.isWindows || Platform.isAndroid)
                    ListTile(
                      title: Text(context.l10n
                          .pick(he: "בדוק ועדכן", en: "Check for updates")),
                      leading: Icon(Icons.update,
                          color: SoferTokens.of(context).accent),
                      onTap: _checkingUpdate ? null : _checkForUpdates,
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

class _UpdateDownloadDialog extends StatelessWidget {
  final String version;
  final ValueListenable<UpdateDownloadProgress> progress;

  const _UpdateDownloadDialog({
    required this.version,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.pick(
          he: 'מוריד את גרסה $version', en: 'Downloading version $version')),
      content: ValueListenableBuilder<UpdateDownloadProgress>(
        valueListenable: progress,
        builder: (context, value, _) {
          final percentage = (value.fraction * 100).floor();
          final receivedMb = value.received / (1024 * 1024);
          final totalMb = value.total / (1024 * 1024);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: value.fraction),
              const SizedBox(height: 12),
              Text(
                value.fraction >= 1
                    ? context.l10n.pick(
                        he: 'ההורדה הסתיימה · מאמת את הקובץ…',
                        en: 'Download complete · verifying file…')
                    : context.l10n.pick(
                        he: '$percentage% · ${receivedMb.toStringAsFixed(1)} מתוך ${totalMb.toStringAsFixed(1)} MB',
                        en: '$percentage% · ${receivedMb.toStringAsFixed(1)} of ${totalMb.toStringAsFixed(1)} MB'),
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}
