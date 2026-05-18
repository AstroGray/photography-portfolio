# Portfolio Workflow

How photos get from camera to grayhammonphoto.com.

## The pipeline at a glance

```
~/Photos (selected JPGs)
        │
        │   scripts/process-photos.sh
        ▼
./web-ready/                                  →   r2:grayhammon-photos/photos/
(local cache of 800/1600/2400px JPGs)             (CDN-fronted public bucket)
        │
        │   scripts/generate-gallery.sh
        ▼
index.html (gallery block regenerated)
        │
        │   git commit && git push
        ▼
Cloudflare Pages → grayhammonphoto.com
```

## Where things live

- **Source photos** — `./Photos/` in this repo (gitignored; the originals don't deploy with the site)
- **Web-ready variants** — `./web-ready/` (also gitignored; regenerable cache)
- **Public CDN** — Cloudflare R2 bucket `grayhammon-photos`, served via `photos.grayhammonphoto.com`
- **Site code** — this repo, deploys via Cloudflare Pages on push to main

## Adding new photos

1. Drop selected JPGs into `./Photos/`
2. Run the processor — generates resized variants and uploads to R2:
   ```bash
   ./scripts/process-photos.sh
   ```
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

`main.js` only handles the nav overlay; it does not render the gallery.

## Common operations

| Task | Command |
|------|---------|
| Add new photos | `process-photos.sh` → `generate-gallery.sh` → commit |
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
