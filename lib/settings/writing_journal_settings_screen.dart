import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../logic/writing_journal.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sofer_widgets.dart';

class WritingJournalSettingsScreen extends StatefulWidget {
  const WritingJournalSettingsScreen({super.key});

  @override
  State<WritingJournalSettingsScreen> createState() =>
      _WritingJournalSettingsScreenState();
}

class _WritingJournalSettingsScreenState
    extends State<WritingJournalSettingsScreen> {
  final StorageService _storage = StorageService();
  WritingJournalSettings _settings = WritingJournalSettings.defaults;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _storage.getWritingJournalSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  Future<void> _set(WritingJournalSettings next) async {
    setState(() => _settings = next);
    await _storage.setWritingJournalSettings(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.pick(
          he: 'הגדרות יומן כתיבה',
          en: 'Writing Journal settings',
        )),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: SoferTokens.of(context).isRules
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(12),
              children: [
                if (SoferTokens.of(context).isRules)
                  const SoferRule(strong: true),
                SwitchListTile(
                  title: Text(context.l10n.pick(
                    he: 'יומן כתיבה כמסך הבית',
                    en: 'Use the Writing Journal as Home',
                  )),
                  subtitle: Text(context.l10n.pick(
                    he: 'הטיימר נשאר זמין מתוך היומן בלחיצה אחת',
                    en: 'The timer remains one tap away from the journal',
                  )),
                  value: _settings.useAsHome,
                  onChanged: (value) =>
                      _set(_settings.copyWith(useAsHome: value)),
                ),
                const Divider(),
                ListTile(
                  title: Text(context.l10n.pick(
                    he: 'תאריכים בטבלה',
                    en: 'Dates in the table',
                  )),
                  subtitle: Text(_dateDisplayLabel(_settings.dateDisplay)),
                ),
                RadioGroup<JournalDateDisplay>(
                  groupValue: _settings.dateDisplay,
                  onChanged: (value) {
                    if (value != null) {
                      _set(_settings.copyWith(dateDisplay: value));
                    }
                  },
                  child: Column(
                    children: [
                      for (final value in JournalDateDisplay.values)
                        RadioListTile<JournalDateDisplay>(
                          value: value,
                          title: Text(_dateDisplayLabel(value)),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  title: Text(context.l10n.pick(
                    he: 'לוח פרשיות ארץ ישראל',
                    en: 'Israel Parashah cycle',
                  )),
                  subtitle: Text(_settings.inIsrael
                      ? context.l10n.pick(
                          he: 'פרשת השבוע לפי ארץ ישראל',
                          en: 'Weekly Parashah according to Israel')
                      : context.l10n.pick(
                          he: 'פרשת השבוע לפי חו״ל',
                          en: 'Weekly Parashah according to the diaspora')),
                  value: _settings.inIsrael,
                  onChanged: (value) =>
                      _set(_settings.copyWith(inIsrael: value)),
                ),
                SwitchListTile(
                  title: Text(context.l10n.pick(
                    he: 'הצג פרשת שבוע',
                    en: 'Show weekly Parashah',
                  )),
                  value: _settings.showParsha,
                  onChanged: (value) =>
                      _set(_settings.copyWith(showParsha: value)),
                ),
                const Divider(),
                _columnToggle(
                  context.l10n.pick(he: 'עמודת פרויקט', en: 'Project column'),
                  _settings.showProject,
                  (value) => _set(_settings.copyWith(showProject: value)),
                ),
                _columnToggle(
                  context.l10n
                      .pick(he: 'עמודת זמן כתיבה', en: 'Writing-time column'),
                  _settings.showTime,
                  (value) => _set(_settings.copyWith(showTime: value)),
                ),
                _columnToggle(
                  context.l10n.pick(he: 'עמודת הערות', en: 'Notes column'),
                  _settings.showNotes,
                  (value) => _set(_settings.copyWith(showNotes: value)),
                ),
                const Divider(),
                ListTile(
                  title: Text(context.l10n.pick(
                    he: 'שורות ריקות לכל יום בהדפסה',
                    en: 'Blank rows per day when printing',
                  )),
                  subtitle: Text(context.l10n.pick(
                    he: '${_settings.blankRowsPerDay} שורות',
                    en: '${_settings.blankRowsPerDay} rows',
                  )),
                  trailing: DropdownButton<int>(
                    value: _settings.blankRowsPerDay,
                    items: [
                      for (var value = 1; value <= 6; value++)
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _set(_settings.copyWith(blankRowsPerDay: value));
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.l10n.pick(
                      he: 'אותן עמודות משמשות במסך, בדף המודפס ובקובץ Excel. השדה „מה נכתב” נשאר תמיד, כדי שהטבלה תוכל להפוך לרשומת כתיבה רגילה.',
                      en: 'The same columns are used on screen, on paper, and in Excel. “Written” is always kept so every row can become a normal work record.',
                    ),
                    style: TextStyle(
                      color: SoferTokens.of(context).inkMuted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _columnToggle(
          String title, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(title: Text(title), value: value, onChanged: onChanged);

  String _dateDisplayLabel(JournalDateDisplay value) => switch (value) {
        JournalDateDisplay.hebrew =>
          context.l10n.pick(he: 'עברי', en: 'Hebrew'),
        JournalDateDisplay.gregorian =>
          context.l10n.pick(he: 'לועזי', en: 'Gregorian'),
        JournalDateDisplay.both =>
          context.l10n.pick(he: 'עברי ולועזי', en: 'Hebrew and Gregorian'),
      };
}
