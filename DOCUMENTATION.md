# תיעוד טכני – סופר ומונה (Sofer v'Mone)

> קובץ תיעוד מרכזי לפרויקט. מתעד ארכיטקטורה, מודל נתונים, לוגיקה עסקית, החלטות תכנון ומצב נוכחי.
> עודכן לאחרונה: 26.07.2026 · גרסת קוד: `0.3.0+1` (עם שינויים בפיתוח שטרם שוחררו – ראו פרק 12)
>
> **מצב בדיקות:** `flutter analyze` – 0 בעיות בקוד הפרויקט (130 הנותרות כולן בחבילת `kosher_dart` החיצונית) · `flutter test` – 12/12 עוברים · בניית Windows release מאומתת. ה-SDK במכונה: `E:\Android\flutter` (3.38.7 / Dart 3.10.7), אינו ב-PATH.

---

## 1. סקירה כללית

אפליקציית **Flutter** לניהול, מעקב ותיעוד עבודתו של סופר סת"ם: ניהול פרויקטים (ספר תורה, תפילין, מזוזות), מדידת זמני כתיבה, חישוב הספקים ורווחים, סיכומים יומיים/חודשיים/פרויקטיים, ניהול הוצאות וגיבוי ל-Google Drive.

| נתון | ערך |
|---|---|
| שם החבילה | `sofer_vmone` |
| Application ID (אנדרואיד) | `com.example.stamsofer` ⚠️ (ראו פרק 13 – חוב טכני) |
| Dart SDK | `>=3.0.0 <4.0.0` |
| פלטפורמות פעילות | Android, Windows (יש תיקיות ios/macos/linux/web אך אינן מתוחזקות) |
| שפה / כיווניות | עברית בלבד (`Locale('he','IL')`), Material 3, seed color: deepPurple |
| אתר הפרויקט | https://soferstam-app.github.io/sofer-vmone/ (מוגש מתיקיית `docs/`) |

---

## 2. מבנה הפרויקט

```
lib/
├── main.dart                    כניסה לאפליקציה, HttpOverrides לנטפרי, אתחול window_manager/התראות
├── home_screen.dart             ★ המסך הראשי – טיימר, מצב חכם, דיאלוג הזנה, ניווט (≈2,300 שורות)
├── summary_screen.dart          סיכום יומי + סיכום חודשי + עריכת היסטוריה
├── project_summary_screen.dart  סיכום ברמת פרויקט + גריד עמודים/פרשיות
├── projects_screen.dart         CRUD פרויקטים + דיאלוג יצירה/עריכה + אודות
├── expenses_screen.dart         מסך הוצאות (הוספה/עריכה/מחיקה, קטגוריות מוצעות)
├── settings_screen.dart         הגדרות, התחברות Google, סנכרון ידני, בדיקת עדכונים
├── recycle_bin_screen.dart      סל מחזור – שחזור/מחיקה סופית של פרויקטים
├── logic/                       ★ לוגיקה טהורה – בלי Flutter, נבדקת בטסטים
│   ├── production_calculator.dart   הספק: שורות/מזוזות/פרשיות לפי סוג
│   ├── profit_calculator.dart       יחידות לחיוב, רווח, ₪/שעה
│   ├── session_logic.dart           טווח זמן, ולידציית שורות, בדיקת חפיפה
│   ├── date_logic.dart              יום עבודה לפי שעת מעבר יום
│   └── id_generator.dart            מזהים ייחודיים חוצי-מכשירים
├── models.dart                  Project, WorkSession, Expense
├── storage_service.dart         עטיפה ל-SharedPreferences (כל המפתחות במקום אחד)
├── backup_service.dart          בניית קובץ גיבוי מלא + שמירה/שיתוף
├── platform_support.dart        הפשטת יכולות פלטפורמה (isDesktop וכו')
├── sync_service.dart            סנכרון דו-כיווני מול Google Drive (Singleton)
├── notification_service.dart    התראות מקומיות (תזכורת יומית + סוף הפסקה)
├── timer_foreground_task.dart   Foreground Service לאנדרואיד – טיימר רץ ברקע
├── hebrew_utils.dart            גימטריה, פורמט תאריך עברי/לועזי
├── work_days_calculator.dart    חישוב ימי עבודה (שבת/חג/שישי) וצפי סיום
├── netfree_cert.dart            תעודת CA של נטפרי כמחרוזת מוטמעת (~252KB)
└── history_screen.dart          קובץ ריק – שריד, ניתן למחיקה

packages/kosher_dart/            עותק מקומי של kosher_dart (path dependency)
assets/icon/ICON.png             אייקון האפליקציה
docs/                            אתר הפרויקט (GitHub Pages) + מדיניות פרטיות + GIF/MP4 הדגמה
test/widget_test.dart            טסט ברירת מחדל של Flutter (לא מותאם לפרויקט)
```

**קבצים ראשיים לפי גודל:** `home_screen.dart` (87KB) ו-`summary_screen.dart` (43KB) הם הליבה – רוב הלוגיקה העסקית יושבת בהם.

---

## 3. ארכיטקטורה וזרימת נתונים

אין ניהול state חיצוני (אין Provider/Riverpod/Bloc). הארכיטקטורה פשוטה וממוקדת:

