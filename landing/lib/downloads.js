import { t, currentLanguage, onLanguageChange } from './i18n.js';

/* Download buttons, built from ./download-config.json at run time.
 *
 * Why a JSON file instead of markup: the person shipping the app is not always the
 * person who wants to open an HTML file. Publishing a build means dropping the new
 * URL in one place, and the page follows — including which button is highlighted
 * for the visitor's own machine.
 *
 * A channel with an empty `url` is never a dead button: it falls back to the
 * `signupUrl` action, or says "coming soon" if there is no fallback either.
 */

const CONFIG_URL = './download-config.json';

/** Same shape as the JSON, so a missing file still paints four real buttons. */
const FALLBACK_CONFIG = {
  version: '0.4.0',
  requirements: { macos: '14.2', windows: '10' },
  signupUrl: 'https://github.com/Julie22-yaerin/PRESENTATION/issues/new?title=Beta%20link',
  channels: [
    { id: 'mac-arm', platform: 'macos', arch: 'arm64', labelKey: 'gen.appleSilicon', icon: 'apple', url: '', sizeMb: 0 },
    { id: 'mac-intel', platform: 'macos', arch: 'x64', labelKey: 'gen.intel', icon: 'apple', url: '', sizeMb: 0 },
    { id: 'win', platform: 'windows', labelKey: 'gen.windows', icon: 'windows', url: '', sizeMb: 0 }
  ]
};

const ICONS = {
  apple:
    '<path d="M16.4 12.9c0-2.5 2-3.7 2.1-3.8-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9s-1.9-.9-3.2-.8c-1.6 0-3.1 1-4 2.4-1.8 3.1-.5 7.6 1.2 10.1.8 1.2 1.9 2.6 3.2 2.5 1.3 0 1.8-.8 3.3-.8s2 .8 3.3.8 2.2-1.2 3.1-2.4c.6-.9 1-1.8 1.2-2.3-2.6-1-2.9-4.1-3-4.2z"/><path d="M14.1 5.6c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.1 1.8-1 2.9 1.1.1 2.2-.6 2.8-1.4z"/>',
  windows:
    '<path d="M3 5.4 10.4 4.4v7.1H3zM11.6 4.2 21 2.9v8.6h-9.4zM3 12.5h7.4v7.1L3 18.6zM11.6 12.5H21v8.6l-9.4-1.3z"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5.2l3.4 2"/>',
  // filled shapes only: .dl__icon svg uses fill="currentColor"
  code: '<path d="M8.6 4.2 3.1 12l5.5 7.8 1.7-1.2L6.1 12l4.2-6.6z"/><path d="M15.4 4.2l-1.7 1.2L17.9 12l-4.2 6.6 1.7 1.2L20.9 12z"/>'
};

function svgFor(name) {
  const body = ICONS[name] ?? ICONS.clock;
  return `<svg class="dl__icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" focusable="false">${body}</svg>`;
}

/** Only real download schemes may end up in an href. */
function safeUrl(value) {
  if (typeof value !== 'string' || value.trim() === '') {
    return '';
  }
  try {
    const url = new URL(value, window.location.href);
    return ['https:', 'http:', 'mailto:'].includes(url.protocol) ? url.href : '';
  } catch {
    return '';
  }
}

/**
 * Desktop only. There is no iOS or Android build, so a phone must never be told
 * "the first button is yours" — a desktop Mac reports MacIntel, an iPhone
 * reports iPhone, and userAgentData.mobile splits the desktop-mode spoof.
 */
function detectPlatform() {
  const data = navigator.userAgentData;
  const hints = [data?.platform, navigator.platform, navigator.userAgent]
    .map((value) => String(value ?? '').toLowerCase())
    .join(' ');
  if (data?.mobile === true || /iphone|ipad|ipod|android/.test(hints)) {
    return 'other';
  }
  if (hints.includes('mac')) {
    return 'macos';
  }
  if (hints.includes('win')) {
    return 'windows';
  }
  return 'other';
}

/**
 * Apple Silicon reports an Apple GPU to WebGL; Intel Macs report Intel or AMD.
 * Unknown is fine — we simply do not pre-select a channel.
 */
function detectMacArch() {
  try {
    const canvas = document.createElement('canvas');
    const gl = canvas.getContext('webgl');
    if (!gl) {
      return 'unknown';
    }
    const debug = gl.getExtension('WEBGL_debug_renderer_info');
    const renderer = String(debug ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER));
    if (/apple m\d|apple gpu|apple silicon/i.test(renderer)) {
      return 'arm64';
    }
    if (/intel|amd|radeon|geforce/i.test(renderer)) {
      return 'x64';
    }
  } catch {
    /* older Safari blocks the extension: leave the choice to the visitor */
  }
  return 'unknown';
}

