#!/bin/bash
# generate-gallery.sh — rebuild the gallery section of index.html
#
# Pulls the list of photos from the R2 bucket, then rewrites the block
# between <!-- GALLERY_START --> and <!-- GALLERY_END --> in index.html
# with a fresh set of responsive <img> tags.
#
# Usage:
#   ./scripts/generate-gallery.sh
#   ./scripts/generate-gallery.sh "https://custom.cdn.url" ./path/to/index.html

set -euo pipefail

# ---- Config ----
BASE_URL="${1:-https://photos.grayhammonphoto.com/photos}"
INDEX_FILE="${2:-./index.html}"
BUCKET_PATH="r2:grayhammon-photos/photos"

# ---- Validate ----
if [ ! -f "$INDEX_FILE" ]; then
  echo "Error: $INDEX_FILE not found" >&2
  exit 1
fi

if ! command -v rclone >/dev/null 2>&1; then
  echo "Error: rclone is not installed or not on PATH" >&2
  exit 1
fi

# ---- Fetch photo list from R2 ----
echo "Fetching photo list from $BUCKET_PATH..."
photos=$(rclone ls "$BUCKET_PATH" 2>/dev/null \
  | awk '{print $2}' \
  | grep "_1600\.jpg$" \
  | sed 's/_1600\.jpg$//' \
  | sort)

if [ -z "$photos" ]; then
  echo "Error: no photos found in $BUCKET_PATH" >&2
  echo "Expected files like DSCxxxxx_1600.jpg" >&2
  exit 1
fi

count=$(echo "$photos" | wc -l | tr -d ' ')
echo "Found $count photos"

# ---- Build the gallery HTML ----
# IMPORTANT: srcset is a SINGLE attribute. Its value is one string
# containing comma-separated entries. The closing quote must come
# AFTER the last entry, not in the middle.
gallery_file=$(mktemp)
trap 'rm -f "$gallery_file"' EXIT

while IFS= read -r photo; do
  [ -z "$photo" ] && continue
  cat >> "$gallery_file" <<EOF
    <div class="gallery-item">
      <img
        src="${BASE_URL}/${photo}_1600.jpg"
        srcset="${BASE_URL}/${photo}_800.jpg 800w, ${BASE_URL}/${photo}_1600.jpg 1600w, ${BASE_URL}/${photo}_2400.jpg 2400w"
        sizes="(max-width: 1100px) 100vw, 1100px"
        alt=""
        loading="lazy"
      />
    </div>
EOF
done <<< "$photos"

# ---- Splice into index.html between markers ----
tmp_file=$(mktemp)
trap 'rm -f "$gallery_file" "$tmp_file"' EXIT

in_block=0
found_start=0
found_end=0

while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" == *"<!-- GALLERY_START -->"* ]]; then
    echo "$line" >> "$tmp_file"
    cat "$gallery_file" >> "$tmp_file"
    in_block=1
    found_start=1
    continue
  fi
  if [[ "$line" == *"<!-- GALLERY_END -->"* ]]; then
    echo "$line" >> "$tmp_file"
    in_block=0
    found_end=1
    continue
  fi
  if [ "$in_block" -eq 0 ]; then
    echo "$line" >> "$tmp_file"
  fi
done < "$INDEX_FILE"

if [ "$found_start" -eq 0 ] || [ "$found_end" -eq 0 ]; then
  echo "Error: $INDEX_FILE is missing <!-- GALLERY_START --> or <!-- GALLERY_END --> markers" >&2
  exit 1
fi

mv "$tmp_file" "$INDEX_FILE"

echo ""
echo "Updated $INDEX_FILE with $count photos."
echo ""
echo "Next steps:"
echo "  1. Open $INDEX_FILE in a browser to preview"
echo "  2. git diff   (sanity-check the changes)"
echo "  3. git add -A && git commit -m 'Update gallery' && git push"
