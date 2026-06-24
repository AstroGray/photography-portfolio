#!/bin/bash
# process-photos.sh — resize source photos for web, upload to R2, and record
# which tab (People / Places / Things) each photo belongs to.
#
# Photos are sorted purely by which subfolder of the source directory they
# live in:
#
#   Photos/
#   ├── People/   → tab "people"   (portraits)
#   ├── Places/   → tab "places"   (landscapes / location shots)
#   └── Things/   → tab "things"   (everything else)
#
# For each photo this script generates 800/1600/2400px variants (skipping any
# already cached), uploads them to R2 with FLAT names (no category in the
# path, so public image URLs never change), and (re)writes the category
# manifest that generate-gallery.sh reads.
#
# To move a photo to a different tab: move its original between folders and
# re-run this script, then generate-gallery.sh.
#
# Usage:
#   ./scripts/process-photos.sh              # uses ./Photos as source
#   ./scripts/process-photos.sh ./MyShoot    # custom source directory

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
if [ ! -d "$SOURCE_DIR" ]; then
  echo "Error: source directory $SOURCE_DIR does not exist" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "Error: ImageMagick (magick command) not found. Install with: brew install imagemagick" >&2
  exit 1
fi

if ! command -v rclone >/dev/null 2>&1; then
  echo "Error: rclone is not installed or not on PATH" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
: > "$TMPD/seen"
: > "$TMPD/new"
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

if [ "$count" -eq 0 ]; then
  echo "Error: no photos found in $SOURCE_DIR/People, $SOURCE_DIR/Places, or $SOURCE_DIR/Things." >&2
  echo "Create those folders and sort your .jpg files into them." >&2
  exit 1
fi

if [ -s "$TMPD/dups" ]; then
  echo "" >&2
  echo "Warning: these filenames appear in more than one category folder; kept the" >&2
  echo "         first seen (people, then places, then things):" >&2
  sort -u "$TMPD/dups" | while IFS= read -r d; do echo "  - $d" >&2; done
fi

echo ""
echo "Processed $count photos ($new new size variants generated)."
echo ""

# ---- Upload to R2 (flat) ----
echo "Uploading to $R2_REMOTE..."
rclone copy "$WORK_DIR" "$R2_REMOTE" \
  --progress \
  --transfers 8 \
  --checksum

# ---- Update the category manifest ----
# Photos found in folders this run are authoritative. Any photo already in the
# manifest but NOT present locally this run keeps its existing category, so
# cleaning out old originals never loses a tab assignment.
mkdir -p "$(dirname "$MANIFEST")"

if [ -f "$MANIFEST" ]; then
  grep -v '^[[:space:]]*#' "$MANIFEST" | awk 'NF' > "$TMPD/old" || true
else
  : > "$TMPD/old"
fi

awk 'NR==FNR { set[$1]=1; next } !($1 in set)' "$TMPD/new" "$TMPD/old" > "$TMPD/keep"
cat "$TMPD/keep" "$TMPD/new" | sort > "$TMPD/sorted"

{
  cat <<'HDR'
# photo-categories.tsv — which tab each photo appears in (People/Places/Things)
#
# AUTO-GENERATED by scripts/process-photos.sh from the category subfolders of
# ./Photos (People/, Places/, Things/). You don't normally edit this by hand —
# move a photo between those folders and re-run process-photos.sh to change
# its tab. A hand-edit survives the next run only for a photo you no longer
# keep locally.
#
# Format:  <photo-id><TAB><category>   (category = people | places | things)
# Photos that generate-gallery.sh finds in R2 but that aren't listed here
# default to "things".
#
HDR
  cat "$TMPD/sorted"
} > "$MANIFEST"

cat_count=$(wc -l < "$TMPD/sorted" | tr -d ' ')
echo ""
echo "Done. Wrote $cat_count photo categories to $MANIFEST."
echo ""
echo "Next step: ./scripts/generate-gallery.sh"
