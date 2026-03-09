#!/bin/bash

set -euxo pipefail

# Build an arm64 version of KiCad, and an x86_64 version of KiCad, combine them, and re-sign them.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
KICAD_MAC_BUILDER_DIR=${SCRIPT_DIR}/../../

"$SCRIPT_DIR"/watermark.sh --both

if [ "$(arch)" != "arm64" ]; then
  echo "Expected 'arch' to return 'arm64'. Are you in a terminal running under Rosetta?"
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

rm -rf build build-arm64 build-x86_64 build-universal

############################################################
# ARM64 BUILD
############################################################

echo "Running build.py for arm64..."

export PATH="/opt/homebrew/bin:$ORIG_PATH"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig"
export CPATH="/opt/homebrew/include"
export LIBRARY_PATH="/opt/homebrew/lib"

./ci/src/clean-cmake-builds.sh

start_time=$SECONDS

CFLAGS="-I$(/opt/homebrew/bin/brew --prefix)/include" \
CXXFLAGS="-I$(/opt/homebrew/bin/brew --prefix)/include" \
WX_SKIP_DOXYGEN_VERSION_CHECK=true \
./build.py --arch=arm64 --target package-kicad-unified \
--kicad-ref $KICAD_REF --symbols-ref $SYMBOLS_REF --footprints-ref $FOOTPRINTS_REF \
--packages3d-ref $PACKAGES3D_REF --release-name $RELEASE_NAME \
--docs-tarball-url $DOCS_TARBALL_URL --templates-ref $TEMPLATES_REF \
$MACOS_MIN_VERSION_ARG $RELEASE_ARG

elapsed=$(( SECONDS - start_time ))
echo "arm64 took $elapsed seconds."

mv build build-arm64

# Free disk space
rm -rf build-arm64/_deps || true
rm -rf build-arm64/CMakeFiles || true
rm -rf build-arm64/Testing || true

############################################################
# X86_64 BUILD
############################################################

echo "Running build.py for x86_64..."

export PATH="/usr/local/bin:$ORIG_PATH"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
export CPATH="/usr/local/include"
export LIBRARY_PATH="/usr/local/lib"

./ci/src/clean-cmake-builds.sh

start_time=$SECONDS

arch -x86_64 bash -c "
CFLAGS='-I\$(/usr/local/bin/brew --prefix)/include' \
CXXFLAGS='-I\$(/usr/local/bin/brew --prefix)/include' \
WX_SKIP_DOXYGEN_VERSION_CHECK=true \
./build.py --arch=x86_64 --target package-kicad-unified \
--kicad-ref $KICAD_REF --symbols-ref $SYMBOLS_REF --footprints-ref $FOOTPRINTS_REF \
--packages3d-ref $PACKAGES3D_REF --release-name $RELEASE_NAME \
--docs-tarball-url $DOCS_TARBALL_URL --templates-ref $TEMPLATES_REF \
$MACOS_MIN_VERSION_ARG $RELEASE_ARG
"

elapsed=$(( SECONDS - start_time ))
echo "x86_64 took $elapsed seconds."

mv build build-x86_64

# Free disk space
rm -rf build-x86_64/_deps || true
rm -rf build-x86_64/CMakeFiles || true
rm -rf build-x86_64/Testing || true

############################################################
# CREATE UNIVERSAL APP
############################################################

echo "Combining arm64 and x86_64 KiCad bundles into a Universal KiCad bundle..."

ditto --arch arm64 build-arm64/kicad-dest build-universal/thinned-arm64
ditto --arch x86_64 build-x86_64/kicad-dest build-universal/thinned-x86_64
ditto build-arm64/kicad-dest build-universal/dest

cd build-universal/dest

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
    ! -name "*.xml" \
    -print0 | while IFS= read -r -d '' f; do

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
      lipo "$THIN_X86_64_VERSION" "$THIN_ARM64_VERSION" -create -output "$f"
    fi
  done

  cd -
done

cd ../

############################################################
# SIGN
############################################################

echo "Adhoc-signing Universal bundle..."

"$KICAD_MAC_BUILDER_DIR"/kicad-mac-builder/bin/apple.py sign \
--certificate-id - \
--entitlements "${KICAD_MAC_BUILDER_DIR}/kicad-mac-builder/signing/entitlements.plist" \
"${KICAD_MAC_BUILDER_DIR}/build-universal/dest/KiCad.app"

echo "The adhoc-signed Universal bundles are in build-universal/dest."
echo "Before distribution they must be signed with an Apple certificate and notarized."