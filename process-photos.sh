#!/bin/bash
set -e

# Config
SOURCE_DIR="${1:-./Photos}"
WORK_DIR="./web-ready"
R2_REMOTE="r2:grayhammon-photos/photos"
SIZES=(800 1600 2400)
QUALITY=85

# Setup
mkdir -p "$WORK_DIR"
echo "Processing photos from: $SOURCE_DIR"
echo "Output directory: $WORK_DIR"
echo ""

# Process each photo
count=0
for img in "$SOURCE_DIR"/*.{jpg,JPG,jpeg,JPEG}; do
  [ -f "$img" ] || continue
  
  base=$(basename "$img")
  base="${base%.*}"
  count=$((count + 1))
  
  echo "[$count] Processing: $base"
  
  for size in "${SIZES[@]}"; do
    output="$WORK_DIR/${base}_${size}.jpg"
    
    if [ -f "$output" ]; then
      echo "  ↳ ${size}px exists, skipping"
      continue
    fi
    
    magick "$img" \
      -resize "${size}x${size}>" \
      -quality $QUALITY \
      -strip \
      -interlace Plane \
      -sampling-factor 4:2:0 \
      "$output"
    
    echo "  ↳ ${size}px done"
  done
done

echo ""
echo "Processed $count photos."
echo ""

# Upload to R2
echo "Uploading to R2..."
rclone copy "$WORK_DIR" "$R2_REMOTE" \
  --progress \
  --transfers 8 \
  --checksum

echo ""
echo "Done. Photos uploaded to: $R2_REMOTE"
