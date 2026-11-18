import { initializeApp } from 'firebase/app';
import {
  browserLocalPersistence, browserSessionPersistence, getAuth, GoogleAuthProvider, onIdTokenChanged,
  setPersistence, signInWithPopup, signOut,
} from 'firebase/auth';
import { installEmailAuth, setupAccountPassword } from './email-auth.mjs';
import { accountLanguage, accountLanguageChoice, localizeAccountPage, setAccountLanguage, t } from './account-language.mjs';

localizeAccountPage();

const panel = document.querySelector('#sign-in');
const status = document.querySelector('#sign-in-status');
const options = document.querySelector('#sign-in-options');
const remember = document.querySelector('#remember-sign-in');
const notice = document.querySelector('#account-notice');
const saving = document.querySelector('#account-saving');
const chooseAccount = document.querySelector('#choose-account');
const demoKey = 'sofer-demo-account';
const phoneDialog = document.querySelector('#phone-link');
const emailCityNames = {
  Jerusalem: 'ירושלים', 'Tel Aviv': 'תל אביב', Haifa: 'חיפה', Ashdod: 'אשדוד',
  'Petach Tikvah': 'פתח תקווה', 'Beer Sheva': 'באר שבע',
};
let locked = false;

function showNotice(message, allowAccountChange = false) {
  document.querySelector('#notice-text').textContent = message;
  chooseAccount.hidden = !allowAccountChange;
  notice.hidden = false;
}

function concealWorkspace() {
  locked = true;
  phoneDialog.close();
  document.querySelector('#account-password').close();
  for (const view of document.querySelectorAll('flutter-view')) {
    view.style.display = 'none';
    view.inert = true;
  }
  notice.hidden = true;
  if (saving) saving.hidden = true;
}

function reopen() {
  concealWorkspace();
  location.replace('/');
}

document.querySelector('#reload').onclick = reopen;
window.addEventListener('pagehide', concealWorkspace);
window.addEventListener('pageshow', event => { if (event.persisted) reopen(); });

async function phoneRequest(tokenFor, method, body, signal, path = '/api/v1/phone-link') {
  const token = await tokenFor();
  if (locked || signal?.aborted) throw new Error('Account is closed');
  const headers = { Authorization: 'Bearer ' + token };
  if (body) headers['Content-Type'] = 'application/json';
  return fetch(path, {
    method, body, headers, signal, cache: 'no-store', redirect: 'error',
  });
}

async function readPhoneProfile(tokenFor, signal) {
  const response = await phoneRequest(tokenFor, 'GET', undefined, signal);
  if (!response.ok) throw new Error('Phone profile unavailable');
  return response.json();
}

