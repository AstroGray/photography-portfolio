#!/bin/bash
set -e

# Config
BASE_URL="${1:-https://photos.grayhammonphoto.com/photos}"
INDEX_FILE="${2:-./index.html}"
BUCKET_PATH="r2:grayhammon-photos/photos"

if [ ! -f "$INDEX_FILE" ]; then
  echo "Error: $INDEX_FILE not found"
  exit 1
fi

echo "Fetching photo list from R2..."
photos=$(rclone ls "$BUCKET_PATH" 2>/dev/null \
  | awk '{print $2}' \
  | grep "_1600\.jpg$" \
  | sed 's/_1600\.jpg$//' \
  | sort)

if [ -z "$photos" ]; then
  echo "Error: no photos found in $BUCKET_PATH"
  exit 1
fi

count=$(echo "$photos" | wc -l | tr -d ' ')
echo "Found $count photos"

# Build the gallery HTML in a temp file
gallery_file=$(mktemp)
for photo in $photos; do
  cat >> "$gallery_file" <<EOF
    <div class="gallery-item">
      <img
        src="${BASE_URL}/${photo}_1600.jpg"
        srcset="${BASE_URL}/${photo}_800.jpg 800w,
                ${BASE_URL}/${photo}_1600.jpg 1600w,
                ${BASE_URL}/${photo}_2400.jpg 2400w"
        sizes="(max-width: 1100px) 100vw, 1100px"
        alt=""
        loading="lazy"
      />
    </div>
EOF
done

# Replace content between markers in index.html using a bash while loop
tmp_file=$(mktemp)
in_block=0
while IFS= read -r line; do
  if [[ "$line" == *"<!-- GALLERY_START -->"* ]]; then
    echo "$line" >> "$tmp_file"
    cat "$gallery_file" >> "$tmp_file"
    in_block=1
    continue
  fi
  if [[ "$line" == *"<!-- GALLERY_END -->"* ]]; then
    echo "$line" >> "$tmp_file"
    in_block=0
    continue
  fi
  if [ "$in_block" -eq 0 ]; then
    echo "$line" >> "$tmp_file"
  fi
done < "$INDEX_FILE"

mv "$tmp_file" "$INDEX_FILE"
rm "$gallery_file"

echo "Updated $INDEX_FILE with $count photos"
echo ""
echo "Next: open index.html in browser to preview, then:"
echo "  git add -A && git commit -m \"Update gallery\" && git push"
