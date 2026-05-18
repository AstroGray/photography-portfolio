// main.js — UI behavior for grayhammonphoto.com
// The gallery itself is rendered server-side by scripts/generate-gallery.sh,
// which writes HTML between <!-- GALLERY_START --> and <!-- GALLERY_END -->
// in index.html. This file only handles the nav overlay.

const menuToggle = document.querySelector('.menu-toggle');
const navOverlay = document.querySelector('.nav-overlay');
const navClose = document.querySelector('.nav-close');

if (menuToggle && navOverlay && navClose) {
  menuToggle.addEventListener('click', () => {
    navOverlay.classList.add('is-open');
  });

  navClose.addEventListener('click', () => {
    navOverlay.classList.remove('is-open');
  });

  document.querySelectorAll('.nav-links a').forEach(link => {
    link.addEventListener('click', () => {
      navOverlay.classList.remove('is-open');
    });
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      navOverlay.classList.remove('is-open');
    }
  });
}
