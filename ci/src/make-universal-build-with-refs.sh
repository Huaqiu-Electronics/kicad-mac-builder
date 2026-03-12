#!/bin/bash

set -euxo pipefail

# Build an arm64 version of KiCad, and an x86_64 version of KiCad, combine them, and re-sign them.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

KICAD_MAC_BUILDER_DIR=${SCRIPT_DIR}/../../

"$SCRIPT_DIR"/watermark.sh --both

if [ "$(arch)" != "arm64" ]; then
  echo "Expected 'arch' to return 'arm64'. Are you in a terminal running under Rosetta, maybe?"
  exit 1
fi

if [ -z "${MACOS_MIN_VERSION:-}" ]; then
  MACOS_MIN_VERSION_ARG=""
else
  MACOS_MIN_VERSION_ARG="--macos-min-version ${MACOS_MIN_VERSION}"
fi

echo "Building KiCad with:"
echo "KICAD_REF=${KICAD_REF}"
echo "SYMBOLS_REF=${SYMBOLS_REF}"
echo "FOOTPRINTS_REF=${FOOTPRINTS_REF}"
echo "PACKAGES3D_REF=${PACKAGES3D_REF}"
echo "TEMPLATES_REF=${TEMPLATES_REF}"
echo "RELEASE_NAME=${RELEASE_NAME}"
echo "EXTRA_VERSION=${EXTRA_VERSION}"
echo "DOCS_TARBALL_URL=${DOCS_TARBALL_URL}"
echo "MACOS_MIN_VERSION_ARG=${MACOS_MIN_VERSION_ARG}"
echo "RELEASE_ARG=${RELEASE_ARG}"

ORIG_PATH="$PATH"

# Use absolute paths for build directories
BUILD_DIR="$(pwd)/build"
BUILD_ARM64_DIR="${BUILD_DIR}-arm64"
BUILD_X86_64_DIR="${BUILD_DIR}-x86_64"
BUILD_UNIVERSAL_DIR="${BUILD_DIR}-universal"

rm -rf "$BUILD_ARM64_DIR" "$BUILD_X86_64_DIR" "$BUILD_UNIVERSAL_DIR"

#########################################################
# ARM64 BUILD
#########################################################

echo "Running build.py for arm64..."

export PATH="/opt/homebrew/bin:$ORIG_PATH"

./ci/src/clean-cmake-builds.sh

ARM_PREFIX="$(/opt/homebrew/bin/brew --prefix)"

start_time=$SECONDS

CFLAGS="-I${ARM_PREFIX}/include" \
CXXFLAGS="-I${ARM_PREFIX}/include" \
WX_SKIP_DOXYGEN_VERSION_CHECK=true \
./build.py --arch=arm64 --target package-kicad-unified \
  --kicad-ref $KICAD_REF \
  --symbols-ref $SYMBOLS_REF \
  --footprints-ref $FOOTPRINTS_REF \
  --packages3d-ref $PACKAGES3D_REF \
  --release-name $RELEASE_NAME \
  --docs-tarball-url $DOCS_TARBALL_URL \
  --templates-ref $TEMPLATES_REF \
  $MACOS_MIN_VERSION_ARG $RELEASE_ARG

elapsed=$(( SECONDS - start_time ))
echo "arm64 took $elapsed seconds."

mv build "$BUILD_ARM64_DIR"

# reduce disk usage
rm -rf "$BUILD_ARM64_DIR/_deps" "$BUILD_ARM64_DIR/CMakeFiles" "$BUILD_ARM64_DIR/Testing" || true

#########################################################
# X86 BUILD
#########################################################

echo "Running build.py for x86_64..."

export PATH="/usr/local/bin:$ORIG_PATH"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
export CPATH="/usr/local/include"
export LIBRARY_PATH="/usr/local/lib"

./ci/src/clean-cmake-builds.sh

INTEL_PREFIX="$(/usr/local/bin/brew --prefix)"

start_time=$SECONDS

arch -x86_64 env \
  CFLAGS="-I${INTEL_PREFIX}/include" \
  CXXFLAGS="-I${INTEL_PREFIX}/include" \
  WX_SKIP_DOXYGEN_VERSION_CHECK=true \
  ./build.py --arch=x86_64 --target package-kicad-unified \
    --kicad-ref $KICAD_REF \
    --symbols-ref $SYMBOLS_REF \
    --footprints-ref $FOOTPRINTS_REF \
    --packages3d-ref $PACKAGES3D_REF \
    --release-name $RELEASE_NAME \
    --docs-tarball-url $DOCS_TARBALL_URL \
    --templates-ref $TEMPLATES_REF \
    $MACOS_MIN_VERSION_ARG $RELEASE_ARG

