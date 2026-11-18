import {
  createUserWithEmailAndPassword, GoogleAuthProvider, reauthenticateWithPopup, reload,
  sendEmailVerification, signInWithEmailAndPassword, signOut,
  updatePassword, updateProfile,
} from 'firebase/auth';
import { t } from './account-language.mjs';

const settings = () => ({ url: location.origin + '/' });
const passwordHelp = t('הסיסמה צריכה לכלול לפחות 8 תווים, אות אנגלית קטנה ומספר.');

function passwordError(password, confirmation) {
  if (password.length < 8 || !/[a-z]/.test(password) || !/[0-9]/.test(password)) return passwordHelp;
  return password === confirmation ? '' : t('הסיסמאות אינן זהות.');
}

export function installEmailAuth(auth, status, openAccount, googleButton, choosePersistence) {
  const panel = document.querySelector('#email-auth');
  const form = document.querySelector('#email-auth-form');
  const registration = document.querySelector('#email-register-form');
  const title = document.querySelector('#sign-in-title');
  const feedback = document.querySelector('#email-feedback');
  const actions = document.querySelector('#email-actions');
  const modeButton = document.querySelector('#email-mode');
  const reset = document.querySelector('#email-reset');
  const pending = document.querySelector('#email-pending');
  const email = form.elements.namedItem('email');
  const registerEmail = registration.elements.namedItem('email');
  let working = false;

  function showPending(user) {
    form.remove();
    registration.remove();
    form.reset();
    registration.reset();
    actions.hidden = true;
    googleButton.hidden = true;
    document.querySelector('#remember-sign-in').parentElement.hidden = true;
    pending.hidden = false;
    title.textContent = t('אימות כתובת המייל');
    status.textContent = t('פתחו את קישור האימות שנשלח לכתובת {email}. אחר כך חזרו לכאן ולחצו על „אימתתי את המייל”.', { email: user.email });
  }

  async function busy(action, fallback, progress = '') {
    if (working) return;
    working = true;
    feedback.textContent = progress;
    const controls = [...panel.querySelectorAll('button'), googleButton];
    controls.forEach(control => { control.disabled = true; });
    try {
      await action();
    } catch (error) {
      feedback.textContent = error?.code === 'auth/too-many-requests'
        ? t('בוצעו ניסיונות רבים. נסו שוב מאוחר יותר.')
        : error?.code === 'auth/network-request-failed'
          ? t('לא התקבל מענה משירות הכניסה. בדקו את החיבור ונסו שוב.')
          : typeof fallback === 'function' ? fallback(error) : fallback;
    } finally {
      working = false;
      controls.forEach(control => { control.disabled = false; });
    }
  }

  function showForm(next, heading, description, focus) {
    for (const current of [form, registration]) {
      current.hidden = current !== next;
      if (current.hidden) {
        for (const field of current.querySelectorAll('input[type=password]')) field.value = '';
      }
    }
    googleButton.hidden = next !== form;
    feedback.textContent = '';
    modeButton.textContent = next === form ? t('פתיחת חשבון במייל') : t('חזרה לכניסה');
    reset.hidden = next !== form;
    title.textContent = heading;
    status.textContent = description;
    focus.focus();
  }

  modeButton.onclick = () => {
    if (form.hidden) {
      if (!email.value) email.value = registerEmail.value;
      showForm(form, t('כניסה לסביבת העבודה'), t('היכנסו עם מייל וסיסמה או עם Google.'), email);
    } else {
      if (!registerEmail.value) registerEmail.value = email.value;
      showForm(registration, t('פתיחת חשבון'), t('לאחר יצירת החשבון נאמת את כתובת המייל.'),
        registration.elements.namedItem('name'));
    }
  };
  form.onsubmit = event => {
    event.preventDefault();
    void busy(async () => {
      await choosePersistence();
      const { user } = await signInWithEmailAndPassword(
        auth, email.value.trim(), form.elements.namedItem('password').value,
      );
      feedback.textContent = '';
      if (user.emailVerified) {
        form.remove();
        panel.hidden = true;
        form.reset();
        openAccount(user);
      } else {
        showPending(user);
      }
    }, t('לא ניתן להיכנס. בדקו את המייל והסיסמה, או נסו לאפס את הסיסמה.'), t('מתחברים…'));
  };
  registration.onsubmit = event => {
    event.preventDefault();
    const displayName = registration.elements.namedItem('name').value.trim();
    const password = registration.elements.namedItem('password').value;
    const confirmation = registration.elements.namedItem('confirm-password').value;
    const problem = displayName ? passwordError(password, confirmation) : t('יש להזין שם.');
    if (problem) {
      feedback.textContent = problem;
      return;
    }
    void busy(async () => {
      await choosePersistence();
      const { user } = await createUserWithEmailAndPassword(auth, registerEmail.value.trim(), password);
      showPending(user);
      feedback.textContent = t('שולחים קישור אימות…');
      const profileSaved = updateProfile(user, { displayName }).catch(() => {});
      try {
        await sendEmailVerification(user, settings());
        feedback.textContent = t('שלחנו קישור אימות. כדאי לבדוק גם בתיקיית הספאם.');
      } catch {
        feedback.textContent = t('החשבון נוצר, אבל שליחת קישור האימות נכשלה. לחצו על „שלחו שוב קישור”.');
      }
      await profileSaved;
    }, error => error?.code === 'auth/email-already-in-use'
      ? t('אי אפשר לפתוח חשבון נוסף עם הכתובת הזאת. חזרו לכניסה או בחרו „שכחתי סיסמה”.')
      : t('פתיחת החשבון נכשלה. בדקו את הפרטים ונסו שוב.'), t('פותחים חשבון…'));
  };
  for (const current of [form, registration]) {
    current.addEventListener('invalid', event => {
      feedback.textContent = event.target.validity.tooShort
        ? passwordHelp : t('יש למלא את כל השדות המסומנים ולבדוק את כתובת המייל.');
    }, true);
  }
  document.querySelector('#email-check').onclick = () => void busy(async () => {
    const user = auth.currentUser;
    await reload(user);
    if (!user.emailVerified) {
      feedback.textContent = t('כתובת המייל עדיין ממתינה לאימות. פתחו את הקישור שנשלח אליכם.');
      return;
    }
    await user.getIdToken(true);
    panel.hidden = true;
    openAccount(user);
  }, t('לא הצלחנו לבדוק את האימות. נסו שוב.'));
  document.querySelector('#email-resend').onclick = () => void busy(async () => {
    await sendEmailVerification(auth.currentUser, settings());
    feedback.textContent = t('נשלח קישור אימות חדש.');
  }, t('לא הצלחנו לשלוח קישור כרגע. נסו שוב מאוחר יותר.'));
  document.querySelector('#email-exit').onclick = () => void busy(async () => {
    await signOut(auth);
    location.replace('/');
  }, t('לא הצלחנו לצאת. נסו שוב.'));

  panel.hidden = false;
  return { showPending };
}

