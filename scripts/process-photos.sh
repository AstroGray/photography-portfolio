#!/bin/bash
# process-photos.sh — resize source photos for web and upload to R2
#
# Reads .jpg/.jpeg files from a source directory, generates 800/1600/2400px
# variants (skipping any that already exist), then uploads everything to
# the R2 portfolio bucket.
#
# Usage:
#   ./scripts/process-photos.sh              # uses ./Photos as source
#   ./scripts/process-photos.sh ./MyShoot    # custom source directory

set -euo pipefail

# ---- Config ----
SOURCE_DIR="${1:-./Photos}"
WORK_DIR="./web-ready"
R2_REMOTE="r2:grayhammon-photos/photos"
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

echo "Source:  $SOURCE_DIR"
echo "Output:  $WORK_DIR"
echo "Remote:  $R2_REMOTE"
echo ""

# ---- Process each photo ----
shopt -s nullglob nocaseglob
count=0
new=0
for img in "$SOURCE_DIR"/*.jpg "$SOURCE_DIR"/*.jpeg; do
  base=$(basename "$img")
  base="${base%.*}"
  count=$((count + 1))

  echo "[$count] $base"

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
done
shopt -u nullglob nocaseglob

if [ "$count" -eq 0 ]; then
  echo "No .jpg/.jpeg files found in $SOURCE_DIR" >&2
  exit 1
fi

echo ""
echo "Processed $count photos ($new new size variants generated)."
echo ""

# ---- Upload to R2 ----
echo "Uploading to $R2_REMOTE..."
rclone copy "$WORK_DIR" "$R2_REMOTE" \
  --progress \
  --transfers 8 \
  --checksum

echo ""
echo "Done."
echo ""
echo "Next step: ./scripts/generate-gallery.sh"
