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
BASE_URL="${1:-https://photos.grayconnerphoto.com/photos}"
INDEX_FILE="${2:-./index.html}"
BUCKET_PATH="r2:grayhammon-photos/photos"
MANIFEST="${3:-./docs/photo-categories.tsv}"
VALID_CATEGORIES="people places things"
DEFAULT_CATEGORY="things"

# ---- Validate ----
if [ ! -f "$INDEX_FILE" ]; then
  echo "Error: $INDEX_FILE not found" >&2
  exit 1
fi

if ! command -v rclone >/dev/null 2>&1; then
  echo "Error: rclone is not installed or not on PATH" >&2
  exit 1
fi

# ---- Category manifest ----
# Maps each photo id to a tab (people | places | things). Missing or
# unlisted photos fall back to DEFAULT_CATEGORY and are reported at the end.
if [ ! -f "$MANIFEST" ]; then
  echo "Warning: manifest $MANIFEST not found — every photo will default to '$DEFAULT_CATEGORY'." >&2
fi

# lookup_category <photo-id> -> echoes the category for that photo.
# Falls back to DEFAULT_CATEGORY for unlisted ids or invalid category values.
lookup_category() {
  local id="$1" cat=""
  if [ -f "$MANIFEST" ]; then
    # First non-comment line whose first field matches the id exactly.
    cat=$(awk -v id="$id" '
      /^[[:space:]]*#/ { next }
      $1 == id { print $2; exit }
    ' "$MANIFEST")
  fi
  case " $VALID_CATEGORIES " in
    *" $cat "*) echo "$cat" ;;
    *)          echo "$DEFAULT_CATEGORY" ;;
  esac
}

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

uncategorized=""

while IFS= read -r photo; do
  [ -z "$photo" ] && continue
  category=$(lookup_category "$photo")

  # Track photos that aren't explicitly listed in the manifest.
  if [ -f "$MANIFEST" ] && ! awk -v id="$photo" '
        /^[[:space:]]*#/ { next }
        $1 == id { found=1 } END { exit !found }
      ' "$MANIFEST"; then
    uncategorized="${uncategorized}  - ${photo} (using '${category}')"$'\n'
  fi

  cat >> "$gallery_file" <<EOF
    <div class="gallery-item" data-category="${category}">
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

if [ -n "$uncategorized" ]; then
  echo ""
  echo "Note: these photos aren't in $MANIFEST yet, so they went to '$DEFAULT_CATEGORY':"
  printf '%s' "$uncategorized"
  echo "Add them to the manifest and re-run to place them in People/Places."
fi

echo ""
echo "Next steps:"
echo "  1. Open $INDEX_FILE in a browser to preview"
echo "  2. git diff   (sanity-check the changes)"
echo "  3. git add -A && git commit -m 'Update gallery' && git push"