function setupPhoneLink(tokenFor, user, startWorkspace, projectSelection, weeklyMailEnabled) {
  const form = document.querySelector('#phone-link-form');
  const verified = document.querySelector('#phone-verified');
  const feedback = document.querySelector('#phone-status');
  const challenge = document.querySelector('#phone-challenge');
  const code = document.querySelector('#phone-code');
  const submit = document.querySelector('#phone-create');
  const onboarding = document.querySelector('#phone-onboarding');
  const email = document.querySelector('#phone-account-email');
  const check = document.querySelector('#phone-check');
  const proceed = document.querySelector('#phone-continue');
  const switchAccount = document.querySelector('#phone-switch');
  const close = document.querySelector('#phone-close');
  const projects = document.querySelector('#phone-projects');
  const projectStatus = document.querySelector('#phone-project-status');
  const selections = [...projects.querySelectorAll('select')];
  const mail = document.querySelector('#weekly-mail');
  const mailStatus = document.querySelector('#weekly-mail-status');
  const cities = mail.elements.city;
  const weekdays = mail.elements.weekday;
  const mailSave = mail.querySelector('button');
  const days = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי לפני שבת', 'שבת — במוצאי שבת'];
  let timer;
  let session;
  let required = false;

  async function loadMail(signal) {
    mail.hidden = false;
    mailSave.disabled = true;
    mailStatus.textContent = t('טוען את הגדרות המייל…');
    try {
      const response = await phoneRequest(tokenFor, 'GET', undefined, signal, '/api/v1/weekly-mail');
      if (!response.ok) throw new Error('Weekly email unavailable');
      const result = await response.json();
      if (signal.aborted) return;
      cities.replaceChildren(new Option(t('בחרו עיר'), ''), ...result.cities.map(city => new Option(t(emailCityNames[city] ?? city), city)));
      weekdays.replaceChildren(new Option(t('ללא שליחה קבועה'), ''), ...days.map((day, index) => new Option(t(day), index)));
      cities.value = result.preference?.city ?? '';
      weekdays.value = result.preference?.weekday ?? '';
      mailSave.disabled = false;
      showNextMail(result.preference);
    } catch {
      if (!signal.aborted) mailStatus.textContent = t('הגדרות המייל אינן זמינות כרגע.');
    }
  }

  function showNextMail(preference) {
    const at = preference?.nextAt;
    mailStatus.textContent = at ? t('השליחה הבאה מתוכננת ל־{date}.', {
      date: new Intl.DateTimeFormat(document.documentElement.lang, {
        dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Jerusalem',
      }).format(at),
    }) : '';
  }

  mail.onsubmit = async event => {
    event.preventDefault();
    if (mailSave.disabled || !session || !cities.value) return;
    const { signal } = session;
    mailSave.disabled = true;
    try {
      const body = JSON.stringify({ city: cities.value, weekday: weekdays.value === '' ? null : Number(weekdays.value) });
      const response = await phoneRequest(tokenFor, 'PUT', body, signal, '/api/v1/weekly-mail');
      if (!response.ok) throw new Error('Cannot save weekly email preferences');
      const { preference } = await response.json();
      if (signal.aborted) return;
      showNextMail(preference);
      if (!mailStatus.textContent) mailStatus.textContent = t('הגדרות המייל נשמרו.');
    } catch {
      if (!signal.aborted) mailStatus.textContent = t('הגדרות המייל לא נשמרו. נסו שוב.');
    } finally {
      if (!signal.aborted) mailSave.disabled = false;
    }
  };

  async function loadProjects(signal) {
    projects.hidden = false;
    projectStatus.textContent = t('טוען פרויקטים…');
    for (const select of selections) {
      select.disabled = true;
      select.replaceChildren();
    }
    try {
      const response = await phoneRequest(tokenFor, 'GET', undefined, signal, '/api/v1/phone-projects');
      if (!response.ok) throw new Error('Phone projects unavailable');
      const settings = await response.json();
      if (signal.aborted) return;
      for (const select of selections) {
        const { projects: choices, selected } = settings[select.name];
        const placeholder = choices.length === 1 ? t('אוטומטי · {project}', { project: choices[0].name })
          : choices.length ? t('ללא בחירה קבועה') : t('אין פרויקטים מתאימים');
        select.replaceChildren(new Option(placeholder, ''), ...choices.map(({ id, name }) => new Option(name, id)));
        select.value = selected ?? '';
        select.disabled = !choices.length;
      }
      projectStatus.textContent = '';
    } catch {
      if (!signal.aborted) projectStatus.textContent = t('לא הצלחנו לטעון את הפרויקטים. אפשר לסגור ולפתוח שוב את ההגדרות.');
    }
  }

  for (const select of selections) {
    select.onchange = async () => {
      const { signal } = session;
      select.disabled = true;
      projectStatus.textContent = t('שומר בחירה…');
      try {
        const body = JSON.stringify({ category: select.name, projectId: select.value || null });
        const response = await phoneRequest(tokenFor, 'PUT', body, signal, '/api/v1/phone-projects');
        if (!response.ok) throw new Error('Project selection failed');
        if (!signal.aborted) {
          select.disabled = false;
          projectStatus.textContent = t('הבחירה נשמרה לדיווחים הבאים.');
        }
      } catch {
        if (!signal.aborted) {
          await loadProjects(signal);
          if (!signal.aborted) projectStatus.textContent = t('הבחירה לא נשמרה. בדקו שהפרויקט עדיין זמין ונסו שוב.');
        }
      }
    };
  }

  async function refresh(signal, knownProfile) {
    clearTimeout(timer);
    check.disabled = true;
    submit.disabled = true;
    try {
      const profile = knownProfile ?? await readPhoneProfile(tokenFor, signal);
      if (signal.aborted) return;
      verified.textContent = profile.verified
        ? t('מספר מאומת המסתיים ב־{suffix} · {email}', profile.verified) : '';
      if (required && profile.verified) {
        form.hidden = true;
        challenge.hidden = true;
        code.value = '';
        check.hidden = true;
        proceed.hidden = false;
        feedback.textContent = t('הטלפון אומת. לאחר פתיחת סביבת העבודה אפשר ליצור פרויקט או להמשיך לפרויקט קיים.');
        proceed.focus();
        return;
      }
      if (!required && profile.verified && projectSelection && projects.hidden) void loadProjects(signal);
      if (!required && profile.verified && weeklyMailEnabled && mail.hidden) void loadMail(signal);
      if (!profile.pending) {
        const wasWaiting = !challenge.hidden;
        challenge.hidden = true;
        code.value = '';
        form.hidden = false;
        submit.disabled = false;
        feedback.textContent = profile.verified
          ? t('אפשר לשייך מספר אחר באמצעות אימות חדש.')
          : wasWaiting ? t('קוד השיוך אינו פעיל. אפשר להפיק קוד חדש.') : '';
        if (wasWaiting && profile.verified) {
          feedback.textContent = t('מצב השיוך התעדכן. המספר המאומת מוצג למעלה.');
        }
        return;
      }
      if (challenge.hidden) {
        form.hidden = false;
        submit.disabled = false;
        feedback.textContent = t('יש קוד פעיל. אם הוא עדיין בידכם, אפשר להשלים את השיוך בשיחה.');
      } else {
        feedback.textContent = t('ממתין לאימות מהקו…');
      }
      timer = setTimeout(() => refresh(signal), 5000);
    } catch {
      if (signal.aborted) return;
      feedback.textContent = t('לא ניתן לבדוק את מצב השיוך כרגע.');
      if (!challenge.hidden) timer = setTimeout(() => refresh(signal), 5000);
      else submit.disabled = false;
    } finally {
      if (!signal.aborted) check.disabled = false;
    }
  }

  phoneDialog.addEventListener('cancel', event => {
    if (required) event.preventDefault();
  });
  phoneDialog.addEventListener('close', () => {
    if (phoneDialog.open) return;
    session?.abort();
    clearTimeout(timer);
    code.value = '';
    form.reset();
    mail.hidden = true;
  });
  form.onsubmit = async event => {
    event.preventDefault();
    const { signal } = session;
    if (submit.disabled || locked) return;
    clearTimeout(timer);
    submit.disabled = true;
    check.disabled = true;
    feedback.textContent = t('מפיק קוד שיוך…');
    try {
      const body = JSON.stringify(Object.fromEntries(new FormData(form)));
      const response = await phoneRequest(tokenFor, 'POST', body, signal);
      if (response.status === 409) {
        if (!signal.aborted) {
          feedback.textContent = t('לא ניתן לשייך את המספר כרגע. אם הוא כבר משויך, השתמשו בחשבון המקורי. אם ביקשתם קוד כעת, המתינו חצי דקה.');
          timer = setTimeout(() => refresh(signal), 30_000);
        }
        return;
      }
      if (response.status === 400) {
        if (!signal.aborted) feedback.textContent = t('יש להזין שם ומספר טלפון ישראלי תקין.');
        return;
      }
      if (!response.ok) throw new Error('Challenge unavailable');
      const result = await response.json();
      if (signal.aborted) return;
      code.value = result.code;
      form.hidden = true;
      challenge.hidden = false;
      feedback.textContent = t('ממתין לאימות מהקו…');
      timer = setTimeout(() => refresh(signal), 5000);
    } catch {
      if (!signal.aborted) feedback.textContent = t('הפקת הקוד נכשלה. אפשר לנסות שוב.');
    } finally {
      if (!signal.aborted) {
        check.disabled = false;
        submit.disabled = false;
      }
    }
  };
  check.onclick = () => void refresh(session.signal);
  switchAccount.onclick = async () => {
    switchAccount.disabled = true;
    try {
      await globalThis.soferAccountSignOut();
    } catch {
      feedback.textContent = t('לא הצלחנו לצאת מהחשבון. נסו שוב.');
      switchAccount.disabled = false;
    }
  };
  proceed.onclick = () => {
    if (locked || proceed.hidden) return;
    proceed.hidden = true;
    phoneDialog.close();
    startWorkspace();
  };
  function open(knownProfile) {
    if (locked || phoneDialog.open) return;
    required = knownProfile !== undefined;
    onboarding.hidden = !required;
    email.hidden = !required;
    email.textContent = required ? t('כתובת החשבון: {email}', { email: user.email }) : '';
    check.hidden = false;
    proceed.hidden = true;
    switchAccount.hidden = !required;
    close.hidden = required;
    projects.hidden = true;
    session = new AbortController();
    form.elements.namedItem('name').value = user.displayName ?? '';
    verified.textContent = '';
    feedback.textContent = t('טוען את מצב השיוך…');
    challenge.hidden = true;
    form.hidden = false;
    submit.disabled = true;
    phoneDialog.showModal();
    void refresh(session.signal, knownProfile);
  }
  globalThis.soferAccountLinkPhone = () => open();
  return open;
}

