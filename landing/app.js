import { initI18n } from './lib/i18n.js';
import { initDownloads } from './lib/downloads.js';

/* Entry point: language, download buttons, scroll reveal.
 * The <html> element already got the `js` class from an inline script, so a page
 * whose module never loads still shows every section (see base.css). */

initI18n();
initDownloads();

const revealables = document.querySelectorAll('.reveal');

if ('IntersectionObserver' in window && revealables.length > 0) {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-in');
          observer.unobserve(entry.target);
        }
      }
    },
    { rootMargin: '0px 0px -8% 0px', threshold: 0.08 }
  );
  revealables.forEach((node) => observer.observe(node));
} else {
  revealables.forEach((node) => node.classList.add('is-in'));
}

/* The yellow highlighter stroke draws itself when the heading reaches the page. */
const highlights = document.querySelectorAll('.hl');
if (highlights.length > 0 && 'IntersectionObserver' in window) {
  const stroke = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-in');
          stroke.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.5 }
  );
  highlights.forEach((node) => stroke.observe(node));
} else {
  highlights.forEach((node) => node.classList.add('is-in'));
}
