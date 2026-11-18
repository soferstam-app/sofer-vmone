import { initializeApp } from 'firebase/app';
import { inMemoryPersistence, initializeAuth, sendPasswordResetEmail } from 'firebase/auth';
import { accountLanguage, localizeAccountPage, t } from './account-language.mjs';

localizeAccountPage();

const form = document.querySelector('#email-reset-form');
const email = document.querySelector('#reset-email');
const submit = form.querySelector('button');
const feedback = document.querySelector('#email-feedback');

async function initialize() {
  const response = await fetch('/account-config', { cache: 'no-store' });
  if (!response.ok) throw new Error('Account settings unavailable');
  const { firebase, passwordEnabled } = await response.json();
  if (!passwordEnabled) throw new Error('Password reset disabled');
  const auth = initializeAuth(initializeApp(firebase), { persistence: inMemoryPersistence });
  auth.languageCode = accountLanguage() === 'en' ? 'en' : 'he';
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (submit.disabled) return;
    submit.disabled = true;
    feedback.textContent = t('שולחים בקשת איפוס…');
    try {
      await sendPasswordResetEmail(auth, email.value.trim(), { url: location.origin + '/' });
      feedback.textContent = t('אם אפשר לאפס סיסמה לכתובת הזאת, יישלח אליה קישור. כדאי לבדוק גם בתיקיית הספאם.');
    } catch (error) {
      feedback.textContent = error?.code === 'auth/too-many-requests'
        ? t('בוצעו ניסיונות רבים. נסו שוב מאוחר יותר.')
        : t('לא הצלחנו לשלוח את הבקשה כרגע. בדקו את החיבור ונסו שוב.');
    } finally {
      submit.disabled = false;
    }
  });
  email.addEventListener('invalid', () => {
    feedback.textContent = t('יש להזין כתובת מייל תקינה.');
  });
  email.disabled = false;
  submit.disabled = false;
  feedback.textContent = '';
}

initialize().catch(() => {
  feedback.textContent = t('שירות איפוס הסיסמה לא נטען. רעננו את הדף ונסו שוב.');
});
