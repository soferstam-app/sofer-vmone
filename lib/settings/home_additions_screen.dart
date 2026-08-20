import 'package:flutter/material.dart';

import '../format.dart';
import '../logic/home_additions.dart';
import '../notification_service.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';

/// Opt-in tools that may be placed on the home screen.
///
/// This is intentionally a separate screen: these controls change the working
/// surface, whereas the rest of Settings changes how records are interpreted.
class HomeAdditionsScreen extends StatefulWidget {
  const HomeAdditionsScreen({super.key});

  @override
  State<HomeAdditionsScreen> createState() => _HomeAdditionsScreenState();
}

class _HomeAdditionsScreenState extends State<HomeAdditionsScreen> {
  final StorageService _storage = StorageService();
  HomeAdditionsSettings _settings = HomeAdditionsSettings.defaults;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _storage.getHomeAdditions();
    if (!mounted) return;
    setState(() {
      _settings = value;
      _loading = false;
    });
  }

  Future<void> _save(HomeAdditionsSettings value) async {
    setState(() => _settings = value);
    await _storage.setHomeAdditions(value);
  }

  String _clockTime(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = minutes.remainder(60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickLineTarget() async {
    final value = await _durationDialog(
      title: 'יעד זמן לשורה',
      firstLabel: 'דקות',
      secondLabel: 'שניות',
      first: _settings.lineTargetSeconds ~/ 60,
      second: _settings.lineTargetSeconds.remainder(60),
      firstMax: 1440,
      secondMax: 59,
    );
    if (value == null || value.$1 == 0 && value.$2 == 0) return;
    await _save(
        _settings.copyWith(lineTargetSeconds: value.$1 * 60 + value.$2));
  }

  Future<void> _pickWritingTarget() async {
    final value = await _durationDialog(
      title: 'יעד זמן לישיבה',
      firstLabel: 'שעות',
      secondLabel: 'דקות',
      first: _settings.writingTargetMinutes ~/ 60,
      second: _settings.writingTargetMinutes.remainder(60),
      firstMax: 24,
      secondMax: 59,
    );
    if (value == null || value.$1 == 0 && value.$2 == 0) return;
    await _save(
        _settings.copyWith(writingTargetMinutes: value.$1 * 60 + value.$2));
  }

  Future<(int, int)?> _durationDialog({
    required String title,
    required String firstLabel,
    required String secondLabel,
    required int first,
    required int second,
    required int firstMax,
    required int secondMax,
  }) async {
    final firstController = TextEditingController(text: '$first');
    final secondController = TextEditingController(text: '$second');
    String? error;
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: firstController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: firstLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: secondController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: secondLabel),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () {
                final a = int.tryParse(firstController.text.trim());
                final b = int.tryParse(secondController.text.trim());
                if (a == null ||
                    b == null ||
                    a < 0 ||
                    a > firstMax ||
                    b < 0 ||
                    b > secondMax ||
                    a == 0 && b == 0) {
                  setDialogState(() => error = 'יש להזין זמן תקין וגדול מאפס');
                  return;
                }
                Navigator.pop(dialogContext, (a, b));
              },
              child: const Text('שמירה'),
            ),
          ],
        ),
      ),
    );
    firstController.dispose();
    secondController.dispose();
    return result;
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.endTimeMinutes ~/ 60,
        minute: _settings.endTimeMinutes.remainder(60),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    await _save(
        _settings.copyWith(endTimeMinutes: picked.hour * 60 + picked.minute));
  }

  Widget _addition({
    required String title,
    required String description,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? control,
  }) {
    final t = SoferTokens.of(context);
    return SoferPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: value ? t.accent : t.inkMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: t.ink)),
                    const SizedBox(height: 4),
                    Text(description,
                        style: TextStyle(
                            fontSize: 13, height: 1.5, color: t.inkMuted)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          if (value && control != null) ...[
            const SizedBox(height: 12),
            const SoferRule(),
            const SizedBox(height: 10),
            control,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('תוספות למסך הבית')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SoferPage(
              maxWidth: 720,
              child: ListView(
                padding: const EdgeInsets.only(top: 16, bottom: 28),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      'כל תוספת פועלת בנפרד וכבויה כברירת מחדל. '
                      'האפשרויות שמתאימות לשני מצבי העבודה מופיעות גם במצב חכם וגם במצב רגיל.',
                      style: TextStyle(height: 1.6, color: t.inkMuted),
                    ),
                  ),
                  _addition(
                    title: 'חגיגה בהגעה ליעד היומי',
                    description:
                        'מציג סימן משמח פעם אחת ברגע שהכתיבה של היום מגיעה ליעד הפרויקט.',
                    icon: Icons.celebration,
                    value: _settings.celebrateDailyGoal,
                    onChanged: (value) =>
                        _save(_settings.copyWith(celebrateDailyGoal: value)),
                  ),
                  _addition(
                    title: 'יעד זמן לשורה',
                    description:
                        'שעון השורה סופר לאחור. לאחר החריגה הוא נעשה אדום ומציג זמן במינוס.',
                    icon: Icons.flag_outlined,
                    value: _settings.lineTargetEnabled,
                    onChanged: (value) =>
                        _save(_settings.copyWith(lineTargetEnabled: value)),
                    control: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('הזמן המוקצב לשורה'),
                      trailing: Text(
                        formatClock(
                            Duration(seconds: _settings.lineTargetSeconds)),
                        style: TextStyle(fontSize: 18, color: t.accent),
                      ),
                      onTap: _pickLineTarget,
                    ),
                  ),
                  _addition(
                    title: 'מטרונום בזמן כתיבה',
                    description:
                        'משמיע פעימה קבועה רק בזמן שהטיימר רץ; בהפסקה ובעצירה הוא שקט.',
                    icon: Icons.graphic_eq,
                    value: _settings.metronomeEnabled,
                    onChanged: (value) =>
                        _save(_settings.copyWith(metronomeEnabled: value)),
                    control: Column(
                      children: [
                        Row(
                          children: [
                            const Text('קצב'),
                            const Spacer(),
                            Text('${_settings.metronomeBpm} פעימות בדקה',
                                style:
                                    TextStyle(fontSize: 16, color: t.accent)),
                          ],
                        ),
                        Slider(
                          min: 30,
                          max: 180,
                          divisions: 150,
                          value: _settings.metronomeBpm.toDouble(),
                          label: '${_settings.metronomeBpm}',
                          onChanged: (value) => setState(() => _settings =
                              _settings.copyWith(metronomeBpm: value.round())),
                          onChangeEnd: (value) => _storage.setHomeAdditions(
                              _settings.copyWith(metronomeBpm: value.round())),
                        ),
                      ],
                    ),
                  ),
                  _addition(
                    title: 'יעד זמן לישיבה',
                    description:
                        'מציג כמה זמן כתיבה נטו נשאר בישיבה, ולאחר היעד מציג חריגה.',
                    icon: Icons.hourglass_bottom,
                    value: _settings.writingTargetEnabled,
                    onChanged: (value) =>
                        _save(_settings.copyWith(writingTargetEnabled: value)),
                    control: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('משך הכתיבה המתוכנן'),
                      trailing: Text(
                        formatClock(
                            Duration(minutes: _settings.writingTargetMinutes)),
                        style: TextStyle(fontSize: 18, color: t.accent),
                      ),
                      onTap: _pickWritingTarget,
                    ),
                  ),
                  _addition(
                    title: 'התראה בשעת סיום',
                    description: NotificationService.isSupported
                        ? 'מציגה התראה ומשמיעה צליל בשעה שנקבעה, גם כשהאפליקציה ברקע.'
                        : 'משמיעה התראה בשעה שנקבעה כל עוד האפליקציה פתוחה.',
                    icon: Icons.alarm,
                    value: _settings.endTimeAlertEnabled,
                    onChanged: (value) async {
                      if (value && NotificationService.isSupported) {
                        await NotificationService().requestPermissions();
                      }
                      await _save(
                          _settings.copyWith(endTimeAlertEnabled: value));
                      if (!value) {
                        await NotificationService().cancelWritingEndAlert();
                      }
                      if (context.mounted && value) {
                        showAppNote(context,
                            'ההתראה תחושב מחדש בתחילת ישיבת הכתיבה הבאה');
                      }
                    },
                    control: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('שעת הסיום'),
                      trailing: Text(_clockTime(_settings.endTimeMinutes),
                          style: TextStyle(fontSize: 18, color: t.accent)),
                      onTap: _pickEndTime,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