elapsed=$(( SECONDS - start_time ))
echo "x86_64 took $elapsed seconds."

mv build "$BUILD_X86_64_DIR"

#########################################################
# CREATE UNIVERSAL BUNDLE
#########################################################

echo "Combining arm64 and x86_64 KiCad bundles into a Universal KiCad bundle..."

# Use absolute paths to avoid issues
ditto --arch arm64 "$BUILD_ARM64_DIR/kicad-dest" "$BUILD_UNIVERSAL_DIR/thinned-arm64"
ditto --arch x86_64 "$BUILD_X86_64_DIR/kicad-dest" "$BUILD_UNIVERSAL_DIR/thinned-x86_64"
ditto "$BUILD_ARM64_DIR/kicad-dest" "$BUILD_UNIVERSAL_DIR/dest"

cd "$BUILD_UNIVERSAL_DIR/dest"

for app in *.app; do
  cd "$app"

  find . -type f \
    ! -name "*.kicad_mod" \
    ! -name "*.step" \
    ! -name "*.wrl" \
    ! -name "*.kicad_sym" \
    ! -name "*.png" \
    ! -name "*.py" \
    ! -name "*.pyc" \
    ! -name "*.h" \
    ! -name "*.txt" \
    ! -name "*.html" \
    ! -name "*.xml" | while read f; do

    if file "$f" | grep -E 'Mach-O|library' > /dev/null; then

      if [ "$app" == "KiCad.app" ]; then
        layers="../.."
      else
        layers="../../../../.."
      fi

      THIN_X86_64_VERSION="$layers/thinned-x86_64/$app/$f"
      THIN_ARM64_VERSION="$layers/thinned-arm64/$app/$f"

      if echo "$f" | grep python3.9-intel64; then
        continue
      fi

      rm "$f"

      echo "Combining $THIN_X86_64_VERSION and $THIN_ARM64_VERSION..."

      lipo "$THIN_X86_64_VERSION" "$THIN_ARM64_VERSION" \
        -create -output "$f"
    fi

  done

  cd - 
done

cd ../

#########################################################
# SIGN UNIVERSAL BUNDLE
#########################################################

echo "Adhoc-signing Universal bundle..."

"$KICAD_MAC_BUILDER_DIR"/kicad-mac-builder/bin/apple.py sign \
  --certificate-id - \
  --entitlements "${KICAD_MAC_BUILDER_DIR}/kicad-mac-builder/signing/entitlements.plist" \
  "${KICAD_MAC_BUILDER_DIR}/build-universal/dest/KiCad.app"

echo "The adhoc-signed Universal bundles are in build-universal/dest."
echo "Before these could be distributed, they should be signed with an Apple certificate and notarized."


#########################################################
# CREATE UNIVERSAL DMG
#########################################################

echo "Creating universal DMG..."

# Use absolute path for the output DMG
BUILD_DMG_DIR="${BUILD_UNIVERSAL_DIR}/build/dmg"
mkdir -p "$BUILD_DMG_DIR"

DMG_NAME="kicad-unified-${RELEASE_NAME}.dmg"

SRC_APP="${BUILD_UNIVERSAL_DIR}/dest/KiCad.app"

if [ ! -d "$SRC_APP" ]; then
  echo "Error: KiCad.app folder not found in $SRC_APP"
  exit 1
fi

#########################################################
# Copy app to temporary staging directory (CI-safe)
#########################################################

echo "Creating temporary DMG staging directory..."

TMP_DMG_DIR=$(mktemp -d)

echo "Copying KiCad.app to staging directory..."
cp -R "$SRC_APP" "$TMP_DMG_DIR/"

echo "Waiting for filesystem to settle..."
sync
sleep 5

#########################################################
# Clean up possible CI leftovers
#########################################################

echo "Cleaning leftover disk image helpers..."

pkill -f diskimages-helper || true
pkill -f hdiutil || true

#########################################################
# Create DMG from staging folder
#########################################################

echo "Building DMG..."

hdiutil create \
  -volname "KiCad" \
  -srcfolder "$TMP_DMG_DIR" \
  -ov \
  -format UDZO \
  "${BUILD_DMG_DIR}/${DMG_NAME}"

#########################################################
# Cleanup
#########################################################

rm -rf "$TMP_DMG_DIR"

echo "Universal DMG created:"
echo "${BUILD_DMG_DIR}/${DMG_NAME}"