async function loadConfig() {
  try {
    const response = await fetch(CONFIG_URL, { cache: 'no-store' });
    if (!response.ok) {
      throw new Error(String(response.status));
    }
    const json = await response.json();
    if (!Array.isArray(json.channels) || json.channels.length === 0) {
      throw new Error('no channels');
    }
    return { ...FALLBACK_CONFIG, ...json };
  } catch {
    return { ...FALLBACK_CONFIG, _loadFailed: true };
  }
}

/**
 * The tile that matches this visitor's machine.
 *
 * A published build wins the star. But while a channel is still pending
 * (`url` empty), an unmarked page would contradict the status line, which
 * already tells the visitor that the first button is theirs — so the star
 * stays on the right *machine*, coming soon or not. Apple Silicon is assumed
 * when WebGL tells us nothing, because that is the common Mac today; the Intel
 * tile sits right next to it, labelled.
 */
function bestChannelId(config, platform, arch) {
  const mine = config.channels.filter((channel) => (channel.platform ?? 'macos') === platform);
  if (mine.length === 0) {
    return '';
  }
  const live = (channel) => safeUrl(channel.url);
  if (platform === 'macos' && arch !== 'unknown') {
    const exact = mine.find((channel) => channel.arch === arch && live(channel))
      || mine.find((channel) => channel.arch === arch);
    if (exact) {
      return exact.id;
    }
  }
  const anyLive = mine.find(live);
  return (anyLive ?? mine[0]).id;
}

function buildItem(channel, config, isBest) {
  // `plannedUrl` is the address the release recipe promises. It is never used
  // as an href: a button only becomes a real download once the owner moves it
  // into `url`, which is the moment the asset actually exists.
  const url = safeUrl(channel.url);
  const fallback = safeUrl(channel.signupUrl || config.signupUrl);
  const href = url || fallback;

  const name = document.createElement('span');
  name.className = 'dl__name';
  name.textContent = t(channel.labelKey);

  const meta = document.createElement('span');
  meta.className = 'dl__meta';
  const notes = [];
  if (url) {
    if (channel.sizeMb) {
      notes.push(`${channel.sizeMb} MB`);
    }
    if (config.version) {
      notes.push(`v${config.version}`);
    }
    if (isBest) {
      notes.push(`★ ${t('gen.best')}`);
    }
  } else {
    const soon = channel.plannedUrl ? `${t('gen.soon')} · ${channel.plannedUrl.split('/download/').pop()}` : t('gen.soon');
    notes.push(fallback ? `${soon} · ${t('gen.notify')}` : soon);
    if (isBest) {
      notes.push(`★ ${t('gen.best')}`);
    }
  }
  meta.textContent = notes.join(' · ');

  const icon = document.createElement('span');
  icon.innerHTML = svgFor(channel.icon ?? 'clock');

  const wrapper = href ? document.createElement('a') : document.createElement('div');
  wrapper.className = 'dl__item';
  if (href) {
    wrapper.href = href;
    if (url) {
      wrapper.setAttribute('download', '');
    }
  } else {
    wrapper.setAttribute('aria-disabled', 'true');
  }
  if (isBest) {
    wrapper.setAttribute('data-best', 'true');
  }
  wrapper.append(icon.firstElementChild ?? icon, name, meta);
  return wrapper;
}

function statusLine(config, platform) {
  if (config._loadFailed) {
    return t('gen.loadError');
  }
  if (platform === 'macos') {
    const version = config.requirements?.macos ?? '14.2';
    return `${t('gen.status.mac')} ${t('gen.req').replace('{version}', version)}`;
  }
  if (platform === 'windows') {
    return t('gen.status.windows');
  }
  return t('gen.status.unknown');
}

export async function initDownloads() {
  const mount = document.querySelector('[data-download-target]');
  if (!mount) {
    return;
  }
  const status = document.getElementById('dl-status');
  const config = await loadConfig();
  const platform = detectPlatform();
  const arch = platform === 'macos' ? detectMacArch() : 'unknown';
  const best = bestChannelId(config, platform, arch);

  const render = () => {
    mount.textContent = '';
    const ordered = [...config.channels].sort((a, b) => Number(b.id === best) - Number(a.id === best));
    for (const channel of ordered) {
      mount.append(buildItem(channel, config, channel.id === best));
    }
    if (status) {
      status.textContent = statusLine(config, platform);
    }
  };

  render();
  onLanguageChange(render);
  return { config, platform, arch, best, lang: currentLanguage() };
}