```
      ┌────────────────────────────────────────────┐
      │  _SoferHomeState (home_screen.dart)        │  ← מחזיק את המקור היחיד לאמת:
      │  projects: List<Project>                   │     projects + history בזיכרון
      │  history:  List<WorkSession>               │
      └───────┬──────────────────────┬─────────────┘
              │ מעביר ב-constructor  │ מקבל חזרה ב-Navigator.pop / callback
              ▼                      ▼
   SummaryScreen / ProjectsScreen / ExpensesScreen / SettingsScreen ...
              │
              ▼
      StorageService  ──►  SharedPreferences (JSON מקומי)
              │
              ▼
      SyncService     ──►  Google Drive (sofer_vmone_backup.json)
```

**עקרונות:**
- כל המסכים מקבלים את הרשימות כפרמטרים ומחזירים שינויים למעלה; `home_screen` שומר ומסנכרן.
- כל שמירה מקומית מלווה בקריאה ל-`SyncService.instance.syncData()` (fire-and-forget).
- מסננים גלובליים: המסך הראשי טוען רק פריטים עם `isDeleted == false`.

---

## 4. מודל הנתונים (`models.dart`)

### `enum ProjectType { sefer, mezuza, tefillin }`
⚠️ הסריאליזציה משתמשת ב-`type.index` — **אין לשנות את סדר הערכים** (ישבור נתונים קיימים).

### `Project`
| שדה | טיפוס | תיאור |
|---|---|---|
| `id` | String | מזהה ייחודי (timestamp) |
| `name` | String | שם הפרויקט |
| `type` | ProjectType | ספר / מזוזה / תפילין |
| `price` | double | מחיר ליחידה (עמוד / מזוזה / סט) |
| `expenses` | double | הוצאות ליחידה (מנוכה מהמחיר בחישוב רווח) |
| `targetDaily` | int | יעד יומי |
| `targetMonthly` | int | יעד חודשי |
| `dailyGoalInLines` | bool | **ספר תורה בלבד**: יעד יומי נמדד בשורות (true) או בעמודים (false) |
| `totalPages` | int? | מספר עמודים בספר (ברירת מחדל בממשק: 245) |
| `linesPerPage` | int? | שורות לעמוד (ברירת מחדל: 42) |
| `lastUpdated` | DateTime | חותמת לצורכי מיזוג בסנכרון |
| `isDeleted` | bool | מחיקה לוגית (Soft Delete) |
| `clientEmail` | String? | לשליחת עדכון ללקוח |
| `targetCompletionDate` | DateTime? | תאריך יעד לסיום |

`==`/`hashCode` מבוססים על `id` בלבד – מאפשר `toSet()` לניקוי כפילויות.

### `WorkSession`
| שדה | טיפוס | תיאור |
|---|---|---|
| `id` | String | מזהה (timestamp; בטווח עמודים: `<timestamp>_<page>`) |
| `projectId` | String | שיוך לפרויקט |
| `startTime` / `endTime` | DateTime | תחילת וסיום העבודה; `duration` = ההפרש |
| `amount` | int | **משמעות תלוית סוג**: בספר תורה = **מספר העמוד**; במזוזה = מספר מזוזות; בתפילין = כמות סטים/יחידות |
| `startLine` / `endLine` | int | טווח שורות (בספר); במזוזה/תפילין `endLine` = שורה אחרונה שנכתבה ביחידה החלקית |
| `tefillinType` | String? | `'head'` / `'hand'` |
| `parshiya` | int? | 1=קדש, 2=והיה כי יביאך, 3=שמע, 4=והיה אם שמוע |
| `description` | String | טקסט מוכן לתצוגה ("עמוד יא (1-42)") |
| `isManual` | bool | הוזן ידנית ולא נמדד בטיימר |
| `backlogOnly` | bool | **רשומת "רקע"** – נספרת רק בהספק הכולל של הפרויקט; מוחרגת מרווח, ממוצעים, יעד יומי וסיכומים יומיים |
| `lastUpdated`, `isDeleted` | | כמו ב-Project |

### `Expense`
`id`, `product` (קטגוריה/מוצר), `date` (תאריך ההוצאה), `amount`, `lastUpdated`, `isDeleted`.
מחיקה היא **לוגית** – אחרת המיזוג מול הדרייב היה משחזר את הרשומה. `lastUpdated` נפרד מ-`date` כי עריכת סכום אינה משנה את תאריך ההוצאה, ובלעדיו העריכה לא הייתה מנצחת במיזוג. גיבויים ישנים ללא השדות החדשים נטענים עם נפילה חזרה ל-`date`.

---

## 5. אחסון מקומי (`storage_service.dart`)

הכול ב-`SharedPreferences`, כ-JSON. מפתחות:

| מפתח | תוכן | ברירת מחדל |
|---|---|---|
| `projects` | מערך פרויקטים | `[]` |
| `history` | מערך רשומות עבודה | `[]` |
| `expenses` | מערך הוצאות | `[]` |
| `notification_enabled` | תזכורת יומית פעילה | `true` |
| `notification_time` | `"HH:mm"` | `20:00` |
| `smart_workflow_enabled` | מצב עבודה חכם | `false` |
| `last_positions` | `{projectId: {page, line}}` – מיקום אחרון במצב חכם | `{}` |
| `timer_state` | מצב טיימר לשחזור אחרי סגירת אפליקציה | – |
| `day_rollover_hour` | שעת מעבר יום (0–23) | `0` |
| `friday_motzei_half_day` | שישי/מוצ"ש כחצי יום עבודה | `false` |
| `use_gregorian_dates` | תאריכים לועזיים במקום עבריים | `false` |

