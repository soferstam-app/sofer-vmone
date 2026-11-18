# בניית ממשק הדפדפן של סופר ומונה

מתיקייה זו בונים את Flutter עם ההגדרות המשותפות לחבילות האפליקציה, ומוסיפים את קוד הדפדפן ממעטפת החשבון.

~~~powershell
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --output build/account-web --dart-define=SOFER_YIDDISH_PREVIEW=true
npm ci --prefix server
npm run build:account --prefix server
~~~

התוצר נמצא ב־`build/account-web`. בנייה מקומית מפיקה את ממשק הדפדפן. הפעלת החשבונות באתר דורשת את שירות החשבונות בשרת.
