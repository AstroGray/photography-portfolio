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

// ---- Gallery tabs (People / Places / Things) ----
// All photos are present in the HTML; this only filters which are shown.
// Works as an enhancement: with JS off, the tab bar is hidden via CSS and
// every photo displays as one continuous gallery.
const galleryTabs = document.querySelectorAll('.gallery-tab');
const galleryItems = document.querySelectorAll('.gallery-item');
const galleryEmpty = document.querySelector('.gallery-empty');

if (galleryTabs.length && galleryItems.length) {
  const categories = ['people', 'places', 'things'];

  const showCategory = (category) => {
    let visibleCount = 0;

    galleryItems.forEach((item) => {
      const match = item.dataset.category === category;
      item.classList.toggle('is-visible', match);
      if (match) visibleCount += 1;
    });

    galleryTabs.forEach((tab) => {
      const active = tab.dataset.filter === category;
      tab.classList.toggle('is-active', active);
      tab.setAttribute('aria-pressed', active ? 'true' : 'false');
    });

    if (galleryEmpty) {
      galleryEmpty.classList.toggle('is-shown', visibleCount === 0);
    }
  };

  const categoryFromHash = () => {
    const hash = window.location.hash.replace('#', '');
    return categories.includes(hash) ? hash : 'people';
  };

  galleryTabs.forEach((tab) => {
    tab.addEventListener('click', () => {
      const category = tab.dataset.filter;
      showCategory(category);
      // Reflect the active tab in the URL so it can be shared / bookmarked.
      history.replaceState(null, '', '#' + category);
    });
  });

  // Respond to back/forward navigation and shared links like /#places.
  window.addEventListener('hashchange', () => showCategory(categoryFromHash()));

  // Initial state: honor the URL hash, otherwise land on People.
  showCategory(categoryFromHash());
}