---

## 6. סנכרון Google Drive (`sync_service.dart`)

**Singleton** (`SyncService.instance`). Scopes: `email` + `drive.file` (גישה רק לקבצים שהאפליקציה יצרה).

**קובץ הגיבוי:** `sofer_vmone_backup.json` – מכיל `projects`, `history`, `expenses`, `lastSync`.

**אלגוריתם `syncData()`:**
1. טעינת נתונים מקומיים + הורדת הקובץ מהדרייב.
2. **מיזוג (`_mergeLists`)** לפי `id`: הרשומה עם `lastUpdated` מאוחר יותר מנצחת – בכל שלושת סוגי הנתונים.
3. **ניקוי (`_purgeOldDeleted`)**: פריטים עם `isDeleted == true` שעברו 30 יום נמחקים לצמיתות – כולל הוצאות.
4. שמירה מקומית + העלאה חזרה לדרייב (update אם קיים, create אם לא).

**הגנה מריצה כפולה:** `syncData()` נקרא מ-13 מקומות ב-UI. דגל `_isSyncing` מונע שני מחזורים חופפים; בקשה שמגיעה באמצע מסומנת ב-`_resyncQueued` ורצה שוב בסיום, כדי שהשינויים שלה לא ילכו לאיבוד.

**דיווח תוצאה:** הפונקציה מחזירה `SyncStatus` (`success` / `notSignedIn` / `failed`), ושומרת `lastSyncTime` ו-`lastSyncError`. מסך ההגדרות מציג את התוצאה האמיתית ואת שעת הסנכרון האחרון.

**אימות לפי פלטפורמה:**
- **אנדרואיד:** `google_sign_in` + `signInSilently()` בהפעלה. החתימה מוגדרת ב-Google Cloud Console – אין מפתחות בקוד.
- **Windows:** OAuth ידני – פתיחת דפדפן, שרת HTTP מקומי על פורט אקראי ל-callback, ואז `obtainAccessCredentialsViaCodeExchange` + `autoRefreshingClient`.
  מקורות המפתחות (לפי סדר עדיפות): `--dart-define=GOOGLE_OAUTH_CLIENT_ID/SECRET` בבנייה → `oauth_credentials.json` בתיקיית העבודה → `oauth_credentials.json` ליד ה-exe.
  הקובץ ב-`.gitignore` ואינו tracked בגיט. יש `oauth_credentials.json.example` כתבנית.

**`_GoogleAuthClient`:** עוטף בקשות ומוסיף כותרות אימות; מטפל ידנית ב-redirects של `GET` ל-googleapis (בגלל אובדן כותרות בהפניה).

---

## 6א. גיבוי לקובץ (`backup_service.dart`)

חלופה מקומית לסנכרון הענן, ובסיס להעברת נתונים בין מכשירים.

**מבנה קובץ הגיבוי** (JSON יחיד, pretty-printed):
```jsonc
{
  "app": "sofer_vmone",
  "formatVersion": 1,          // בקרת תאימות לייבוא עתידי
  "appVersion": "0.4.0",
  "exportedAt": "2026-07-29T14:35:00.000",
  "exportedFrom": "windows",   // android / windows / macos
  "counts": { "projects": 3, "history": 812, "expenses": 44 },
  "projects":  [ ... ],
  "history":   [ ... ],
  "expenses":  [ ... ],
  "lastPositions": { "<projectId>": { "page": 12, "line": 7 } },
  "settings": { "day_rollover_hour": 2, "use_gregorian_dates": true, ... }
}
```

`StorageService.exportAll()` אוסף את הכול ממקום אחד. `timer_state` **מוחרג** במכוון – הוא מצב רגעי ופר-מכשיר. פענוח שדות פגומים לא זורק חריגה אלא מחזיר רשימה ריקה, כדי שגיבוי יצליח גם אם ערך אחד באחסון השתבש.

**שני מסלולי ייצוא**, לבחירת המשתמש:
| מסלול | דסקטופ (Windows/מק) | אנדרואיד |
|---|---|---|
| **שמור במכשיר** | דיאלוג שמירה מקורי; הקובץ נכתב ידנית לנתיב שנבחר | בורר המסמכים של המערכת; ה-bytes מועברים ל-`saveFile` |
| **שיתוף** | תפריט השיתוף של המערכת | share sheet – וואטסאפ, מייל, כל אפליקציה |

שם הקובץ נושא חותמת תאריך ושעה, כך שגיבויים עוקבים לא דורסים זה את זה.

✅ **החסמים לייבוא נסגרו** (`f9dd0e7`): המזהים כוללים רכיב אקראי (`IdGenerator`), מחיקה סופית מנצחת במיזוג, ורשומות של פרויקט שנמחק סופית נמחקות איתו. הליבה שנותרה למימוש הייבוא היא חילוץ `_mergeLists` מ-`sync_service` ל-`merge_service` נייטרלי.

---

## 6ב. הפשטת פלטפורמה (`platform_support.dart`)

