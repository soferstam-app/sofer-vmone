import '../models.dart';

enum StamScript {
  beitYosef('beit-yosef', 'בית יוסף', 'StamBeitYosef'),
  ari('ari', 'האר״י', 'StamAri'),
  sephardi('sephardi', 'ספרדי', 'StamSephardi'),
  chabad('chabad', 'חב״ד', 'StamChabad');

  final String id;
  final String label;
  final String family;
  const StamScript(this.id, this.label, this.family);
  static StamScript fromId(Object? id) =>
      values.firstWhere((s) => s.id == id, orElse: () => beitYosef);
}

class TefillinPreferences {
  static bool usesWords(Project p) =>
      p.type == ProjectType.tefillin &&
      p.extraFields['tefillinWordEntry'] == true;
  static StamScript script(Project p) =>
      StamScript.fromId(p.extraFields['tefillinScript']);
  static Project update(Project p, {bool? words, StamScript? script}) =>
      p.copyWith(extraFields: {
        ...p.extraFields,
        'tefillinWordEntry': words ?? usesWords(p),
        'tefillinScript': (script ?? TefillinPreferences.script(p)).id,
      });
}

/// A font is a presentation choice, never the identity of a word.
class TefillinText {
  static const version = 'tefillin-canonical-1';
  final int parshiya;
  final List<String> words;
  late final List<int> letterBoundaries = [
    0,
    for (var i = 1; i <= words.length; i++)
      words.take(i).fold<int>(0, (sum, w) => sum + w.length),
  ];
  TefillinText._(this.parshiya, String text)
      : words = List.unmodifiable(text.split(' '));
  int get letters => letterBoundaries.last;
  String wordAt(int boundary) =>
      boundary <= 0 || boundary > words.length ? '' : words[boundary - 1];
  static TefillinText of(int parshiya) => all[parshiya - 1];

  // Source: supplied Beit Yosef tikkun, Shel Yad. The large ayin/dalet
  // in Shema were read from their physical positions, not extraction rows.
  // No niqqud, punctuation, line geometry or font-specific variants.
  static final all = [
    TefillinText._(1,
        'וידבר יהוה אל משה לאמר קדש לי כל בכור פטר כל רחם בבני ישראל באדם ובבהמה לי הוא ויאמר משה אל העם זכור את היום הזה אשר יצאתם ממצרים מבית עבדים כי בחזק יד הוציא יהוה אתכם מזה ולא יאכל חמץ היום אתם יצאים בחדש האביב והיה כי יביאך יהוה אל ארץ הכנעני והחתי והאמרי והחוי והיבוסי אשר נשבע לאבתיך לתת לך ארץ זבת חלב ודבש ועבדת את העבדה הזאת בחדש הזה שבעת ימים תאכל מצת וביום השביעי חג ליהוה מצות יאכל את שבעת הימים ולא יראה לך חמץ ולא יראה לך שאר בכל גבלך והגדת לבנך ביום ההוא לאמר בעבור זה עשה יהוה לי בצאתי ממצרים והיה לך לאות על ידך ולזכרון בין עיניך למען תהיה תורת יהוה בפיך כי ביד חזקה הוצאך יהוה ממצרים ושמרת את החקה הזאת למועדה מימים ימימה'),
    TefillinText._(2,
        'והיה כי יבאך יהוה אל ארץ הכנעני כאשר נשבע לך ולאבתיך ונתנה לך והעברת כל פטר רחם ליהוה וכל פטר שגר בהמה אשר יהיה לך הזכרים ליהוה וכל פטר חמר תפדה בשה ואם לא תפדה וערפתו וכל בכור אדם בבניך תפדה והיה כי ישאלך בנך מחר לאמר מה זאת ואמרת אליו בחזק יד הוציאנו יהוה ממצרים מבית עבדים ויהי כי הקשה פרעה לשלחנו ויהרג יהוה כל בכור בארץ מצרים מבכר אדם ועד בכור בהמה על כן אני זבח ליהוה כל פטר רחם הזכרים וכל בכור בני אפדה והיה לאות על ידכה ולטוטפת בין עיניך כי בחזק יד הוציאנו יהוה ממצרים'),
    TefillinText._(3,
        'שמע ישראל יהוה אלהינו יהוה אחד ואהבת את יהוה אלהיך בכל לבבך ובכל נפשך ובכל מאדך והיו הדברים האלה אשר אנכי מצוך היום על לבבך ושננתם לבניך ודברת בם בשבתך בביתך ובלכתך בדרך ובשכבך ובקומך וקשרתם לאות על ידך והיו לטטפת בין עיניך וכתבתם על מזזות ביתך ובשעריך'),
    TefillinText._(4,
        'והיה אם שמע תשמעו אל מצותי אשר אנכי מצוה אתכם היום לאהבה את יהוה אלהיכם ולעבדו בכל לבבכם ובכל נפשכם ונתתי מטר ארצכם בעתו יורה ומלקוש ואספת דגנך ותירשך ויצהרך ונתתי עשב בשדך לבהמתך ואכלת ושבעת השמרו לכם פן יפתה לבבכם וסרתם ועבדתם אלהים אחרים והשתחויתם להם וחרה אף יהוה בכם ועצר את השמים ולא יהיה מטר והאדמה לא תתן את יבולה ואבדתם מהרה מעל הארץ הטבה אשר יהוה נתן לכם ושמתם את דברי אלה על לבבכם ועל נפשכם וקשרתם אתם לאות על ידכם והיו לטוטפת בין עיניכם ולמדתם אתם את בניכם לדבר בם בשבתך בביתך ובלכתך בדרך ובשכבך ובקומך וכתבתם על מזוזות ביתך ובשעריך למען ירבו ימיכם וימי בניכם על האדמה אשר נשבע יהוה לאבתיכם לתת להם כימי השמים על הארץ'),
  ];
}

