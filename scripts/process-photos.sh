#!/bin/bash
# process-photos.sh — make the live portfolio match your Photos/ folders.
#
# The category subfolders of the source directory are the SINGLE SOURCE OF
# TRUTH for what's on the site:
#
#   Photos/
#   ├── People/   → tab "people"   (portraits)
#   ├── Places/   → tab "places"   (landscapes / location shots)
#   └── Things/   → tab "things"   (everything else)
#
# Each run generates 800/1600/2400px variants for every photo in those folders
# (skipping cached ones), then MIRRORS them to R2 — adding new photos AND
# deleting any photo no longer in a folder — and rewrites the category
# manifest from the folders.
#
#   • To add a photo:    drop it in a folder, re-run.
#   • To remove a photo: delete it from its folder, re-run.
#   • To re-tab a photo: move it between folders, re-run.
#
# Because the folders drive deletions, an empty or unmounted source directory
# is treated as an error — it will NOT wipe the site. Your true originals live
# in the B2 archive regardless.
#
# Usage:
#   ./scripts/process-photos.sh              # uses ./Photos as source
#   ./scripts/process-photos.sh ./MyPhotos   # custom source directory

set -euo pipefail

# ---- Config ----
SOURCE_DIR="${1:-./Photos}"
WORK_DIR="./web-ready"
R2_REMOTE="r2:grayhammon-photos/photos"
MANIFEST="${2:-./docs/photo-categories.tsv}"
CATEGORIES=(people places things)
SIZES=(800 1600 2400)
QUALITY=85

# ---- Validate ----
[ -d "$SOURCE_DIR" ] || { echo "Error: source directory $SOURCE_DIR does not exist" >&2; exit 1; }
command -v magick >/dev/null 2>&1 || { echo "Error: ImageMagick (magick) not found. Install with: brew install imagemagick" >&2; exit 1; }
command -v rclone  >/dev/null 2>&1 || { echo "Error: rclone is not installed or not on PATH" >&2; exit 1; }

mkdir -p "$WORK_DIR"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
: > "$TMPD/seen"
: > "$TMPD/new"     # id <TAB> cat — authoritative set from the folders
: > "$TMPD/dups"

echo "Source:  $SOURCE_DIR"
echo "Output:  $WORK_DIR"
echo "Remote:  $R2_REMOTE"
echo ""