בקוד יש 22 בדיקות `Platform.is*` (12 `isAndroid`, 10 `isWindows`, 2 `isMacOS`). כמעט כל `isWindows` מתכוון בפועל ל"דסקטופ" – וזו הסיבה שמק נופל בין הכיסאות. `PlatformSupport` מרכז את השאלות כ**יכולות** ולא כשמות מערכת: `isDesktop`, `isMobile`, `hasNativeSaveDialog`, `canBindLocalServer`, `hasForegroundTimerService`, `hasLocalNotifications`, `hasWindowManager`, `name`.

קוד חדש צריך לשאול דרך המחלקה הזו. הקוד הישן יועבר בהדרגה.

---

## 7. לוגיקה עסקית לפי סוג פרויקט

זהו החלק העדין ביותר בקוד – כל סוג פרויקט נספר אחרת.

> **מאז 29.07.2026 כל החישובים האלה חיים ב-`lib/logic/` ולא בתוך המסכים.** `ProductionCalculator` להספק, `ProfitCalculator` לכסף, `DateLogic` לתאריכים. המסכים קוראים להם ואינם מחזיקים עותק משלהם. 43 טסטים מכסים אותם.

### ספר תורה (`sefer`)
- יחידת מדידה: **שורות**. `amount` ברשומה = מספר העמוד.
- **הספק** = `endLine - startLine + 1` שורות; המרה לעמודים: `שורות / linesPerPage`.
- **רווח** = `(שורות / linesPerPage) × (price - expenses)`.
- **יעד יומי** = `targetDaily` אם `dailyGoalInLines`, אחרת `targetDaily × linesPerPage`.
- **בדיקת חפיפה** (`_checkOverlap`): מונעת הזנה כפולה של שורות באותו עמוד – מציגה אזהרה עם אפשרות "שמור בכל זאת".
- **טווח עמודים**: הזנת "מעמוד…עד עמוד…" יוצרת רשומה נפרדת לכל עמוד עם `1..linesPerPage`.

### מזוזה (`mezuza`)
- תקן קבוע: **22 שורות למזוזה**.
- הספק בשורות: `(amount - 1) × 22 + endLine` כאשר יש מזוזה חלקית, אחרת `amount × 22`.
- **רווח** = `(שורות / 22) × (price - expenses)`.

### תפילין (`tefillin`)
- **סט = 8 פרשיות** (4 של ראש + 4 של יד).
- המרה לפרשיות: סט מלא → `amount × 8`; ראש/יד בלבד → `amount × 4`; פרשייה בודדת → `amount`.
- מגבלות שורות: של ראש עד 4 שורות, של יד עד 7 שורות.
- **רווח** = `(פרשיות / 8) × (price - expenses)`.

### כלל חוצה-סוגים: `backlogOnly`
רשומה שנוצרה בהזנה ידנית **ללא תאריך** מסומנת `backlogOnly = true`. משמעות: היא נספרת רק בהספק הכולל של הפרויקט (כדי לתעד עבודה שנעשתה לפני התקנת האפליקציה), אך מוחרגת מ:
רווח · ממוצע דקות ליחידה · יעד יומי · הסיכום היומי · הסיכום החודשי.
בקוד: כל מסכי הסיכום מפרידים `sessions` (הצגה) מ-`sessionsForStats` (`.where((s) => !s.backlogOnly)`).

---

## 8. המסכים והתכונות

### מסך הבית (`home_screen.dart`)
שני מצבי עבודה, נשלטים בהגדרה "זרימת עבודה חכמה":

**מצב רגיל:** בוחרים פרויקט → מפעילים טיימר → "עצור" פותח דיאלוג הזנה (מה נכתב).
**מצב חכם:** האפליקציה זוכרת את המיקום (עמוד+שורה) בכל פרויקט (`last_positions`); כפתור "סיימתי שורה" מקדם את המיקום אוטומטית וגם מודד זמן שורה (Lap); בסיום הסשן הרשומה נבנית לבד מהמיקום ההתחלתי והסופי.

תכונות נוספות במסך:
- **הזנה ידנית** – תאריך (בורר עברי או לועזי), שעות התחלה/סיום (עם תמיכה בגלישה ליום הבא), או ללא תאריך כלל → `backlogOnly`.
- **הפסקת קפה** – במצב חכם נפתח דיאלוג המאפשר לקבוע התראה אחרי X דקות; זמן ההפסקה נצבר ב-`_sessionBreakDuration` ואינו נכנס לממוצע הכתיבה.
- **עריכת מיקום** – קפיצה ידנית לעמוד/שורה (עמוד באותיות עבריות).
- **חלון צף (Windows)** – כפתור ב-AppBar מקטין לתצוגת טיימר מינימלית.
- **כפתור תרומה** – פותח https://buymeacoffee.com/soferstam.

### הטיימר – שמירת מצב והרצה ברקע
- הזמן מחושב מ-**חותמות זמן אמיתיות** ולא מ-`Stopwatch` בלבד: `_effectiveElapsed() = _accumulatedElapsedSeconds + (now - _timerStartTime)`. כך הזמן נשמר נכון גם כשהאפליקציה נהרגת.
- `_persistTimerState()` שומר ל-`timer_state` בעת השהיה או מעבר לרקע; `_restoreTimerState()` משחזר בטעינה.
- **אנדרואיד:** ביציאה לרקע עם טיימר פעיל מופעל `flutter_foreground_task` (serviceId 256, ערוץ `sofer_vmone_timer`), שמעדכן התראה עם הזמן כל שנייה (`TimerTaskHandler`). בחזרה לחזית השירות נעצר.

