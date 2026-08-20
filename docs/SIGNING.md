# חתימה וסיבוב מפתח

מסמך תפעולי. אם משהו כאן נראה סותר את הקוד — הקוד צודק, והמסמך צריך תיקון.

---

## המצב היום

שלוש הגרסאות שפורסמו — **0.2.0, 0.3.0, 0.3.1** — חתומות כולן באותו מפתח, והוא **מפתח הדיבאג** של מכונת הפיתוח:

```
~/.android/debug.keystore
alias      androiddebugkey
storepass  android
SHA-256    3E:FA:1D:00:91:82:DA:59:1C:A9:E5:80:FA:D0:A2:09:
           BB:E8:4F:52:CE:81:7D:6C:A9:94:B6:B1:28:44:82:72
```

אומת מול ה-APK-ים שפורסמו בפועל ב-`apksigner verify --print-certs`, לא הונח.

```
applicationId    com.example.stamsofer
versionCode      0.3.0 → 1  ·  0.3.1 → 2
minSdk           24 (אנדרואיד 7.0)
```

## למה זו בעיה

**מפתח הדיבאג אינו סוד.** הוא נוצר אוטומטית אצל כל מפתח בעולם, בפורמט קבוע, עם הסיסמה `android`. כל אחד יכול לחתום APK שאנדרואיד יקבל כ**עדכון לגיטימי** של האפליקציה הזו ויתקין מעל הקיימת — עם כל הנתונים.

## למה אי אפשר פשוט להחליף אותו

אנדרואיד בודק שלושה דברים בהתקנה, ו**כל אחד מהם לבדו** יכול להכשיל עדכון:

| | אם משתנה |
|---|---|
| **שם החבילה** | אפליקציה אחרת. מותקנת לצד, נתונים נפרדים. **אין דרך לעקוף** |
| **תעודת החתימה** | `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. חייבים להסיר — והנתונים נמחקים |
| **versionCode** | `INSTALL_FAILED_VERSION_DOWNGRADE` אם אינו גבוה מהמותקן |

**נתוני אנדרואיד מבודדים לפי שם חבילה, ואין לזה מעקף.** מי שמשנה את `applicationId` מוותר על נתוני המשתמשים הקיימים, נקודה.

## הפתרון: סיבוב מפתח (v3 lineage)

APK Signature Scheme v3 מאפשר **להחליף מפתח בלי לשבור עדכונים**. חותמים עם המפתח החדש, ומצרפים *שרשרת ייחוס* חתומה בישן שמוכיחה שהבעלים אחד.

**שם החבילה נשאר `com.example.stamsofer`.** זה מכוער, אבל מחוץ ל-Google Play הוא חסר משמעות — ושינוי שלו הוא הדבר היחיד שאין לו מעקף.

### מגבלה שחייבים להכיר

סיבוב מפתח נאכף מ**אנדרואיד 9 (API 28)** ומעלה. ה-`minSdk` כאן הוא **24**, ולכן:

> **במכשירי אנדרואיד 7 ו-8 מפתח הדיבאג נשאר עוגן האמון.**

כלומר: **`debug.keystore` הופך מעכשיו לנכס שאסור לאבד** — בדיוק כמו המפתח החדש. בלעדיו אי אפשר יהיה לייצר את השרשרת שוב, ומשתמשי אנדרואיד ישן לא יקבלו עדכונים לעולם.

---

## ההליך

### 1. יצירת המפתח החדש — פעם אחת

```powershell
keytool -genkeypair -v -keystore C:\keys\sofer-release.jks -storetype JKS `
        -keyalg RSA -keysize 4096 -validity 10000 -alias sofer
```

בחר סיסמה שאינה בשימוש בשום מקום אחר.

### 2. גיבוי — לפני כל דבר אחר

**שלושה קבצים, בשני מקומות נפרדים לפחות, שאינם המחשב הזה:**

```
C:\keys\sofer-release.jks      המפתח החדש
~/.android/debug.keystore      המפתח הישן — כבר לא ניתן להחלפה
C:\keys\lineage.bin            השרשרת (שלב 3)
```

אובדן של הראשון = אי אפשר לעדכן אף משתמש, לעולם.
אובדן של השני = משתמשי אנדרואיד 7–8 תקועים.

### 3. יצירת השרשרת — פעם אחת

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\37.0.0\apksigner.bat" rotate `
    --out C:\keys\lineage.bin `
    --old-signer --ks "$env:USERPROFILE\.android\debug.keystore" `
                 --ks-key-alias androiddebugkey --ks-pass pass:android `
    --new-signer --ks C:\keys\sofer-release.jks --ks-key-alias sofer
```

### 4. `android/key.properties`

```properties
storeFile=C:/keys/sofer-release.jks
storePassword=...
keyAlias=sofer
keyPassword=...
```

הקובץ ב-`.gitignore` ואסור שייכנס למאגר.

### 5. בנייה וחתימה

Gradle אינו יודע לצרף שרשרת ייחוס, ולכן החתימה נעשית אחריו:

```powershell
flutter build apk --release
.\tool\sign_release.ps1
```

`sign_release.ps1` חותם מחדש עם המפתח החדש **בצירוף השרשרת**, ואז מאמת ומדפיס את שתי התעודות. **אל תפרסם APK שלא עבר דרכו.**

---

## אימות לפני פרסום

```powershell
apksigner verify --print-certs -v <apk>
```

צריך להופיע:

- `Verified using v3 scheme: true`
- התעודה **החדשה** כחותמת
- שורת lineage שמזכירה את התעודה הישנה

אם אין lineage — **כל משתמש קיים ייתקע**. אל תפרסם.

## בדיקה אמיתית לפני פרסום

התקן על מכשיר שיש בו **0.3.1 מגיטהאב** ובדוק שהעדכון עובר בלי הסרה ושהנתונים שם. זו הבדיקה היחידה שסופרת.
