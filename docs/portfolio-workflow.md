# Portfolio Workflow

How photos get from camera to grayconnerphoto.com.

## The pipeline at a glance

```
~/Photos/People/  ~/Photos/Places/  ~/Photos/Things/   (sorted JPGs)
        │
        │   scripts/process-photos.sh
        ▼
./web-ready/                  →   r2:grayhammon-photos/photos/   (flat, CDN-fronted)
(800/1600/2400px JPGs)        →   docs/photo-categories.tsv      (tab per photo)
        │
        │   scripts/generate-gallery.sh
        │   (reads docs/photo-categories.tsv for tabs)
        ▼
index.html (gallery block regenerated)
        │
        │   git commit && git push
        ▼
GitHub Pages → grayconnerphoto.com
```

## Where things live

- **Source photos** — sorted into category subfolders of `./Photos/`:
  `Photos/People/`, `Photos/Places/`, `Photos/Things/` (gitignored; originals
  don't deploy with the site). Which folder a photo is in decides its tab.
- **Web-ready variants** — `./web-ready/` (also gitignored; regenerable cache)
- **Public CDN** — Cloudflare R2 bucket `grayhammon-photos`, served via
  `photos.grayconnerphoto.com`. Files are stored flat (no category in the
  path), so a photo's URL never changes when it moves between tabs.
- **Category manifest** — `./docs/photo-categories.tsv`, written automatically
  by `process-photos.sh` from your folders. `generate-gallery.sh` reads it to
  decide which tab each photo goes in. You don't normally edit it by hand.
- **Site code** — this repo, deploys via GitHub Pages on push to main

## Adding new photos

1. Drop each selected JPG into the folder for its tab:
   `Photos/People/`, `Photos/Places/`, or `Photos/Things/`.
2. Run the processor — resizes, uploads to R2, and writes the category
   manifest from your folders:
   ```bash
   ./scripts/process-photos.sh
   ```
   (Files left loose in `Photos/` rather than in a category folder are
   skipped with a warning.)
3. Regenerate the gallery HTML in `index.html`:
   ```bash
   ./scripts/generate-gallery.sh
   ```
4. Sanity check:
   ```bash
   git diff index.html
   open index.html        # preview in browser
   ```
5. Ship it:
   ```bash
   git add -A
   git commit -m "Add new photos to gallery"
   git push
   ```

GitHub Pages picks up the push and redeploys within a minute or two.

## Organizing photos into tabs

The home gallery is split into three tabs — **People** (portraits), **Places**
(landscapes / location shots), and **Things** (everything else). People is the
tab the page lands on.

A photo's tab is decided entirely by **which folder it lives in** under
`./Photos/`:

```
Photos/People/DSC01122.jpg   → People tab
Photos/Places/DSC01030.jpg   → Places tab
Photos/Things/DSC00475.jpg   → Things tab
```

`process-photos.sh` reads those folders and writes `docs/photo-categories.tsv`
for you; `generate-gallery.sh` then reads that file to place each photo. To
**move a photo to a different tab**, drag its original between the folders and
re-run both scripts:

```bash
./scripts/process-photos.sh        # rewrites the manifest from your folders
./scripts/generate-gallery.sh      # rebuilds the gallery
```

Because R2 stays flat, moving a photo between tabs never changes its public
URL. And if you've deleted an old original locally, its tab is preserved from
the existing manifest rather than reset.

All photos stay in the page markup regardless of tab — `main.js` just shows
the ones in the active tab — so search engines and link previews still see
every image. With JavaScript disabled, the tab bar is hidden and all photos
show as one gallery. The tabs are also linkable:
`grayconnerphoto.com/#places` opens straight to Places.

## Removing photos from the gallery

`generate-gallery.sh` rebuilds the gallery from whatever is currently in
R2, so to remove a photo from the site:

1. Delete its three variants from R2:
   ```bash
   rclone delete r2:grayhammon-photos/photos/DSC01234_800.jpg
   rclone delete r2:grayhammon-photos/photos/DSC01234_1600.jpg
   rclone delete r2:grayhammon-photos/photos/DSC01234_2400.jpg
   ```
2. Re-run `./scripts/generate-gallery.sh`
3. Commit and push

## How the responsive images work

Each gallery entry uses `srcset` with three sizes. Browsers pick the right
size based on screen width and pixel density:

- `_800.jpg` — phones, low-bandwidth
- `_1600.jpg` — standard desktop (also the fallback `src=`)
- `_2400.jpg` — retina/4K displays

The `sizes` attribute (`max-width: 1100px ...`) tells the browser the
image's rendered width so it can pick correctly.

## Why the gallery is in HTML, not JavaScript

The gallery markup is baked into `index.html` rather than rendered
client-side. This means:

- Search engines and link previews see the images
- The page works even with JavaScript disabled
- First paint is faster (no waiting for JS to populate the DOM)

`main.js` handles the nav overlay and the gallery tab filtering; it does
not render the gallery itself.

## Common operations

| Task | Command |
|------|---------|
| Add new photos | sort into `Photos/People|Places|Things` → `process-photos.sh` → `generate-gallery.sh` → commit |
| Move a photo to another tab | move it between `Photos/` folders → `process-photos.sh` → `generate-gallery.sh` |
| Rebuild gallery from R2 contents | `./scripts/generate-gallery.sh` |
| List photos currently in R2 | `rclone ls r2:grayhammon-photos/photos` |
| Check what's in `web-ready/` | `ls -la web-ready/` |
| Clear local cache | `rm -rf web-ready/` |

## Troubleshooting

**Gallery HTML looks wrong after `generate-gallery.sh`**
Check that `index.html` still has `<!-- GALLERY_START -->` and
`<!-- GALLERY_END -->` markers. The script needs both to splice the new
content in.

**`process-photos.sh` says "magick: command not found"**
Install ImageMagick: `brew install imagemagick`

**`rclone` upload failing**
Check that the `r2` remote is configured: `rclone listremotes` should
show `r2:`. If not, reconfigure with `rclone config`.

**Site shows old photos after push**
GitHub Pages cache. Usually clears within a minute or two; if not,
purge the cache in the Cloudflare dashboard under Caching → Configuration.

**A photo is in the wrong tab, or a tab looks empty**
A photo's tab comes from which `Photos/` folder it's in. Move the original
into the right `People/`, `Places/`, or `Things/` folder, then re-run
`./scripts/process-photos.sh` followed by `./scripts/generate-gallery.sh`.
If `generate-gallery.sh` printed a "not in the manifest yet" note, those
photos exist in R2 but no longer have a local original in any folder — they
default to `things`; either re-add an original and re-process, or hand-edit
`docs/photo-categories.tsv` for that id.

**A photo was skipped by `process-photos.sh`**
It's probably sitting loose in `Photos/` instead of inside a `People/`,
`Places/`, or `Things/` subfolder. Move it into one and re-run.
