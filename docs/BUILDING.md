# בנייה — המכשלות שחוזרות

מסמך של מה שנשבר בפועל ולמה. כל אחד מהסעיפים כאן עלה כמה שעות למישהו לפחות
פעם אחת, ורובם נראים בהתחלה כמו בעיה אחרת לגמרי.

לפני הבנייה יש להריץ `flutter doctor` ולוודא ש־Flutter, סביבת Android ו־Visual
Studio עם רכיב Desktop development with C++ מזוהים. הוראות החתימה לאנדרואיד
נמצאות ב־`docs/SIGNING.md`.

---

## טווח הגרסאות הנתמך

| | |
|---|---|
| **אנדרואיד** | **7.0 ומעלה** (API 24) עד אנדרואיד 16 (API 36) |
| ווינדוס | 10 ומעלה |

‏**אנדרואיד 4, 5 ו-6 אינם נתמכים ואינם יכולים להיות נתמכים.** זו אינה בחירה של
הפרויקט: הרצפה של Flutter היא API 21, וגרסת ה-SDK שבשימוש קובעת 24. מכשיר ישן
מכך פשוט לא יתקין את הקובץ.

הערך מגיע מ-`flutter.minSdkVersion` ולא נכתב בפרויקט, כך שהוא עולה מעצמו עם
כל שדרוג של Flutter. **אם זה חשוב שיישאר יציב — צריך לקבע אותו במפורש**
ב-`android/app/build.gradle.kts`.

---

## ווינדוס: הבנייה נכשלת על הורדת Pdfium

### מה רואים

```
CMake Error at .../printing/windows/DownloadProject.cmake:179 (message):
  Build step for pdfium failed: 1
Unable to generate build files
```

### מה זה באמת

**זו אינה תקלת רשת ואינה תעודה חסרה**, אף ששתי ההשערות האלה נראות סבירות
ושתיהן מבזבזות שעה. השגיאה האמיתית מופיעה רק כשמריצים את שלב ההורדה לבדו:

```
schannel: added 142 certificate(s) from
  'C:\ProgramData\NetFree\CA\netfree-ca-bundle-curl.crt'
schannel: the revocation status is unknown
```

‏**CMake כן מכיר את תעודת נטפרי.** הוא נופל על בדיקת *שלילת* התעודה — הפנייה
לשרת ה-CRL חסומה בסינון, ו-schannel מסרב להמשיך בלי תשובה.

### איך לראות את השגיאה בעצמך

הפלט של `flutter build` מסתיר אותה. להריץ את שלב ההורדה ישירות:

```bash
& "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build "E:\stamsofer\build\windows\x64\pdfium-download" --config Debug
```

### העקיפה

```powershell
$env:PUB_CACHE = "C:\pub-cache"
$env:CMAKE_TLS_VERIFY = "0"
flutter build windows --debug
```

‏`CMAKE_TLS_VERIFY=0` מכבה את האימות **עבור ההורדה הזו בלבד**, ורק למשך אותה
הרצה. הוא אינו נשמר בפרויקט בכוונה: הגדרה שמכבה אימות תעודות ויושבת בקובץ היא
הגדרה שאיש כבר לא זוכר שהיא שם.

### ולמה זה לא מספיק

**התוסף מוריד בינארי מגיטהאב בזמן בנייה בלי hash מקובע.** כלומר הבנייה תלויה
ברשת, ואין דבר שמוודא שמה שהתקבל הוא מה שהיה אמור להתקבל. עם `TLS_VERIFY=0`
גם אין אימות של הצד השני.

**האימות היחיד שנעשה עד היום נעשה בידיים:**

```powershell
# הורדה בערוץ שכן מאמת
Invoke-WebRequest -Uri "https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/5200/pdfium-win-x64.tgz" -OutFile "C:\gradle-trust\pdfium-win-x64-verified.tgz"
Get-FileHash "C:\gradle-trust\pdfium-win-x64-verified.tgz" -Algorithm SHA256

# ואז השוואה מול מה ש-CMake הוריד
Get-FileHash "build\windows\x64\pdfium-download\pdfium-download-prefix\src\pdfium-win-x64.tgz" -Algorithm SHA256
```

הערך שנמדד ב-4.8.2026 עבור `pdfium-win-x64.tgz` גרסה 5200:

```
8E900C3E5103AE9A3AA7800653E804575C687D132FCFB4DEDA7BB2CE04ACA8D2   (2,629,624 bytes)
```

**התיקון הנכון הוא לקבע את הקובץ או את ה-hash בפרויקט** ולא להסתמך על כך שמישהו
יזכור לבדוק. עד אז — הערך למעלה הוא מה שיש להשוות אליו.

### תקלה נלווית: קובץ באורך אפס

הורדה שנכשלת **משאירה מעטפת ריקה** ב-
`build/windows/x64/pdfium-download/pdfium-download-prefix/src/pdfium-win-x64.tgz`.
הצבת הקובץ הנכון שם ידנית אינה עוזרת — ‏`ExternalProject` מוריד מחדש בכל מקרה
ודורס אותו. הדרך היחידה היא שההורדה עצמה תצליח.

---

## אנדרואיד: הבנייה חייבת לרוץ מ-PowerShell

בנייה מ-Git Bash נופלת מיד:

```
java.io.IOException: Unable to establish loopback connection
```

גם כאן ההודעה מפנה לרשת וגם כאן זו הפניה מוטעית. `Selector.open()` בווינדוס
פותח pipe פנימי מעל Unix-domain socket, ו-`UnixDomainSockets.connect0` מחזיר
`Invalid argument`. **זה ה-JVM ולא Gradle:** תוכנית Java בת ארבע שורות נכשלת
באותה צורה ב-JDK 17 וב-JDK 25 — תמיד מ-Git Bash, אף פעם מ-PowerShell, אותה
מכונה ואותו JDK.

זו כמעט בוודאי גם הסיבה לכישלון ה-Kotlin daemon שתועד בפרק 11, ושנעקף שם ב-
`kotlin.compiler.execution.strategy=in-process` בלי שזוהה מה נעקף.

```powershell
$env:PUB_CACHE = "C:\pub-cache"
flutter build apk --release
```

---

## הרצת הבדיקות

```bash
flutter test
flutter analyze lib test
```

‏**`lib test` ולא בלי ארגומנטים.** ניתוח משורש המאגר מושך את
`packages/kosher_dart/example`, שהיא אפליקציית Flutter בתוך חבילת Dart ולכן
ה-imports שלה אינם נפתרים כאן. זה מיוצג ב-`analysis_options.yaml` דרך
`exclude: packages/**`, אבל הפקודה עם היעדים המפורשים עדיין המהירה והנכונה.