### מסך סיכומים (`summary_screen.dart`)
- **סיכום יומי** לפי תאריך נבחר, מקובץ לפי פרויקט: הספק, זמן עבודה, רווח, ממוצע, עמידה ביעד.
- **סיכום חודשי** (חודש עברי): טבלה מרכזת, גרף עמודות של התקדמות יומית, חישוב ימי עבודה בפועל, ושורות **הכנסות כתיבה / הוצאות / נטו**.
- **עריכת היסטוריה**: עריכת רשומה (שעות, שורות, כמות), מחיקה בודדת ומחיקה מרובה עם תיבות סימון.

### מסך סיכום פרויקט (`project_summary_screen.dart`)
התקדמות כוללת, ממוצע דקות לשורה/פרשייה, צפי סיום, "שלח עדכון ללקוח" (פותח מייל), **גריד ויזואלי**: לספר תורה – רשת עמודים עם מילוי לפי אחוז השורות שנכתבו; לתפילין – תיבות פרשיות ראש/יד.

### מסך פרויקטים · הוצאות · הגדרות · סל מחזור
- **פרויקטים:** יצירה/עריכה/מחיקה לוגית (עם רענון מיידי של המסך הראשי), שדות דינמיים לפי סוג, אודות, איפוס כל הנתונים.
- **הוצאות:** כרטיס סה"כ + רשימה; קטגוריות מוצעות (קלף, דיו, קולמוס, הגהות, משלוחים, חדר סופרים ועוד) + טקסט חופשי.
- **הגדרות:** התראות ושעתן · תאריכים לועזיים · זרימת עבודה חכמה · שישי/מוצ"ש כחצי יום · שעת מעבר יום · התחברות Google וסנכרון ידני · בדיקת עדכונים (Windows) · אודות.
- **סל מחזור:** שחזור פרויקטים שנמחקו לוגית או מחיקה סופית.

---

## 9. תאריכים עבריים וימי עבודה

**`hebrew_utils.dart`:**
- `formatDisplayDate(date, useGregorian)` / `formatDisplayDateMonth` – מתג יחיד לכל האפליקציה בין תאריך עברי (`kosher_dart`) ללועזי `dd.mm.yyyy`.
- `formatHebrewNumber(n)` – גימטריה לתצוגת עמודים (כולל טיפול נכון ב-טו/טז ובאלפים).
- `parseHebrewPageToNumber(s)` – פענוח קלט: מקבל גם ספרות וגם אותיות (כולל סופיות ך/ם/ן/ף/ץ).

**`work_days_calculator.dart`:**
- `workDayValue(date, fridayMotzeiHalfDay)` – 0 בשבת/חג (`isAssurBemelacha`), 0.5 לשישי ולשבת כשההגדרה דלוקה, אחרת 1.
- `countWorkDays`, `estimatedCompletionDate`, `workDaysNeeded` – בסיס לשורות "מתי אני אמור לסיים" ו"כמה שורות ליום נשארו".

**שעת מעבר יום:** `_effectiveDate()` מחסיר יום כאשר `now.hour < dayRolloverHour` – כדי שסופר שמסיים ב-01:00 ישויך ליום הקודם.

---

## 10. התראות (`notification_service.dart`)

Singleton מעל `flutter_local_notifications`. אזור זמן קבוע: `Asia/Jerusalem`. **אנדרואיד בלבד** (כל המתודות יוצאות מוקדם בפלטפורמות אחרות).

| ID | ערוץ | תפקיד |
|---|---|---|
| 0 | `daily_reminder_channel` | תזכורת יומית חוזרת בשעה שנבחרה; מבוטלת אוטומטית כשהיעד היומי הושג (`_checkDailyGoalMet`) |
| 1 | `break_reminder_channel` | התראה חד-פעמית בתום הפסקה |
| — | `sofer_vmone_timer` | התראת ה-Foreground Service של הטיימר |

---

## 11. פלטפורמות, בנייה ותשתית

### נטפרי / SSL
`MyHttpOverrides` ב-`main.dart` מטמיע את תעודת ה-CA של נטפרי (`netfree_cert.dart`) ומאשר תעודות עבור google/googleapis/gstatic/netfree או כל תעודה שהמנפיק שלה מכיל "NetFree". באנדרואיד יש בנוסף `network_security_config.xml` המאשר תעודות משתמש.
⚠️ עקיפת ולידציית תעודות מצומצמת לדומיינים הללו, אך היא עדיין הקלה מכוונת באבטחה – נדרשת לתמיכה בסביבות מסוננות.

### אנדרואיד
- `compileOptions`: Java 17 + `coreLibraryDesugaring` (`desugar_jdk_libs:2.0.4`) – נדרש ל-`flutter_local_notifications`.
- הרשאות: `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `SCHEDULE_EXACT_ALARM`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`.
- שירות `com.pravera.flutter_foreground_task.service.ForegroundService` עם `foregroundServiceType="dataSync"`.
- ⚠️ ה-release חתום כרגע ב-**debug keys** (ראו חוב טכני).

