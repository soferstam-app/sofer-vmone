// What the first screens say, and when they are shown at all.
//
// The content lives here rather than inside the widget so it can be read and
// checked without building anything: the wording is the feature, and a screen
// nobody can test the wording of is a screen whose wording drifts.

/// How a page is laid out. Five pages, four shapes — the last one is the only
/// page that asks for something rather than telling.
enum OnboardingKind { prose, steps, facts, list, appearance }

/// A named thing with a sentence under it, which is three of the five pages.
class OnboardingItem {
  final String label;
  final String text;

  const OnboardingItem(this.label, this.text);
}

class OnboardingPage {
  final OnboardingKind kind;
  final String title;

  /// Full sentences, shown as paragraphs.
  final List<String> paragraphs;

  /// Label-and-sentence pairs.
  final List<OnboardingItem> items;

  /// The closing sentence under the body, where there is one.
  final String? footnote;

  const OnboardingPage({
    required this.kind,
    required this.title,
    this.paragraphs = const [],
    this.items = const [],
    this.footnote,
  });
}

/// Five pages, in order.
///
/// The audience is a sofer who may never have been taught what an app is, so
/// these say what the thing does rather than how it feels. The second page is
/// the one the whole screen exists for: everything else in the app can be found
/// by looking, but nothing on screen explains why a *project* has to exist
/// before a minute can be measured.
const List<OnboardingPage> onboardingPages = [
  OnboardingPage(
    kind: OnboardingKind.prose,
    title: 'סופר ומונה',
    paragraphs: [
      'תוכנה לסופרי סת״ם שסופרת במקומך.',
      'בזמן שאתה כותב היא מודדת כמה זמן ישבת, כמה שורות כתבת וכמה הרווחת — '
          'בלי שתרשום כלום על פתק ובלי שתחשב כלום בראש.',
    ],
    // The three questions a person who does not trust computers asks before
    // he begins, answered before he has to ask them.
    footnote: 'הכל נשמר במכשיר שלך בלבד. '
        'אין הרשמה, אין תשלום, ואין צורך באינטרנט.',
  ),
  OnboardingPage(
    kind: OnboardingKind.steps,
    title: 'שלושה דברים, וזה הכל',
    items: [
      OnboardingItem(
        'פרויקט',
        'פעם אחת בהתחלה אתה אומר לתוכנה מה אתה כותב: ספר תורה, תפילין או '
            'מזוזה. כמה עמודים, כמה שורות בעמוד, ובכמה סיכמת. מכאן היא יודעת '
            'לחשב את כל השאר.',
      ),
      OnboardingItem(
        'ישיבה',
        'כשאתה מתיישב לכתוב אתה לוחץ "התחלה", וכשאתה קם "סיום". השעון רץ '
            'לבד, גם אם סגרת את התוכנה. יצאת להפסקה? יש כפתור, והזמן הזה לא '
            'נספר לך.',
      ),
      OnboardingItem(
        'שורה',
        'בכל שורה שגמרת אתה לוחץ על הכפתור הגדול "סיימתי שורה". זה כל מה '
            'שאתה עושה תוך כדי כתיבה.',
      ),
    ],
  ),
  OnboardingPage(
    kind: OnboardingKind.facts,
    title: 'אחרי שבוע היא כבר יודעת לומר לך',
    items: [
      OnboardingItem('◷', 'שורה לוקחת לך 4 דקות ו-20 שניות בממוצע'),
      OnboardingItem('₪', 'אתה מרוויח 68 ₪ לשעה — בפועל, אחרי הוצאות'),
      OnboardingItem('☷', 'בקצב הזה תסיים את הספר בכ״ג בשבט'),
      OnboardingItem('▤', 'היום עליך להגיע לעמוד י״ד'),
    ],
    footnote: 'הלוח מדלג על ימים שאינך כותב בהם, ואם פיגרת הוא פורס את ההפרש '
        'על הימים שנותרו — כדי שלא תצטרך לחשב את זה בעצמך ביום שבו אתה כבר '
        'בפיגור.',
  ),
  OnboardingPage(
    kind: OnboardingKind.list,
    title: 'ומה עוד יש בפנים',
    items: [
      OnboardingItem('הוצאות ותשלומים',
          'כמה קלף וקולמוס קנית, וכמה כסף באמת כבר הגיע אליך'),
      OnboardingItem('הגהה', 'מי הגיה, מתי, ומה נמצא'),
      OnboardingItem('דוח שנתי לרואה חשבון',
          'הכנסות והוצאות חודש בחודשו, מוכן להדפסה'),
      OnboardingItem('הצעת מחיר',
          'כמה לבקש על עבודה חדשה, לפי הקצב האמיתי שלך ולא לפי הערכה'),
      OnboardingItem('תזכורת יומית', 'גיבוי לקובץ, ולוח עברי מלא'),
    ],
  ),
  OnboardingPage(
    kind: OnboardingKind.appearance,
    title: 'איך זה ייראה',
    footnote: 'לחיצה מחילה מיד, ואפשר לשנות בכל רגע בהגדרות. אם תבחר מעבר '
        'אוטומטי — התוכנה תלבש את גרסת הלילה של הערכה שבחרת, מצאת הכוכבים ועד '
        'עלות השחר.',
  ),
];

/// Whether to open with the explanation.
///
/// Not simply "has it been seen": a sofer updating from an older version has
/// never seen it and does not need it. He has been working for months, and
/// being told what a project is would be an insult before it was a help. Any
/// project or any recorded sitting is proof enough that the explanation is
/// behind him — no new setting required, and nothing to migrate.
bool shouldShowOnboarding({
  required bool seen,
  required bool hasProjects,
  required bool hasHistory,
}) =>
    !seen && !hasProjects && !hasHistory;
