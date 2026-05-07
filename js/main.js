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

// Gallery: all photos, shuffled on each load
const photos = [
  'DSC00475.jpg', 'DSC00490.jpg', 'DSC00603.jpg', 'DSC00952.jpg',
  'DSC00959.jpg', 'DSC00969.jpg', 'DSC00977.jpg', 'DSC00984.jpg',
  'DSC01030.jpg', 'DSC01122.jpg', 'DSC01127.jpg', 'DSC01136.jpg',
  'DSC01137.jpg', 'DSC01148.jpg', 'DSC01187.jpg', 'DSC01188.jpg',
  'DSC01204.jpg', 'DSC01260.jpg', 'DSC01289.jpg', 'DSC01821.jpg',
  'DSC01829.jpg', 'DSC02010.jpg', 'DSC02079.jpg', 'DSC02135.jpg',
  'DSC02179.jpg', 'DSC02242.jpg', 'DSC02248.jpg', 'DSC02301.jpg',
  'DSC02526.jpg', 'DSC02529.jpg', 'DSC04069.jpg', 'DSC04073.jpg',
  'DSC04160.jpg', 'DSC04370.jpg', 'DSC04435.jpg', 'DSC04707.jpg',
  'DSC04732.jpg'
];

function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

const rowPatterns = [2, 1, 2, 3, 2, 1, 3, 2];

function buildGallery() {
  const gallery = document.getElementById('gallery');
  if (!gallery) return;

  const shuffled = shuffle([...photos]);
  let idx = 0;
  let patternIdx = 0;

  while (idx < shuffled.length) {
    const count = rowPatterns[patternIdx % rowPatterns.length];
    const rowPhotos = shuffled.slice(idx, idx + count);
    if (rowPhotos.length === 0) break;

    const rowClass = rowPhotos.length === 1 ? 'gallery-row--1'
      : rowPhotos.length === 3 ? 'gallery-row--3'
      : (patternIdx % 4 === 2) ? 'gallery-row--2-narrow'
      : 'gallery-row--2';

    const row = document.createElement('div');
    row.className = `gallery-row ${rowClass}`;

    rowPhotos.forEach(photo => {
      const item = document.createElement('div');
      item.className = 'gallery-item';
      const img = document.createElement('img');
      img.src = `Photos/${photo}`;
      img.alt = '';
      img.loading = 'lazy';
      item.appendChild(img);
      row.appendChild(item);
    });

    gallery.appendChild(row);
    idx += count;
    patternIdx++;
  }
}

buildGallery();