בנייה: `flutter build apk --release`

### Windows
- `window_manager` – חלון 1280×720 ממורכז, ותמיכה בחלון צף.
- `auto_updater` – בדיקת עדכונים **רק בלחיצה ידנית** בהגדרות (אין בדיקה בעלייה).
- `windows/CMakeLists.txt` מוסיף התקנה של `vcruntime140.dll`, `vcruntime140_1.dll`, `msvcp140.dll` ליד ה-exe – כדי שלא יידרש להתקין VC++ Redistributable.

בנייה: `flutter build windows --release` (בתוספת `--dart-define` למפתחות OAuth, אם לא משתמשים בקובץ)

### תלויות עיקריות
`kosher_dart` (path מקומי, 2.0.18) · `shared_preferences` · `path_provider` · `url_launcher` · `google_sign_in` · `googleapis` + `googleapis_auth` · `http` · `flutter_local_notifications` · `timezone` · `flutter_foreground_task` · `window_manager` · `auto_updater` · `flutter_localizations` · **`file_picker` 8.3.7** (שמירה מקומית בכל הפלטפורמות) · **`share_plus` 10.1.4** (תפריט שיתוף מערכתי).

### מצב הבנייה בסביבת הפיתוח
- **Windows:** ✅ `flutter build windows --release`
- **אנדרואיד:** ✅ `flutter build apk --release` (55.6MB)
- **מק:** לא נבנה – נדרש מארח macOS. ראו סעיף בנייה בענן בפרק 13.

### ⚠️ הגדרות סביבה נדרשות לבניית אנדרואיד (מכונה זו)

ארבע מכשלות נפרדות התגלו בהעלאת בניית האנדרואיד. אם היא נשברת שוב – זה הסדר לבדוק בו:

**1. Flutter הצביע ל-SDK הלא נכון.** הוא השתמש ב-PlatformTools מינימלי של WinGet במקום ב-SDK המלא של Android Studio:
```
flutter config --android-sdk "C:\Users\<user>\AppData\Local\Android\Sdk"
```

**2. NDK לא היה מותקן.** נדרשות **שתי** גרסאות – Flutter מבקש 27, ה-AGP דורש בפועל 28.2:
```
sdkmanager --install "ndk;27.0.12077973" "ndk;28.2.13676358"
```

**3. תעודות נטפרי חסרות ב-truststore של Java.** התעודות מותקנות ב-Windows, ולכן הדפדפן ו-PowerShell עובדים – אבל **Java מחזיק truststore נפרד** ולא רואה אותן, וכל הורדת תלות ב-Gradle נכשלת ב-`PKIX path building failed`.
הפתרון שיושם, ללא נגיעה בקובצי מערכת: עותק של ה-`cacerts` של ה-JDK בתוספת תעודות נטפרי, ב-`C:\gradle-trust\netfree-cacerts`, ומצביעים אליו מ-`~/.gradle/gradle.properties`:
```properties
systemProp.javax.net.ssl.trustStore=C:/gradle-trust/netfree-cacerts
systemProp.javax.net.ssl.trustStorePassword=changeit
```
⚠️ הנתיב חייב להיות **באנגלית בלבד** – ראו סעיף 4.
(`trustStoreType=Windows-ROOT` **אינו** עובד – ה-JBR של Android Studio לא כולל את הספק הזה.)

**4. תווים עבריים בנתיב שוברים את מהדר Kotlin.** ה-pub cache ישב תחת `C:\Users\שאול\...`, ומהדר Kotlin קיבל את הנתיב מקודד כ-`C:\Users\u05E9u05D0u05D5u05DC\...` ודיווח על **כל** קובצי המקור של הפלאגינים כלא-קיימים. הפתרון – pub cache בנתיב אנגלי:
```
setx PUB_CACHE "C:\pub-cache"
```
בנוסף, ה-Kotlin daemon נכשל על המכונה (`Daemon compilation failed: null`); `android/gradle.properties` מגדיר לכן `kotlin.compiler.execution.strategy=in-process`.

---

## 12. מצב נוכחי – שינויים שטרם נכנסו לגיט

הענף `main` נמצא ב-`b5270e4` (v0.3.0), ומעליו יש שינויים לא מקומיטים (≈750 שורות ב-17 קבצים). עיקרי הפיצ'רים החדשים:

1. **טיימר עמיד לסגירת אפליקציה** – חישוב לפי חותמות זמן, `timer_state` ב-SharedPreferences, ו-Foreground Service באנדרואיד שמציג את הזמן בהתראה.
2. **`backlogOnly`** – רשומות "השלמת רקע" (הזנה ידנית ללא תאריך) שנספרות בהספק בלבד ומוחרגות מכל החישובים הכספיים והממוצעים.
3. **`dailyGoalInLines`** – בספר תורה אפשר להגדיר יעד יומי בשורות במקום בעמודים (מתג בדיאלוג הפרויקט).
4. **הזנת טווח עמודים** – שדה "עד עמוד" יוצר רשומה מלאה לכל עמוד בטווח, עם בדיקת חפיפה על כל הטווח.
5. **הפסקה עם התראה** – דיאלוג הפסקת קפה עם קציבת דקות; זמן ההפסקה מוחרג מהממוצע.
6. **תיקוני חישוב בסיכומים** – הפרדה עקבית בין נתוני תצוגה לנתוני סטטיסטיקה, והגנה מפני חלוקה באפס (`totalTime.inSeconds > 0`).
7. **VC++ Runtime מצורף** ל-build של Windows.
8. **`oauth_credentials.json` נוסף ל-.gitignore** (הקובץ אינו tracked – לא הודלף לגיט).