# ---- Find a category folder (case-insensitive, so People/ or people/) ----
find_category_dir() {
  local want="$1" d name lname
  shopt -s nullglob
  for d in "$SOURCE_DIR"/*/; do
    name=$(basename "$d")
    lname=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')
    if [ "$lname" = "$want" ]; then
      printf '%s' "$d"
      return 0
    fi
  done
  return 0
}

# ---- Warn about loose photos sitting directly in the source dir ----
shopt -s nullglob nocaseglob
loose=()
for f in "$SOURCE_DIR"/*.jpg "$SOURCE_DIR"/*.jpeg; do loose+=("$f"); done
shopt -u nullglob nocaseglob
if [ "${#loose[@]}" -gt 0 ]; then
  echo "Warning: these files sit directly in $SOURCE_DIR, not in a People/Places/Things" >&2
  echo "         folder, so they will be SKIPPED. Move them into a category folder:" >&2
  for f in "${loose[@]}"; do echo "  - $(basename "$f")" >&2; done
  echo "" >&2
fi

# ---- Process each category folder ----
count=0
new=0
for cat in "${CATEGORIES[@]}"; do
  dir=$(find_category_dir "$cat")
  [ -z "$dir" ] && continue

  shopt -s nullglob nocaseglob
  for img in "$dir"*.jpg "$dir"*.jpeg; do
    base=$(basename "$img")
    base="${base%.*}"

    if grep -qxF "$base" "$TMPD/seen"; then
      echo "$base" >> "$TMPD/dups"
      continue
    fi
    echo "$base" >> "$TMPD/seen"

    count=$((count + 1))
    echo "[$cat] $base"

    for size in "${SIZES[@]}"; do
      output="$WORK_DIR/${base}_${size}.jpg"
      if [ -f "$output" ]; then
        echo "  ${size}px — exists, skipping"
        continue
      fi
      magick "$img" \
        -resize "${size}x${size}>" \
        -quality "$QUALITY" \
        -strip \
        -interlace Plane \
        -sampling-factor 4:2:0 \
        "$output"
      echo "  ${size}px — generated"
      new=$((new + 1))
    done

    printf '%s\t%s\n' "$base" "$cat" >> "$TMPD/new"
  done
  shopt -u nullglob nocaseglob
done

# ---- Safety: never let an empty/unmounted source wipe the site ----
if [ "$count" -eq 0 ]; then
  echo "Error: no photos found in $SOURCE_DIR/People, $SOURCE_DIR/Places, or $SOURCE_DIR/Things." >&2
  echo "Refusing to continue — syncing an empty source would delete every photo from" >&2
  echo "the site. If that's really what you want, clear the R2 bucket manually." >&2
  exit 1
fi

if [ -s "$TMPD/dups" ]; then
  echo "" >&2
  echo "Warning: these filenames appear in more than one category folder; kept the" >&2
  echo "         first seen (people, then places, then things):" >&2
  sort -u "$TMPD/dups" | while IFS= read -r d; do echo "  - $d" >&2; done
fi

# Authoritative id set from the folders.
cut -f1 "$TMPD/new" | sort -u > "$TMPD/ids"

# ---- Prune the local cache so it matches the folders ----
pruned=0
shopt -s nullglob
for f in "$WORK_DIR"/*_800.jpg "$WORK_DIR"/*_1600.jpg "$WORK_DIR"/*_2400.jpg; do
  bn=$(basename "$f")
  fid="${bn%.*}"; fid="${fid%_800}"; fid="${fid%_1600}"; fid="${fid%_2400}"
  if ! grep -qxF "$fid" "$TMPD/ids"; then
    rm -f "$f"
    pruned=$((pruned + 1))
  fi
done
shopt -u nullglob

# ---- Report photos about to be removed from R2 ----
: > "$TMPD/r2ids"
rclone lsf "$R2_REMOTE" 2>/dev/null \
  | grep -E '_(800|1600|2400)\.jpg$' \
  | sed -E 's/_(800|1600|2400)\.jpg$//' \
  | sort -u > "$TMPD/r2ids" || true

removed=$(comm -23 "$TMPD/r2ids" "$TMPD/ids" || true)
if [ -n "$removed" ]; then
  echo ""
  echo "Removing from the site (no longer in any folder):"
  printf '%s\n' "$removed" | sed 's/^/  - /'
fi

# ---- Mirror the cache to R2 (adds new photos, deletes removed ones) ----
echo ""
echo "Syncing to $R2_REMOTE..."
rclone sync "$WORK_DIR" "$R2_REMOTE" \
  --progress \
  --transfers 8 \
  --checksum

# ---- Rewrite the manifest from the folders ----
sort "$TMPD/new" > "$TMPD/sorted"
{
  cat <<'HDR'
# photo-categories.tsv — which tab each photo appears in (People/Places/Things)
#
# FULLY REGENERATED by scripts/process-photos.sh on every run, from the
# category subfolders of ./Photos (People/, Places/, Things/). Those folders
# are the single source of truth: a photo not in a folder is not on the site.
# Don't hand-edit — changes are overwritten on the next run.
#
# Format:  <photo-id><TAB><category>   (category = people | places | things)
#
HDR
  cat "$TMPD/sorted"
} > "$MANIFEST"

# ---- Summary ----
live=$(wc -l < "$TMPD/ids" | tr -d ' ')
nremoved=$(printf '%s\n' "$removed" | sed '/^$/d' | wc -l | tr -d ' ')
echo ""
echo "Done. $live photos live — $new new variants generated, $pruned cache files pruned, $nremoved removed from R2."
echo ""
echo "Next step: ./scripts/generate-gallery.sh"
