#!/bin/bash

set -euo pipefail

# Required environment variables
: "${KICAD_INSTALL_DIR:?Need KICAD_INSTALL_DIR}"
: "${PACKAGING_DIR:?Need PACKAGING_DIR}"
: "${DMG_DIR:?Need DMG_DIR}"
: "${RELEASE_NAME:?Need RELEASE_NAME}"

MOUNT_NAME="KiCad"
TMP_DMG="temp_kicad.dmg"
FINAL_DMG="kicad-unified-${RELEASE_NAME}.dmg"

WORK_DIR=$(pwd)
STAGING_DIR="$WORK_DIR/dmg-root"

echo "Preparing DMG staging directory..."

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "Copying KiCad apps..."

mkdir -p "$STAGING_DIR/KiCad"
rsync -a "$KICAD_INSTALL_DIR/" "$STAGING_DIR/KiCad/"

if [ -d "$STAGING_DIR/KiCad/demos" ]; then
    mv "$STAGING_DIR/KiCad/demos" "$STAGING_DIR/"
fi

cp "$PACKAGING_DIR/background.png" "$STAGING_DIR/"

echo "Creating writable DMG..."

SIZE=$(du -sh "$STAGING_DIR" | awk '{print $1}')

hdiutil create \
  -volname "$MOUNT_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$TMP_DMG"

echo "Mounting DMG..."

ATTACH_OUTPUT=$(hdiutil attach "$TMP_DMG" -noautoopen)
DEVICE=$(echo "$ATTACH_OUTPUT" | grep "^/dev/" | head -n1 | awk '{print $1}')

echo "Mounted device: $DEVICE"

MOUNT_POINT="/Volumes/$MOUNT_NAME"

sleep 2

echo "Applying Finder background..."

mkdir -p "$MOUNT_POINT/.background"
mv "$MOUNT_POINT/background.png" "$MOUNT_POINT/.background/"

SetFile -a V "$MOUNT_POINT/.background/background.png" || true

sync
sleep 2

echo "Detaching..."

hdiutil detach "$DEVICE"

sleep 2

echo "Compressing DMG..."

hdiutil convert "$TMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG"

rm "$TMP_DMG"

mkdir -p "$DMG_DIR"
mv "$FINAL_DMG" "$DMG_DIR/"

echo ""
echo "✅ DMG created successfully:"
echo "$DMG_DIR/$FINAL_DMG"