function configureSignOut(exit) {
  globalThis.soferAccountSignOut = async () => {
    if (locked) return;
    locked = true;
    try {
      await exit();
    } catch (error) {
      locked = false;
      throw error;
    }
    reopen();
  };
  chooseAccount.onclick = async () => {
    try {
      await globalThis.soferAccountSignOut();
    } catch {
      showNotice(t('היציאה נכשלה. אפשר לנסות שוב.'), true);
    }
  };
}

function startApp(tokenFor) {
  options.replaceChildren();
  status.textContent = t('טוען את החשבון…');
  globalThis.soferAccountLanguage = accountLanguageChoice();
  globalThis.soferRememberAccountLanguage = setAccountLanguage;
  globalThis.soferAccountLoadFailed = () => {
    if (notice.hidden) showNotice(t('טעינת החשבון נכשלה. אפשר לנסות שוב.'), !panel.hidden);
  };
  async function request(method, body) {
    if (locked) throw new Error('Account is closed');
    const token = await tokenFor();
    if (locked) throw new Error('Account is closed');
    const headers = { Authorization: 'Bearer ' + token };
    if (method === 'PUT') headers['Content-Type'] = 'application/json';
    const response = await fetch('/api/v1/workspace', {
      method, body, headers, cache: 'no-store', redirect: 'error',
    });
    if (response.status === 409) {
      showNotice(t('החשבון השתנה בחלון אחר. טען מחדש כדי לעבוד עם הנתונים המעודכנים.'));
    } else if (response.status === 403) {
      showNotice(t('הגישה לחשבון דורשת אימות. טענו את הדף מחדש כדי להמשיך.'), !panel.hidden);
    }
    return JSON.stringify({ status: response.status, body: await response.json() });
  }
  // Fetch the account while Flutter is downloading and starting up.
  let initialWorkspace = request('GET');
  initialWorkspace.catch(() => {}); // Dart may attach after a fast failure.
  globalThis.soferAccountRequest = async (method, body) => {
    if (method === 'GET' && initialWorkspace) {
      const pending = initialWorkspace;
      initialWorkspace = null;
      return pending;
    }
    if (method !== 'PUT') return request(method, body);
    if (saving) saving.hidden = false;
    try {
      return await request(method, body);
    } finally {
      if (saving) saving.hidden = true;
    }
  };
  const script = document.createElement('script');
  script.src = '/flutter_bootstrap.js';
  script.onerror = globalThis.soferAccountLoadFailed;
  window.addEventListener('flutter-first-frame', () => { panel.hidden = true; }, { once: true });
  document.body.append(script);
}