קבצים לא מנוהלים בתיקייה: `sofer_vmone_0.3.0_windows.zip` (14MB), `סופר ומונה 0.3.0.apk` (57MB) – מקומם ב-GitHub Releases. נוספו ל-`.gitignore` (`*.apk`, `*.aab`, `sofer_vmone_*_windows.zip`) כדי שלא ייכנסו למאגר בטעות.

### תיקוני באגים (26.07.2026)
| הבאג | התיקון |
|---|---|
| מחיקת הוצאה חזרה מהענן בסנכרון הבא | `isDeleted` ל-`Expense` + מחיקה לוגית + `_purgeOldDeleted` |
| עריכת הוצאה לא הסתנכרנה בין מכשירים | `lastUpdated` ל-`Expense`; המיזוג עבר להשתמש בו במקום ב-`date` |
| שני מחזורי סנכרון יכלו לרוץ במקביל ולדרוס זה את זה | `_isSyncing` + `_resyncQueued` |
| מסך ההגדרות דיווח "הסנכרון הושלם בהצלחה" גם בכישלון | `SyncStatus` מוחזר מ-`syncData()`; ה-UI מדווח נכון + שעת סנכרון אחרון |
| תיבת הקלף באנימציית "כותב..." הוצגה ללא רקע | `Color(0xFFF5E6)` (6 ספרות → אלפא 00, שקוף) → `Color(0xFFFFF5E6)`, בשני מקומות |
| `TextEditingController` בדיאלוגים ללא `dispose` | נוסף `dispose` ב-`home_screen`, `summary_screen`, `expenses_screen` |
| `flutter test` נכשל – הטסט לא התקמפל | הוחלף בטסטים ל-`hebrew_utils` ול-`Expense` |
| deprecations ו-lints | `withOpacity`→`withValues`, `value`→`initialValue`, `const MyApp`, ועוד |

---

## 13. חוב טכני ונקודות פתוחות

| # | נושא | הערה |
|---|---|---|
| 1 | `applicationId = com.example.stamsofer` | עדיין ברירת המחדל של Flutter; שינוי אחרי פרסום ידרוש התקנה מחדש למשתמשים |
| 2 | חתימת release ב-debug keys | חובה להגדיר keystore אמיתי לפני העלאה לחנות |
| 3 | `home_screen.dart` ≈2,300 שורות | מועמד לפיצול (טיימר / דיאלוג הזנה / מצב חכם כרכיבים נפרדים) |
| 4 | ~~שגיאות סנכרון נבלעות~~ | ✅ תוקן – `syncData()` מחזיר `SyncStatus` וה-UI מדווח |
| 5 | `history_screen.dart` ריק | שריד – ניתן למחוק |
| 6 | כיסוי טסטים חלקי | ✅ הטסט השבור הוחלף בטסטים ל-`hebrew_utils` ול-`Expense`. עדיין אין כיסוי לחישובי ההספק/רווח – מועמד ראשון להמשך, רצוי יחד עם חילוץ החישובים מהמסכים לקובץ נפרד |
| 7 | `type.index` בסריאליזציה | שינוי סדר ה-enum ישבור נתונים קיימים |
| 8 | קישורים ב-README | "[קישור להורדות]" עדיין placeholder, וכן `YOUR_USERNAME` בהוראות ה-clone |
| 9 | תמיכת iOS/macOS/Linux/web | תיקיות קיימות אך לא נבדקו; `NotificationService` ו-`SyncService` מותנים ב-Android/Windows בלבד |
| 10 | **מק – חסמי רשת** | `macos/Runner/Release.entitlements` מכיל רק `app-sandbox`. חסר `com.apple.security.network.client` – ובלעדיו **כל גישה לרשת חסומה ב-release**. `network.server` (נדרש ל-OAuth loopback ולהעברת LAN) קיים רק ב-`DebugProfile` |
| 11 | מק – מזהה חבילה | `PRODUCT_BUNDLE_IDENTIFIER = com.example.stamsofer`, חוסם חתימה והפצה |
| 12 | מזהי רשומות מבוססי-זמן בלבד | ראו אזהרה בפרק 6א – תנאי מקדים לייבוא/מיזוג בין מכשירים |

### בנייה למק בלי מחשב מק
**GitHub Actions** מריץ `macos-latest` (חינם למאגר ציבורי): workflow שמריץ `flutter build macos --release` ומעלה את התוצאה כ-artifact. מגבלות: (א) בנייה בלבד – בדיקה ויזואלית עדיין דורשת מק אמיתי; (ב) חתימה ונוטריזציה דורשות חשבון Apple Developer, ובלעדיהן המשתמש נדרש לעקוף Gatekeeper ידנית.

---

## 14. יומן החלטות (Decisions Log)

