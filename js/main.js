// Menu toggle
const menuToggle = document.querySelector('.menu-toggle');
const navOverlay = document.querySelector('.nav-overlay');
const navClose = document.querySelector('.nav-close');

menuToggle.addEventListener('click', () => {
  navOverlay.classList.add('is-open');
});

navClose.addEventListener('click', () => {
  navOverlay.classList.remove('is-open');
});

// Close menu on link click
document.querySelectorAll('.nav-links a').forEach(link => {
  link.addEventListener('click', () => {
    navOverlay.classList.remove('is-open');
  });
});

// Close menu on Escape key
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    navOverlay.classList.remove('is-open');
  }
});
