# Portfolio Workflow

How photos get from camera to grayhammonphoto.com.

## The pipeline at a glance

```
~/Photos/People/  ~/Photos/Places/  ~/Photos/Things/   (sorted JPGs)
        │
        │   scripts/process-photos.sh
        │   (mirrors folders → R2: adds + removes)
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
Cloudflare Pages → grayhammonphoto.com
```

## Where things live

- **Source photos** — sorted into category subfolders of `./Photos/`:
  `Photos/People/`, `Photos/Places/`, `Photos/Things/` (gitignored; originals
  don't deploy with the site). These folders are the **single source of truth**
  for the site — `process-photos.sh` mirrors them to R2, so a photo not in a
  folder isn't on the site. Which folder it's in decides its tab.
- **Web-ready variants** — `./web-ready/` (also gitignored; regenerable cache)
- **Public CDN** — Cloudflare R2 bucket `grayhammon-photos`, served via
  `photos.grayhammonphoto.com`. Files are stored flat (no category in the
  path), so a photo's URL never changes when it moves between tabs.
- **Category manifest** — `./docs/photo-categories.tsv`, written automatically
  by `process-photos.sh` from your folders. `generate-gallery.sh` reads it to
  decide which tab each photo goes in. You don't normally edit it by hand.
- **Site code** — this repo, deploys via Cloudflare Pages on push to main

## Adding new photos

1. Drop each selected JPG into the folder for its tab:
   `Photos/People/`, `Photos/Places/`, or `Photos/Things/`.
2. Run the processor — resizes, mirrors your folders to R2 (adding new
   photos and removing any you've taken out), and rewrites the category
   manifest:
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

Cloudflare Pages picks up the push and redeploys within a minute or two.

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
./scripts/process-photos.sh        # mirrors folders → R2, rewrites the manifest
./scripts/generate-gallery.sh      # rebuilds the gallery
```

Because R2 stays flat, moving a photo between tabs never changes its public
URL. The `Photos/` folders are the single source of truth: `process-photos.sh`
mirrors them to R2 each run, so a photo you remove from a folder is removed
from the site, and one you leave out was never published. Keep every live
photo's original in its folder (your untouched masters live in the B2 archive).

All photos stay in the page markup regardless of tab — `main.js` just shows
the ones in the active tab — so search engines and link previews still see
every image. With JavaScript disabled, the tab bar is hidden and all photos
show as one gallery. The tabs are also linkable:
`grayhammonphoto.com/#places` opens straight to Places.

## Removing photos from the gallery

Because the `Photos/` folders are the single source of truth, removal is just:
**delete the photo from its folder and re-run the two scripts.**

```bash
rm Photos/People/DSC01234.jpg      # or move it out of the folder
./scripts/process-photos.sh        # syncs the deletion to R2 + prunes the cache
./scripts/generate-gallery.sh      # rebuilds the gallery
git add -A && git commit -m "Remove photo" && git push
```

`process-photos.sh` uses `rclone sync`, so a photo no longer in any folder is
deleted from R2, pruned from `web-ready/`, and dropped from the manifest in one
run — it lists exactly what it's removing before it does. Your untouched master
lives in the B2 archive, so this is always recoverable.

Safety guard: if the source directory is empty (e.g. an external drive didn't
mount), `process-photos.sh` refuses to run rather than sync an empty set and
wipe the site.

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
| Remove a photo from the site | delete it from its `Photos/` folder → `process-photos.sh` → `generate-gallery.sh` |
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
Cloudflare Pages cache. Usually clears within a minute or two; if not,
purge the cache in the Cloudflare dashboard under Caching → Configuration.

**A photo is in the wrong tab, or a tab looks empty**
A photo's tab comes from which `Photos/` folder it's in. Move the original
into the right `People/`, `Places/`, or `Things/` folder, then re-run
`./scripts/process-photos.sh` followed by `./scripts/generate-gallery.sh`.
Since `process-photos.sh` rebuilds the manifest from the folders every run,
the tab follows the folder — no manual manifest editing needed.

**A photo was skipped by `process-photos.sh`**
It's probably sitting loose in `Photos/` instead of inside a `People/`,
`Places/`, or `Things/` subfolder. Move it into one and re-run.

**A photo disappeared from the site unexpectedly**
The folders are the source of truth, so anything missing from them gets removed
on the next `process-photos.sh` run. Common causes: the original was moved or
deleted, or an external drive holding `Photos/` wasn't mounted. Restore the
original to its folder (pull the master from the B2 archive if needed) and
re-run.

**`process-photos.sh` says "no photos found" / "refusing to continue"**
None of `Photos/People`, `Photos/Places`, or `Photos/Things` contained images
— often a drive that didn't mount. This is the safety guard: it refuses to sync
an empty set so it can't wipe the site. Fix the folders and re-run.