export function setupAccountPassword(auth, user, locked) {
  const dialog = document.querySelector('#account-password');
  const form = document.querySelector('#password-form');
  const feedback = document.querySelector('#password-status');
  const submit = form.querySelector('[type=submit]');
  const password = form.elements.namedItem('password');
  const repeated = form.elements.namedItem('repeated');
  const email = form.elements.namedItem('email');
  dialog.addEventListener('close', () => form.reset());
  globalThis.soferAccountPassword = () => {
    if (locked() || dialog.open) return;
    email.value = user.email;
    feedback.textContent = '';
    form.hidden = false;
    dialog.showModal();
  };
  form.onsubmit = async event => {
    event.preventDefault();
    if (locked() || auth.currentUser?.uid !== user.uid) return;
    const problem = passwordError(password.value, repeated.value);
    if (problem) {
      feedback.textContent = problem;
      return;
    }
    const value = password.value;
    submit.disabled = true;
    try {
      if (user.providerData.some(provider => provider.providerId === 'google.com')) {
        await reauthenticateWithPopup(user, new GoogleAuthProvider());
      }
      if (locked() || auth.currentUser?.uid !== user.uid || !dialog.open) return;
      if (user.providerData.some(provider => provider.providerId === 'password')) {
        await updatePassword(user, value);
      } else {
        // Firebase requires accounts:signUp for linking under email enumeration protection.
        const url = new URL('https://identitytoolkit.googleapis.com/v1/accounts:signUp');
        url.searchParams.set('key', auth.app.options.apiKey);
        const result = await fetch(url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ idToken: await user.getIdToken(), email: user.email, password: value }),
        });
        if (!result.ok) throw new Error('Could not add password');
      }
      feedback.textContent = t('הסיסמה נשמרה. אפשר להיכנס לחשבון הזה עם המייל והסיסמה.');
      form.reset();
      form.hidden = true;
    } catch (error) {
      feedback.textContent = error?.code === 'auth/requires-recent-login'
        ? t('לשינוי הסיסמה, היכנסו מחדש או השתמשו באיפוס סיסמה ממסך הכניסה.')
        : t('לא הצלחנו לשמור את הסיסמה. בדקו את הפרטים ונסו שוב.');
    } finally {
      submit.disabled = false;
    }
  };
}