function button(label, action) {
  const control = document.createElement('button');
  control.textContent = label;
  control.onclick = async () => {
    for (const choice of options.children) choice.disabled = true;
    try {
      await action();
    } catch {
      status.textContent = t('הכניסה נכשלה. אפשר לנסות שוב.');
      for (const choice of options.children) choice.disabled = false;
    }
  };
  options.append(control);
  return control;
}

async function demoSignIn(account) {
  const response = await fetch('/local-demo-sign-in', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ account }), cache: 'no-store',
  });
  if (!response.ok) throw new Error('Demo sign-in failed');
  const { token } = await response.json();
  sessionStorage.setItem(demoKey, account);
  configureSignOut(() => sessionStorage.removeItem(demoKey));
  startApp(() => token);
}

async function initialize() {
  const response = await fetch('/account-config', { cache: 'no-store' });
  if (!response.ok) throw new Error('Account settings unavailable');
  const config = await response.json();
  if (config.demo && location.hostname === '127.0.0.1') {
    const remembered = sessionStorage.getItem(demoKey);
    if (remembered) {
      try {
        await demoSignIn(remembered);
        return;
      } catch {
        sessionStorage.removeItem(demoKey);
      }
    }
    status.textContent = t('בחר חשבון דמה');
    button(t('חשבון דמה א׳'), () => demoSignIn('alice'));
    button(t('חשבון דמה ב׳'), () => demoSignIn('bob'));
    return;
  }
  const auth = getAuth(initializeApp(config.firebase));
  auth.languageCode = accountLanguage() === 'en' ? 'en' : 'he';
  await auth.authStateReady();
  const choosePersistence = () => setPersistence(auth, remember.checked
    ? browserLocalPersistence : browserSessionPersistence);
  function openAccount(user) {
    if (locked) return;
    remember.parentElement.hidden = true;
    if (config.passwordEnabled && user.providerData.some(provider => provider.providerId === 'google.com')) {
      setupAccountPassword(auth, user, () => locked);
    }
    onIdTokenChanged(auth, current => {
      if (!locked && current?.uid !== user.uid) reopen();
    });
    const tokenFor = () => {
      if (auth.currentUser?.uid !== user.uid) throw new Error('Account changed');
      return user.getIdToken();
    };
    configureSignOut(() => signOut(auth));
    const startWorkspace = () => startApp(tokenFor);
    const openPhone = setupPhoneLink(tokenFor, user, startWorkspace, config.phoneProjectSelection, config.weeklyMail);
    if (!config.phoneRequired) {
      startWorkspace();
      return;
    }
    options.replaceChildren();
    document.querySelector('#email-auth').hidden = true;
    status.textContent = t('בודקים אם הטלפון כבר משויך…');
    void readPhoneProfile(tokenFor).then(profile => {
      if (locked) return;
      if (profile.verified) startWorkspace();
      else openPhone(profile);
    }).catch(() => {
      if (!locked) showNotice(t('לא הצלחנו לבדוק אם הטלפון משויך. טענו מחדש ונסו שוב.'), true);
    });
  }
  if (auth.currentUser?.emailVerified) {
    openAccount(auth.currentUser);
    return;
  }
  if (auth.currentUser && !config.passwordEnabled) await signOut(auth);
  status.textContent = t('היכנס לחשבון כדי לפתוח את סביבת העבודה');
  remember.parentElement.hidden = Boolean(auth.currentUser);
  const google = button(t('כניסה עם Google'), async () => {
    await choosePersistence();
    const { user } = await signInWithPopup(auth, new GoogleAuthProvider());
    if (!user.emailVerified) {
      if (emailAuth) emailAuth.showPending(user);
      else {
        await signOut(auth);
        throw new Error('Email is unverified');
      }
      return;
    }
    document.querySelector('#email-auth').hidden = true;
    openAccount(user);
  });
  const emailAuth = config.passwordEnabled
    ? installEmailAuth(auth, status, openAccount, google, choosePersistence) : null;
  if (emailAuth) google.classList.add('auth-secondary');
  if (auth.currentUser) emailAuth?.showPending(auth.currentUser);
}

initialize().catch(() => showNotice(t('מסך הכניסה אינו זמין כרגע. אפשר לנסות שוב.')));
