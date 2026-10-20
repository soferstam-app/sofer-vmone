import 'package:flutter/material.dart';

import '../format.dart';
import '../logic/home_additions.dart';
import '../logic/metronome_audio.dart';
import '../notification_service.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';
import '../l10n/app_localizations.dart';

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
  final MetronomeAudio _metronomeAudio = MetronomeAudio();
  HomeAdditionsSettings _settings = HomeAdditionsSettings.defaults;
  bool _askBreakLength = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await _storage.getHomeAdditions();
    final askBreakLength = await _storage.getAskBreakLength();
    if (!mounted) return;
    setState(() {
      _settings = value;
      _askBreakLength = askBreakLength;
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
      title: context.l10n.pick(he: 'יעד זמן לשורה', en: 'Line time target'),
      firstLabel: context.l10n.pick(he: 'דקות', en: 'Minutes'),
      secondLabel: context.l10n.pick(he: 'שניות', en: 'Seconds'),
      first: _settings.lineTargetSeconds ~/ 60,
      second: _settings.lineTargetSeconds.remainder(60),
      firstMax: 1440,
      secondMax: 59,
    );
    if (value == null || value.$1 == 0 && value.$2 == 0) return;
    await _save(
        _settings.copyWith(lineTargetSeconds: value.$1 * 60 + value.$2));
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
              child: Text(context.l10n.cancel),
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
                  setDialogState(() => error = context.l10n.pick(
                        he: 'יש להזין זמן תקין וגדול מאפס',
                        en: 'Enter a valid time greater than zero',
                      ));
                  return;
                }
                Navigator.pop(dialogContext, (a, b));
              },
              child: Text(context.l10n.pick(he: 'שמירה', en: 'Save')),
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

  Future<void> _previewAlert() async {
    final played = await _metronomeAudio.alert();
    if (!mounted) return;
    if (played) {
      showAppSuccess(
        context,
        context.l10n.pick(he: 'צליל ההתראה הושמע', en: 'Alert sound played'),
      );
    } else {
      showAppError(
        context,
        context.l10n.pick(
          he: 'לא ניתן היה להשמיע צליל. יש לבדוק שעוצמת המכשיר פעילה.',
          en: 'The sound could not be played. Check the device volume.',
        ),
      );
    }
  }

  Future<void> _previewMetronome() async {
    final played = await _metronomeAudio.beat(_settings.metronomeVolume);
    if (!mounted || played) return;
    showAppError(
      context,
      context.l10n.pick(
        he: 'לא ניתן היה להשמיע פעימה. יש לבדוק שעוצמת המדיה פעילה.',
        en: 'The beat could not be played. Check the media volume.',
      ),
    );
  }

  @override
  void dispose() {
    _metronomeAudio.dispose();
    super.dispose();
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
      appBar: AppBar(
          title: Text(context.l10n
              .pick(he: 'תוספות למסך הבית', en: 'Home screen additions'))),
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
                      context.l10n.pick(
                        he: 'כל תוספת פועלת בנפרד וכבויה כברירת מחדל. האפשרויות שמתאימות לשני מצבי העבודה מופיעות גם במצב חכם וגם במצב רגיל.',
                        en: 'Each addition works independently and is off by default. Options that apply to both workflows appear in Smart Mode and Regular Mode.',
                      ),
                      style: TextStyle(height: 1.6, color: t.inkMuted),
                    ),
                  ),
                  _addition(
                    title: context.l10n.pick(
                        he: 'לשאול כמה זמן ההפסקה',
                        en: 'Ask how long the break will be'),
                    description: context.l10n.pick(
                      he: 'כשכבוי, ההפסקה מתחילה מיד בלחיצה. כשפעיל, אפשר להגדיר לה יעד ולראות חריגה.',
                      en: 'When off, the break starts immediately. When on, you can set a target and see overtime.',
                    ),
                    icon: Icons.coffee,
                    value: _askBreakLength,
                    onChanged: (value) async {
                      await _storage.setAskBreakLength(value);
                      if (mounted) setState(() => _askBreakLength = value);
                    },
                  ),
                  _addition(
                    title: context.l10n.pick(
                        he: 'חגיגה בהגעה ליעד היומי',
                        en: 'Celebrate reaching the daily target'),
                    description: context.l10n.pick(
                        he: 'מציג סימן משמח פעם אחת ברגע שהכתיבה של היום מגיעה ליעד הפרויקט.',
                        en: 'Shows a celebration once when today’s writing reaches the project target.'),
                    icon: Icons.celebration,
                    value: _settings.celebrateDailyGoal,
                    onChanged: (value) =>
                        _save(_settings.copyWith(celebrateDailyGoal: value)),
                  ),
                  _addition(
                    title: context.l10n.pick(
                      he: 'סיום כתיבה משלים שורה',
                      en: 'Finish writing completes the line',
                    ),
                    description: context.l10n.pick(
                      he: 'במצב חכם, לחיצה על סיום כתיבה תשמור את השורה הנוכחית כשלמה ותתקדם. כשהאפשרות כבויה, הזמן נשמר כחלקי ונשארים באותה שורה.',
                      en: 'In Smart Mode, stopping saves the current line as complete and advances. When off, its time is saved as partial and the position stays on that line.',
                    ),
                    icon: Icons.stop_circle_outlined,
                    value: _settings.finishWritingCompletesLine,
                    onChanged: (value) => _save(_settings.copyWith(
                        finishWritingCompletesLine: value)),
                  ),
                  _addition(
                    title: context.l10n
                        .pick(he: 'יעד זמן לשורה', en: 'Line time target'),
                    description: context.l10n.pick(
                        he: 'שעון השורה סופר לאחור. לאחר החריגה הוא נעשה אדום ומציג זמן במינוס.',
                        en: 'The line clock counts down. After the target it turns red and shows negative time.'),
                    icon: Icons.flag_outlined,
                    value: _settings.lineTargetEnabled,
                    onChanged: (value) =>
                        _save(_settings.copyWith(lineTargetEnabled: value)),
                    control: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.pick(
                          he: 'הזמן המוקצב לשורה',
                          en: 'Time allowed per line')),
                      trailing: Text(
                        formatClock(
                            Duration(seconds: _settings.lineTargetSeconds)),
                        style: TextStyle(fontSize: 18, color: t.accent),
                      ),
                      onTap: _pickLineTarget,
                    ),
                  ),
                  _addition(
                    title: context.l10n.pick(
                        he: 'מטרונום בזמן כתיבה',
                        en: 'Metronome while writing'),
                    description: context.l10n.pick(
                        he: 'משמיע פעימה קבועה רק בזמן שהטיימר רץ; בהפסקה ובעצירה הוא שקט.',
                        en: 'Plays a steady beat only while the timer is running; it is silent during breaks and after stopping.'),
                    icon: Icons.graphic_eq,
                    value: _settings.metronomeEnabled,
                    onChanged: (value) =>
                        _save(_settings.copyWith(metronomeEnabled: value)),
                    control: Column(
                      children: [
                        Row(
                          children: [
                            Text(context.l10n.pick(he: 'קצב', en: 'Tempo')),
                            const Spacer(),
                            Text(
                                context.l10n.pick(
                                    he: '${_settings.metronomeBpm} פעימות בדקה',
                                    en:
                                        '${_settings.metronomeBpm} beats per minute'),
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
                        Row(
                          children: [
                            Text(context.l10n.pick(he: 'עוצמה', en: 'Volume')),
                            const Spacer(),
                            Text(
                              '${_settings.metronomeVolume}%',
                              style: TextStyle(fontSize: 16, color: t.accent),
                            ),
                          ],
                        ),
                        Slider(
                          min: 0,
                          max: 100,
                          divisions: 20,
                          value: _settings.metronomeVolume.toDouble(),
                          label: '${_settings.metronomeVolume}%',
                          onChanged: (value) => setState(() => _settings =
                              _settings.copyWith(
                                  metronomeVolume: value.round())),
                          onChangeEnd: (value) async {
                            final updated = _settings.copyWith(
                                metronomeVolume: value.round());
                            await _storage.setHomeAdditions(updated);
                            await _metronomeAudio.beat(updated.metronomeVolume);
                          },
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _previewMetronome,
                            icon: const Icon(Icons.volume_up_outlined),
                            label: Text(context.l10n.pick(
                                he: 'השמע פעימה לבדיקה', en: 'Preview beat')),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _addition(
                    title: context.l10n
                        .pick(he: 'יעד זמן לישיבה', en: 'Session time target'),
                    description: context.l10n.pick(
                        he: 'מציג במסך הבית כפתור לבחירת היעד של הישיבה הנוכחית. היעד עצמו נקבע שם, לפני הכתיבה או במהלכה.',
                        en: 'Shows a home-screen button for choosing the current session target. The target itself is set there, before or during writing.'),
                    icon: Icons.hourglass_bottom,
                    value: _settings.writingTargetEnabled,
                    onChanged: (value) =>
                        _save(_settings.copyWith(writingTargetEnabled: value)),
                    control: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(context.l10n.pick(
                            he: 'צליל בהגעה ליעד הישיבה',
                            en: 'Sound when the session target is reached',
                          )),
                          subtitle: Text(context.l10n.pick(
                            he: 'כבוי כברירת מחדל, כדי שלא להוסיף צליל שלא ביקשת.',
                            en: 'Off by default, so the app never adds an unrequested sound.',
                          )),
                          value: _settings.sessionTargetChimeEnabled,
                          onChanged: (value) => _save(_settings.copyWith(
                              sessionTargetChimeEnabled: value)),
                        ),
                        if (_settings.sessionTargetChimeEnabled)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: _previewAlert,
                              icon: const Icon(Icons.volume_up_outlined),
                              label: Text(context.l10n.pick(
                                he: 'בדיקת צליל היעד',
                                en: 'Preview target sound',
                              )),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _addition(
                    title: context.l10n
                        .pick(he: 'התראה בשעת סיום', en: 'Finish-time alert'),
                    description: NotificationService.isSupported
                        ? context.l10n.pick(
                            he:
                                'מציגה התראה ומשמיעה צליל בשעה שנקבעה, גם כשהאפליקציה ברקע.',
                            en:
                                'Shows a notification and plays a sound at the selected time, even in the background.')
                        : context.l10n.pick(
                            he: 'משמיעה התראה בשעה שנקבעה כל עוד האפליקציה פתוחה.',
                            en: 'Plays an alert at the selected time while the app is open.'),
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
                        showAppNote(
                            context,
                            context.l10n.pick(
                                he: 'ההתראה תחושב מחדש בתחילת ישיבת הכתיבה הבאה',
                                en: 'The alert will be recalculated when the next writing session starts'));
                      }
                    },
                    control: Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(context.l10n
                              .pick(he: 'שעת הסיום', en: 'Finish time')),
                          trailing: Text(_clockTime(_settings.endTimeMinutes),
                              style: TextStyle(fontSize: 18, color: t.accent)),
                          onTap: _pickEndTime,
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _previewAlert,
                            icon: const Icon(Icons.volume_up_outlined),
                            label: Text(context.l10n.pick(
                              he: 'בדיקת צליל ההתראה',
                              en: 'Preview alert sound',
                            )),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
