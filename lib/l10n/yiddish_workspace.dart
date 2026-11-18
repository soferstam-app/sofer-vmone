import 'yiddish_preview.dart';
import 'yiddish_workspace_copy.dart';

final _placeholders = RegExp(r'«(\d+)»');
final _leadingSpace = RegExp(r'^\s+');
final _trailingSpace = RegExp(r'\s+$');

String _keepEdges(String source, String translation) {
  final left = _leadingSpace.stringMatch(source) ?? '';
  final right = _trailingSpace.stringMatch(source) ?? '';
  return '$left${translation.trim()}$right';
}

RegExp _templatePattern(List<String> spans) =>
    RegExp('^${spans.map(RegExp.escape).join('(.*?)')}\$', dotAll: true);

class _YiddishTemplate {
  _YiddishTemplate(this.english, List<List<String>> hebrew, this.copy)
      : _hebrew = hebrew.map(_templatePattern).toList();

  final List<String> english;
  final List<RegExp> _hebrew;
  final String copy;
  late final RegExp _english = _templatePattern(english);

  String? translate(String he, String en) {
    final match = _english.firstMatch(en);
    if (match == null || !_hebrew.any((pattern) => pattern.hasMatch(he))) {
      return null;
    }
    final translated = copy.replaceAllMapped(_placeholders, (placeholder) {
      return match[int.parse(placeholder[1]!)]!;
    });
    return _keepEdges(en, translated);
  }
}

final _index = () {
  final byInitial = <String, List<_YiddishTemplate>>{};
  for (final (english, hebrew, copy) in yiddishTemplates) {
    final prefix = english.first;
    byInitial
        .putIfAbsent(prefix.isEmpty ? '' : prefix[0], () => [])
        .add(_YiddishTemplate(english, hebrew, copy));
  }
  return byInitial;
}();

String yiddishWorkspaceCopy(String he, String en) {
  final reviewed = yiddishLabels[he];
  if (reviewed != null) return reviewed;
  final exact = yiddishStaticCopy[en];
  if (exact != null) return _keepEdges(en, exact);
  if (en.isEmpty) return he;
  for (final candidates in [_index[en[0]], _index['']]) {
    if (candidates == null) continue;
    for (final template in candidates) {
      final translated = template.translate(he, en);
      if (translated != null) return translated;
    }
  }
  return he;
}

const _businessCopy = <String, String>{
  'יש להזין לפחות עמוד התחלה תקין': 'גיט אַרײַן אַ גילטיקן אָנהייב־עמוד',
  'יש להזין עמוד סיום תקין או להשאיר אותו ריק':
      'גיט אַרײַן אַ גילטיקן סוף־עמוד אָדער לאָזט דאָס פֿעלד ליידיק',
  'עמוד הסיום לא יכול להיות לפני עמוד ההתחלה':
      'דער סוף־עמוד קען נישט קומען פֿאַרן אָנהייב־עמוד',
  'יש להזין שורות תקינות (משורה, עד שורה)':
      'גיט אַרײַן גילטיקע שורות, פֿון וועלכער שורה ביז וועלכער שורה',
  'שורה התחלה חייבת להיות קטנה משורה סיום':
      'די אָנהייב־שורה מוז זײַן פֿאַר דער סוף־שורה',
  'מספר שורה אינו יכול להיות שלילי':
      'דער שורה־נומער קען נישט זײַן קלענער פֿון נול',
  'יש להזין מספר זוג כדי לשמור על סדר הפרשיות בתוך הסט':
      'גיט אַרײַן דעם פּאָר־נומער כּדי צו האַלטן דעם סדר פֿון די פּרשיות',
  'המזוזה שנבחרה כבר אינה חלקית. יש לרענן ולבחור שוב':
      'די אויסגעקליבענע מזוזה איז שוין פֿאַרטיק. דערהײַנטיקט די רשימה און קלײַבט ווידער',
  'יש להזין עד איזו שורה הגעת':
      'גיט אַרײַן ביז וועלכער שורה איר זענט אָנגעקומען',
  'יש להזין כמות': 'גיט אַרײַן אַ צאָל',
};

final _businessTemplates = <(RegExp, String)>[
  (
    RegExp(r'^מספר העמוד חורג מהגדרת הספר \((\d+)\)$'),
    'דער עמוד־נומער גייט ווײַטער ווי דער סוף פֿונעם ספר («1»)'
  ),
  (
    RegExp(r'^עמוד הסיום חורג מהגדרת הספר \((\d+)\)$'),
    'דער סוף־עמוד גייט ווײַטער ווי דער סוף פֿונעם ספר («1»)'
  ),
  (
    RegExp(r'^טווח של יותר מ־(\d+) עמודים בהזנה אחת — יש לפצל אותו$'),
    'טיילט אויף אַ רישום פֿון מער ווי «1» עמודים אויף באַזונדערע רישומים'
  ),
  (
    RegExp(r'^שורת ההתחלה חייבת להיות בין 1 ל־(\d+)$'),
    'די אָנהייב־שורה מוז זײַן צווישן 1 און «1»'
  ),
  (
    RegExp(r'^שורת הסיום חייבת להיות בין 1 ל־(\d+)$'),
    'די סוף־שורה מוז זײַן צווישן 1 און «1»'
  ),
  (
    RegExp(r'^מספר השורות חורג מהגדרת העמוד \((\d+)\)$'),
    'די צאָל שורות איז גרעסער ווי די צאָל שורות אויפֿן עמוד («1»)'
  ),
  (
    RegExp(r'^במזוזה יש רק (\d+) שורות$'),
    'אין אַ מזוזה זענען דאָ בלויז «1» שורות'
  ),
  (
    RegExp(r'^בתפילין (ראש|יד) יש עד (\d+) שורות$'),
    'אין תּפֿילין של «1» זענען דאָ ביז «2» שורות'
  ),
  (
    RegExp(r'^פרשיית (.+) בזוג (\d+) כבר התחילה$'),
    'די פּרשה «1» אין פּאָר «2» איז שוין אָנגעהויבן'
  ),
  (
    RegExp(r'^אי אפשר להתחיל את (.+) לפני שהפרשייה (.+) הסתיימה באותו סט$'),
    'פֿאַרענדיקט די פּרשה «2» אינעם זעלבן פּאָר איידער איר הייבט אָן «1»'
  ),
  (
    RegExp(r'^מזוזה (\d+) כבר נכתבה עד שורה (\d+)$'),
    'מזוזה «1» איז שוין געשריבן ביז שורה «2»'
  ),
  (RegExp(r'^פרשיית (.+) כבר הסתיימה$'), 'די פּרשה «1» איז שוין פֿאַרטיק'),
  (
    RegExp(r'^פרשיית (.+) נפסלה; יש להסיר אותה לפני שמתחילים מחדש$'),
    'די פּרשה «1» איז פּסול. נעמט זי אַוועק איידער איר הייבט אָן פֿון ס׳נײַ'
  ),
  (
    RegExp(r'^אי אפשר לכתוב את (.+) לפני שהפרשייה הקודמת הסתיימה באותו סט$'),
    'פֿאַרענדיקט די פֿריִערדיקע פּרשה אינעם זעלבן פּאָר איידער איר שרײַבט «1»'
  ),
];

String yiddishBusinessMessage(String he) {
  final exact = _businessCopy[he];
  if (exact != null) return exact;
  for (final (pattern, copy) in _businessTemplates) {
    final match = pattern.firstMatch(he);
    if (match != null) {
      return copy.replaceAllMapped(
          _placeholders, (part) => match[int.parse(part[1]!)]!);
    }
  }
  return he;
}