| החלטה | נימוק |
|---|---|
| **SharedPreferences ולא SQLite** | היקף הנתונים קטן (מאות רשומות), הכול נטען לזיכרון, וסריאליזציית JSON מאפשרת גיבוי/סנכרון טריוויאלי כקובץ אחד |
| **State מקומי ב-`_SoferHomeState`, בלי Provider/Bloc** | אפליקציה חד-משתמשית עם מסך ראשי דומיננטי; ספריית state הייתה מוסיפה מורכבות בלי תמורה |
| **מחיקה לוגית (`isDeleted`) + ניקוי אחרי 30 יום** | מאפשר סל מחזור ומונע "תחיית" רשומות שנמחקו במכשיר אחד וחוזרות מהענן במיזוג |
| **`lastUpdated` כמכריע במיזוג** | Last-Write-Wins – הפתרון הפשוט שמספיק כשמשתמש יחיד מסנכרן בין שני מכשירים |
| **`drive.file` scope ולא `drive`** | האפליקציה ניגשת רק לקובץ הגיבוי שהיא יצרה – מינימום הרשאות |
| **חותמות זמן ולא `Stopwatch` בלבד** | `Stopwatch` נעצר כשהאפליקציה נהרגת; חישוב מ-`DateTime` שומר על דיוק גם אחרי סגירה או ריסטארט |
| **Foreground Service באנדרואיד** | ללא שירות חזית, אנדרואיד עוצר timers ברקע והטיימר "קופא" |
| **`backlogOnly` כשדה במקום סוג רשומה נפרד** | שומר על מודל אחד ל-WorkSession; הפילטר `!backlogOnly` מספיק לכל מקומות החישוב |
| **`lastUpdated` נפרד מ-`date` ב-`Expense`** | תאריך ההוצאה הוא נתון עסקי שהמשתמש קובע; חותמת המיזוג חייבת להשתנות בכל עריכה. שימוש בשדה אחד לשתי המטרות מנע מעריכות להסתנכרן |
| **מחיקה לוגית גם להוצאות** | ב-Last-Write-Wins, היעדר רשומה אינו "מידע" – רק נוכחות של `isDeleted` מבדילה בין "נמחק" ל"עדיין לא הגיע לכאן" |
| **`_isSyncing` + coalescing במקום debounce** | debounce מעכב כל שמירה; הדגל מונע את מרוץ הכתיבה בלי להשהות את המשתמש, וה-`_resyncQueued` מבטיח שאף שינוי לא יאבד |
| **קובץ גיבוי יחיד ולא כמה קבצים** | העברה בין מכשירים צריכה להיות פעולה אחת של המשתמש. קובץ אחד גם מבטיח שההגדרות והנתונים תמיד עקביים ביניהם |
| **`formatVersion` בקובץ הגיבוי** | מאפשר לייבוא עתידי לזהות ולהמיר גיבויים ישנים במקום להיכשל או, גרוע מכך, לפרש שדות לא נכון |
| **הגדרות נכללות בגיבוי, `timer_state` לא** | ההגדרות הן חלק מהסביבה שהמשתמש בנה לעצמו ושווה לשחזר; מצב הטיימר רגעי ופר-מכשיר, ושחזורו במכשיר אחר היה יוצר סשן פנטום |
| **`PlatformSupport` לפי יכולת ולא לפי שם מערכת** | `Platform.isWindows` פזור ב-10 מקומות התכוון בפועל ל"דסקטופ"; שאלה לפי יכולת הופכת הוספת מק לשינוי במקום אחד |
| **תעודת נטפרי מוטמעת בקוד** | קהל היעד (סופרי סת"ם) משתמש בהיקף רחב בסינון נטפרי; הטמעה מונעת כשל התחברות ל-Google Drive אצל רוב המשתמשים |
| **`kosher_dart` כתלות path מקומית** | שליטה בגרסה ואפשרות תיקונים מקומיים בלי להמתין לגרסה ב-pub.dev |
| **`price` ו-`expenses` הם *ליחידה*** | רווח מחושב תמיד כ-`יחידות × (price - expenses)`; הוצאות כלליות שאינן תלויות יחידה מנוהלות בנפרד במסך ההוצאות |
| **עמודים באותיות עבריות בכל הממשק** | תואם את אופן העבודה המקובל אצל סופרים ("עמוד יא"), כולל בקלט – עם קבלה גם של ספרות |

---

## 15. מסמכים נוספים בפרויקט

- [SUGGESTIONS.md](SUGGESTIONS.md) – **התנגשויות שאותרו בסקירת קוד + הצעות שיפור**, ממוינות לפי עדיפות.
- [DESIGN_PLAN.md](DESIGN_PLAN.md) – **תכנון ארכיטקטורה וממשק**: מסלול שיפור בארבעה גלים, פריסות דסקטופ/מובייל, מערכת אייקונים.
- [README.md](README.md) – תיאור למשתמש, הוראות התקנה והגדרת OAuth.
- [CHANGELOG.md](CHANGELOG.md) – יומן שינויים לפי גרסאות.
- [docs/GIT_UPLOAD.md](docs/GIT_UPLOAD.md) – הוראות העלאה לגיטהאב.
- [docs/index.html](docs/index.html) – אתר הפרויקט (GitHub Pages).
- `docs/privacy_policy.html` / `privacy_policy_en.html` – מדיניות פרטיות (עברית/אנגלית).
