import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../logic/diagnostic_report.dart';
import '../logic/save_user_file.dart';
import '../widgets/feedback.dart';

enum _ReportText {
  title('ייצוא דוח תקלה', 'Export diagnostic report',
      'עקספּאָרטירן אַ פֿעלער־באַריכט'),
  local(
      'הדוח נשמר בקובץ. אפשר לצרף אותו להודעה לתמיכה.',
      'The report is saved as a file that you can attach to a support message.',
      'דער באַריכט ווערט אָפּגעהיט ווי אַ טעקע, וואָס איר קענט צולייגן צו אַ מעלדונג פֿאַר שטיצע.'),
  include('כלול את נתוני העבודה', 'Include work data',
      'אַרײַננעמען די אַרבעטס־דאַטן'),
  workData(
      'כולל שמות פרויקטים, רשומות כתיבה, הזמנות, הוצאות, תשלומים והגדרות. הנתונים עשויים לכלול פרטי לקוחות.',
      'Includes project names, writing records, orders, expenses, payments and settings. These may include client details.',
      'דאָס נעמט אַרײַן פּראָיעקט־נעמען, שרײַב־רשומות, באַשטעלונגען, הוצאות, צאָלונגען און אײַנשטעלונגען. עס קענען זײַן דערין פּרטים פֿון קונים.'),
  save('שמור דוח', 'Save report', 'אָפּהיטן דעם באַריכט'),
  saving('מכין דוח…', 'Preparing report…', 'מען גרייט צו דעם באַריכט…'),
  saved('דוח התקלה נשמר.', 'The diagnostic report was saved.',
      'דער פֿעלער־באַריכט איז אָפּגעהיט געוואָרן.'),
  failed(
      'לא ניתן היה לייצא את הדוח. אפשר לנסות שוב.',
      'Could not export the report. You can try again.',
      'מען האָט נישט געקענט עקספּאָרטירן דעם באַריכט. איר קענט פּרוּוון ווידער.'),
  failedWithData(
      'לא ניתן היה לייצא את הדוח. אפשר להסיר את הסימון של נתוני העבודה ולנסות שוב.',
      'Could not export the report. You can deselect work data and try again.',
      'מען האָט נישט געקענט עקספּאָרטירן דעם באַריכט. איר קענט אָפּנעמען דעם סימן בײַ די אַרבעטס־דאַטן און פּרוּוון ווידער.');

  const _ReportText(this.he, this.en, this.yi);
  final String he, en, yi;

  String inLanguage(AppLocalizations l10n) =>
      switch (l10n.locale.languageCode) {
        'en' => en,
        'yi' => yi,
        _ => he,
      };
}

String diagnosticReportTitle(BuildContext context) =>
    _ReportText.title.inLanguage(context.l10n);

Future<void> showDiagnosticReportDialog(BuildContext context,
    {bool workDataAvailable = true}) async {
  final l10n = context.l10n;
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _DiagnosticReportDialog(workDataAvailable: workDataAvailable),
  );
  if (saved == true && context.mounted) {
    showAppSuccess(context, _ReportText.saved.inLanguage(l10n));
  }
}

class _DiagnosticReportDialog extends StatefulWidget {
  const _DiagnosticReportDialog({required this.workDataAvailable});

  final bool workDataAvailable;

  @override
  State<_DiagnosticReportDialog> createState() =>
      _DiagnosticReportDialogState();
}

class _DiagnosticReportDialogState extends State<_DiagnosticReportDialog> {
  late bool _includeWorkData = widget.workDataAvailable;
  bool _saving = false;
  _ReportText? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await Diagnostics.export(includeWorkData: _includeWorkData);
      if (!mounted) return;
      final stamp =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
      final path = await saveUserFile(
        dialogTitle: diagnosticReportTitle(context),
        fileName: 'sofer-vmone-diagnostic-$stamp.json',
        bytes: bytes,
      );
      if (mounted && path != null) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            _includeWorkData ? _ReportText.failedWithData : _ReportText.failed);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(diagnosticReportTitle(context)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_ReportText.local.inLanguage(l10n)),
          if (widget.workDataAvailable)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeWorkData,
              title: Text(_ReportText.include.inLanguage(l10n)),
              subtitle: Text(_ReportText.workData.inLanguage(l10n)),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _includeWorkData = value == true),
            ),
          if (_error case final error?)
            Semantics(liveRegion: true, child: Text(error.inLanguage(l10n))),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text((_saving ? _ReportText.saving : _ReportText.save)
              .inLanguage(l10n)),
        ),
      ],
    );
  }
}
