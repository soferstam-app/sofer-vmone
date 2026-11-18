import { messages } from './account-messages.mjs';

const preference = 'sofer-account-language';
export function accountLanguageChoice() {
  try {
    const code = localStorage.getItem(preference);
    if (['he', 'en', 'yi'].includes(code)) return code;
  } catch {
    // The login remains available when the browser blocks storage.
  }
  return null;
}

export function accountLanguage() {
  return accountLanguageChoice() ?? 'he';
}

export function setAccountLanguage(code) {
  if (!['he', 'en', 'yi'].includes(code)) return false;
  try {
    localStorage.setItem(preference, code);
    return true;
  } catch {
    return false;
  }
}

export function t(hebrew, values = {}) {
  const index = { en: 0, yi: 1 }[accountLanguage()];
  const text = messages.get(hebrew)?.[index] ?? hebrew;
  return text.replace(/\{(\w+)\}/g, (match, key) => String(values[key] ?? match));
}

export function localizeAccountPage() {
  const language = accountLanguage();
  document.documentElement.lang = language;
  document.documentElement.dir = language === 'en' ? 'ltr' : 'rtl';
  document.title = t(document.title);
  const nodes = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  while (nodes.nextNode()) {
    const node = nodes.currentNode;
    if (node.parentElement.closest('script, style, noscript, [data-account-language]')) continue;
    const original = node.textContent;
    const phrase = original.trim().replace(/\s+/g, ' ');
    if (messages.has(phrase)) node.textContent = original.replace(/\S[\s\S]*\S|\S/, () => t(phrase));
  }
  for (const element of document.querySelectorAll('[aria-label], meta[name="description"]')) {
    const attribute = element.matches('meta') ? 'content' : 'aria-label';
    element.setAttribute(attribute, t(element.getAttribute(attribute)));
  }
  const picker = document.querySelector('[data-account-language]');
  if (!picker) return;
  picker.setAttribute('aria-label', t('שפת הממשק'));
  picker.value = language;
  picker.addEventListener('change', () => {
    if (setAccountLanguage(picker.value)) location.reload();
    else picker.value = language;
  });
}
