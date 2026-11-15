import { en } from './dictionary.en.js';
import { vi } from './dictionary.vi.js';

/* Two-mode language switch, VI ⇄ EN.
 *
 * The page is written in Vietnamese in index.html. On the first pass we cache each
 * element's own markup by key, which means:
 *   - with JavaScript off the page is a complete Vietnamese site,
 *   - no Vietnamese string is duplicated into a JS file,
 *   - switching back to VI restores the original markup, including <strong> and <a>.
 *
 * innerHTML is intentional: every value here is authored in this repository, never
 * supplied by a visitor, so there is nothing to escape.
 */

const STORAGE_KEY = 'lyceum:lang';
const EVENTS = 'lyceum:lang';

/** key → original Vietnamese markup / attribute value */
const vietnamese = new Map();

let current = 'vi';

function nodes() {
  return document.querySelectorAll('[data-i18n],[data-i18n-alt],[data-i18n-aria]');
}

function cache() {
  for (const node of nodes()) {
    const textKey = node.getAttribute('data-i18n');
    if (textKey && !vietnamese.has(textKey)) {
      vietnamese.set(textKey, node.innerHTML);
    }
    for (const [attribute, dataKey] of [['alt', 'data-i18n-alt'], ['aria-label', 'data-i18n-aria']]) {
      const key = node.getAttribute(dataKey);
      if (key) {
        const cacheKey = `@${attribute}:${key}`;
        if (!vietnamese.has(cacheKey)) {
          vietnamese.set(cacheKey, node.getAttribute(attribute) || '');
        }
      }
    }
  }
}

function readStored() {
  try {
    const value = window.localStorage.getItem(STORAGE_KEY);
    return value === 'vi' || value === 'en' ? value : null;
  } catch {
    return null; // private mode: fall back to the browser, never throw
  }
}

function writeStored(language) {
  try {
    window.localStorage.setItem(STORAGE_KEY, language);
  } catch {
    /* ignore */
  }
}

/** vi|en from ?lang=, then storage, then the browser, then Vietnamese. */
function initialLanguage() {
  const fromUrl = new URLSearchParams(window.location.search).get('lang');
  if (fromUrl === 'vi' || fromUrl === 'en') {
    return fromUrl;
  }
  const stored = readStored();
  if (stored) {
    return stored;
  }
  const browsers = [navigator.language, ...(navigator.languages || [])].filter(Boolean);
  return browsers.some((tag) => tag.toLowerCase().startsWith('en')) ? 'en' : 'vi';
}


/** Look up a generated string (download buttons, status lines). */
export function t(key, language = current) {
  if (language === 'en') {
    return en[key] ?? vi[key] ?? key;
  }
  return vi[key] ?? en[key] ?? key;
}

function setMeta(selector, value) {
  const node = document.querySelector(selector);
  if (node) {
    node.setAttribute('content', value);
  }
}

export function apply(language, { persist = true } = {}) {
  current = language === 'en' ? 'en' : 'vi';

  for (const node of nodes()) {
    const textKey = node.getAttribute('data-i18n');
    if (textKey) {
      const original = vietnamese.get(textKey);
      if (original !== undefined) {
        node.innerHTML = current === 'en' ? (en[textKey] ?? original) : original;
      }
    }

    const altKey = node.getAttribute('data-i18n-alt');
    if (altKey) {
      const original = vietnamese.get(`@alt:${altKey}`);
      const value = current === 'en' ? (en[altKey] ?? original) : original;
      if (value !== undefined) {
        node.setAttribute('alt', value);
      }
    }

    const ariaKey = node.getAttribute('data-i18n-aria');
    if (ariaKey) {
      const original = vietnamese.get(`@aria-label:${ariaKey}`);
      const value = current === 'en' ? (en[ariaKey] ?? original) : original;
      if (value !== undefined) {
        node.setAttribute('aria-label', value);
      }
    }
  }

  // Anything that must be plain text even when the source had markup.
  const title = t('meta.title');
  document.title = title;
  setMeta('meta[name="description"]', t('meta.desc'));
  setMeta('meta[property="og:title"]', t('meta.title'));
  // og:description mirrors what the visitor actually sees: read the rendered
  // hero line instead of a dictionary key, so Vietnamese falls back to the HTML.
  const heroLede = document.querySelector('.lede');
  if (heroLede) {
    setMeta('meta[property="og:description"]', heroLede.textContent.trim());
  }

  document.documentElement.lang = current;

  for (const button of document.querySelectorAll('[data-lang]')) {
    button.setAttribute('aria-pressed', String(button.getAttribute('data-lang') === current));
  }

  if (persist) {
    writeStored(current);
  }

  document.dispatchEvent(new CustomEvent(EVENTS, { detail: { lang: current } }));
}

export function onLanguageChange(handler) {
  document.addEventListener(EVENTS, (event) => handler(event.detail.lang));
}

export function currentLanguage() {
  return current;
}

export function initI18n() {
  cache();

  for (const button of document.querySelectorAll('[data-lang]')) {
    button.addEventListener('click', () => apply(button.getAttribute('data-lang')));
  }

  apply(initialLanguage(), { persist: false });
  return current;
}