/// Stored as an extension so older readers preserve it on backup round trips.
/// Legacy amount/line fields are zero: old readers must not count a word
/// stretch as a complete parshiya. Use the new app to read its production.
class TefillinWordRange {
  static const key = 'tefillinWords';
  final int parshiya;
  final int from;
  final int until;
  final int baselineWord;
  final double baselineFraction;
  final String script;
  const TefillinWordRange(
      {required this.parshiya,
      required this.from,
      required this.until,
      this.baselineWord = 0,
      this.baselineFraction = 0,
      required this.script});

  TefillinText get text => TefillinText.of(parshiya);
  double get fractionAdded =>
      (1 - baselineFraction) *
      (text.letterBoundaries[until] - text.letterBoundaries[from]) /
      (text.letters - text.letterBoundaries[baselineWord]);
  Map<String, dynamic> toJson() => {
        'version': TefillinText.version,
        'from': from,
        'until': until,
        'baselineWord': baselineWord,
        'baselineFraction': baselineFraction,
        'script': script,
      };
  static bool isWordRecord(WorkSession s) => s.extraFields.containsKey(key);
  static TefillinWordRange? read(WorkSession s) {
    final raw = s.extraFields[key];
    final p = s.parshiya;
    if (raw is! Map ||
        raw['version'] != TefillinText.version ||
        p == null ||
        p < 1 ||
        p > 4 ||
        (s.pairIndex ?? 0) < 1 ||
        !const {'head', 'hand'}.contains(s.tefillinType)) {
      return null;
    }
    final from = raw['from'], until = raw['until'];
    final base = raw['baselineWord'], fraction = raw['baselineFraction'];
    if (from is! int ||
        until is! int ||
        base is! int ||
        fraction is! num ||
        !fraction.isFinite ||
        fraction < 0 ||
        fraction >= 1 ||
        base < 0 ||
        base > from ||
        from < 0 ||
        until <= from ||
        until > TefillinText.of(p).words.length ||
        (fraction == 0 && base != 0) ||
        (fraction > 0 && base == 0)) {
      return null;
    }
    return TefillinWordRange(
        parshiya: p,
        from: from,
        until: until,
        baselineWord: base,
        baselineFraction: fraction.toDouble(),
        script: StamScript.fromId(raw['script']).id);
  }
}
