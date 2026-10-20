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

הערך מקובע במפורש כ־24 ב־`android/app/build.gradle.kts`, כדי ששדרוג Flutter
לא יוציא מכשירים מהתמיכה בלי החלטה מפורשת.

---

## חוזה קובצי השחרור עבור המעדכן

יעד ההפצה שבהכנה הוא **0.7.0+8** (החלטה 66). קובצי ההפצה יהיו
`sofer-vmone-0.7.0-android.apk` ו־`sofer-vmone-0.7.0-windows.zip`.
החתימה וזהות Android ממשיכות את מסלול גרסת ההיערכות; שינוי המספר
אינו שלב החלפת המפתח. חבילות סקירה ישנות אינן חבילות 0.7.0.

המעדכן המובנה אינו מנחש איזה קובץ להתקין. בשחרור `X.Y.Z` חייבים להיות בדיוק
הנכסים הבאים ב־GitHub Releases:

```text
sofer-vmone-X.Y.Z-android.apk
sofer-vmone-X.Y.Z-windows.zip
```

GitHub מחשב לכל נכס שדה `digest` מסוג SHA-256. המעדכן דורש את השדה, מוריד את
מספר הבתים שפורסם ומשווה את הגיבוב לפני התקנה. שינוי שם הקובץ, העלאת קובץ ריק
או פרסום שחרור לפני ששני הנכסים מוכנים גורמים לעדכון להיעצר בהודעה ברורה.

חבילת Windows חייבת להכיל באותה תיקיית שורש את קובץ ההפעלה, את
`flutter_windows.dll` ואת `data/app.so` ו־`data/icudtl.dat`. אפשר לעטוף את
השורש בתיקייה אחת בתוך ה־ZIP; המעדכן מאתר אותה, אבל אינו מקבל שני קובצי הפעלה
באותו שם.

לפני פרסום יש לוודא גם שמספר הבנייה ב־`pubspec.yaml` גבוה מה־`versionCode`
האחרון ושחתימת ה־APK ממשיכה את מסלול החתימה המתועד ב־`docs/SIGNING.md`.

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

### המסלול הנוכחי — אימות אוטומטי (0.7.0)

`printing` מקובע לעותק מקומי של 5.14.3 ב־`packages/printing`, עם שינוי
בקובצי הבנייה של Windows בלבד. CMake דורש SHA-256 קבוע לארכיון PDFium
5200 x64, לפני חילוץ, ובודק גם את ה־DLL המחולץ בכל הגדרה של הבנייה.
ארכיטקטורה אחרת מחייבת בחירה מפורשת של בינארי וגיבובים מאומתים.
אין לערוך את Pub Cache או את קובצי התוספים המחוללים.

בבנייה מקוונת ההורדה נעשית אצל המפתח. לבנייה מעותק מקומי שכבר הורד,
אפשר להגדיר את הנתיב ב־CMakeCache; גם קובץ זה חייב להתאים לאותו גיבוב:

```powershell
& $cmakeExe -S windows -B build/windows/x64 `
  -DSTAMSOFER_PDFIUM_ARCHIVE=C:/gradle-trust/pdfium-win-x64-verified.tgz
flutter build windows --release --no-pub
```

`$cmakeExe` הוא הנתיב ל־cmake.exe של Visual Studio. בלי הפרמטר משתמשים
בכתובת המקובעת של GitHub עם אימות התעודה הרגיל. אין צורך לכבות אימות TLS.
הגדרת המטמון מקומית למחשב; אין לשמור נתיב אישי בקוד.

המשתמש מקבל `pdfium.dll` לצד קובץ ההפעלה ואת
`data/licenses/pdfium.txt`. אין הורדת PDFium בזמן הרצת האפליקציה.
יש לארוז את תיקיית ההתקנה המלאה, ולא את ה־EXE בלבד.
אם הוגדר בעבר `CMAKE_INSTALL_PREFIX`, הבנייה יכולה להתקין שם גם כשהפלט של
Flutter מצביע על `runner/Release`. יש לבדוק את `install_manifest.txt` ואת
מספר הגרסה של ה־EXE בחבילה; תיקייה ששמה 0.6.0 אינה הוכחה לגרסת התוכן.

### העקיפה ההיסטורית — הוחלפה במסלול המאומת לעיל

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

לפני התיקון ב־0.7.0 האימות נעשה ידנית:

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

ב־0.7.0 הגיבוב לעיל מקובע בבנייה, יחד עם גיבוב ה־DLL. התיאור הבא מתעד
את הכשל במנגנון ההורדה הישן; קובץ מקומי מאומת נתמך כעת במפורש.

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

## עדכון סביבת Android — 14.10.2026

השגיאה `Unable to establish loopback connection` הופיעה גם בהרצת
PowerShell, עם `Invalid argument: connect` ב־`UnixDomainSockets`.
הבנייה הצליחה עם ההגדרות הבאות עבור תהליך הבנייה בלבד:

```powershell
New-Item -ItemType Directory -Path C:\jtmp -Force | Out-Null
$env:TEMP = "C:\jtmp"
$env:TMP = "C:\jtmp"
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=C:/jtmp -Djava.net.preferIPv4Stack=true"
& C:\flutter\bin\flutter.bat build apk --debug --no-pub
```

נבדקה בניית Debug לצורך סקירה. אין צורך לשנות את משתני הסביבה
הקבועים במערכת. ההסבר הקודם על Git Bash מתאר את התקלה שנבדקה אז;
הופעת אותה שגיאה אינה מוכיחה שההרצה הנוכחית נעשתה ב־Git Bash.

## הרצת הבדיקות — פקודות

```bash
flutter test
flutter analyze lib test
```

‏**`lib test` ולא בלי ארגומנטים.** ניתוח משורש המאגר מושך את
`packages/kosher_dart/example`, שהיא אפליקציית Flutter בתוך חבילת Dart ולכן
ה-imports שלה אינם נפתרים כאן. זה מיוצג ב-`analysis_options.yaml` דרך
`exclude: packages/**`, אבל הפקודה עם היעדים המפורשים עדיין המהירה והנכונה.
