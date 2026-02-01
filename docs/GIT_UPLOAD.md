# העלאת הפרויקט לגיטהאב – מה מעלים ומה לא

## קבצים חשובים שיעלו (נכללים ב־commit)

- **קוד האפליקציה**: `lib/*.dart` – כל הקבצים במסכים, שירותים ומודלים  
- **הגדרות**: `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`  
- **אנדרואיד**: `android/` (ללא build ו־XML הכפול – ראו למטה)  
- **iOS**: `ios/` (לפי ה־.gitignore של ios)  
- **Windows / Linux / macOS**: `windows/`, `linux/`, `macos/`  
- **Web**: `web/`  
- **נכסים**: `assets/`  
- **מסמכים**: `README.md`, `CHANGELOG.md`, `docs/index.html`, `docs/privacy_policy*.html`, `docs/*.mp4`, `docs/*.gif`, `docs/buy-me-a-coffee-description.md`  
- **טסטים**: `test/`  
- **חבילה מקומית**: `packages/kosher_dart/` (התיקייה, לא קובץ ה־.tar.gz)

## קבצים שלא יעלו (ב־.gitignore)

- **Build**: `build/`, `.dart_tool/`, `android/app/build`, וכו'  
- **תעודות מקומיות**: `ca-bundle.crt`  
- **ארכיון חבילה**: `packages/*.tar.gz`  
- **תיקייה כפולה**: `android/app/src/XML/` (הקונפיג הרשמי ב־`main/res/xml/`)  
- **רשימות פיתוח**: `GEMINI.MD`  
- **תמונה ללא שימוש**: `docs/unnamed.jpg`

## פקודות להעלאה לגיטהאב

```bash
# בדיקה מה ישתנה
git status

# הוספת כל הקבצים החשובים (ה־.gitignore כבר מסנן זבל)
git add .

# אם הוספת בעבר קבצים שעכשיו ב־.gitignore והם עדיין ב־staging:
# git rm -r --cached android/app/src/XML/   # אם קיים
# git rm --cached packages/kosher_dart-2.0.18.tar.gz   # אם קיים
# git rm --cached ca-bundle.crt   # אם קיים

# commit
git commit -m "גרסה 0.3.0 – הוצאות, תאריכים לועזיים, עמודים באותיות, אודות ותרומה"

# שליחה ל־remote (החלף branch אם צריך)
git push origin main
```

לפני `git push` רצוי להריץ `git status` ו־`git diff --staged` ולוודא שאין קבצים רגישים או מיותרים.
