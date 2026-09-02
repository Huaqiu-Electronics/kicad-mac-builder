#!/bin/bash

set -euxo pipefail

# Build an architecture-specific KiCad DMG (no universal binary, no lipo).
#
# Usage: ./ci/src/make-build-with-refs.sh --arch arm64|x86_64
#
# This is the split-packaging build script (docs/split-packaging.md). It
# replaces the old make-universal-build-with-refs.sh for CI. Each invocation
# builds exactly ONE architecture and produces a standalone DMG via the
# package-kicad-unified CMake target. There is no lipo step and no universal
# bundle.
#
# The DMG is created by bin/package.sh and lands in build/dmg/. package.sh
# names it kicad-unified-${RELEASE_NAME}.dmg for PACKAGE_TYPE=unified; the
# caller (CI workflow) renames it to kicad-${RELEASE_NAME}.dmg so the release
# asset matches docs/split-packaging.md section 7 (no "unified" in the name).
#
# Environment variables (same as make-universal-build-with-refs.sh):
#   KICAD_REF, SYMBOLS_REF, FOOTPRINTS_REF, PACKAGES3D_REF, TEMPLATES_REF,
#   RELEASE_NAME, EXTRA_VERSION, DOCS_TARBALL_URL, RELEASE_ARG,
#   MACOS_MIN_VERSION (optional)
#
# Both arm64 and x86_64 builds run on an Apple Silicon host (macos-14 runner).
# The x86_64 build uses Rosetta 2 via `arch -x86_64` and the /usr/local
# Homebrew installation, exactly like the bootstrap script and the old
# universal build script's x86_64 section.

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
KICAD_MAC_BUILDER_DIR=${SCRIPT_DIR}/../../

source "${SCRIPT_DIR}/brew_deps.sh"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

ARCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --arch)
      ARCH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 --arch arm64|x86_64"
      exit 1
      ;;
  esac
done

if [ -z "${ARCH}" ]; then
  echo "ERROR: --arch is required (arm64 or x86_64)"
  echo "Usage: $0 --arch arm64|x86_64"
  exit 1
fi

if [ "${ARCH}" != "arm64" ] && [ "${ARCH}" != "x86_64" ]; then
  echo "ERROR: --arch must be 'arm64' or 'x86_64', got: '${ARCH}'"
  exit 1
fi

# ---------------------------------------------------------------------------
# Verify Apple Silicon host (both arch builds run on Apple Silicon runners)
# ---------------------------------------------------------------------------

if [ "$(arch)" != "arm64" ]; then
  echo "ERROR: expected 'arch' to return 'arm64' (Apple Silicon host)."
  echo "       Are you in a terminal running under Rosetta?"
  exit 1
fi

# ---------------------------------------------------------------------------
# Architecture identification (docs/split-packaging.md section 14)
# ---------------------------------------------------------------------------

echo "============================================================"
echo "Building KiCad for ${ARCH}"
echo "============================================================"

echo "Host architecture:"
echo "  uname -m: $(uname -m)"
echo "  arch:     $(arch)"
echo "  Building ${ARCH}"

# ---------------------------------------------------------------------------
# Verify only THIS architecture's Homebrew dependencies (not --both).
# The split packaging does not compare arm64 vs x86_64 versions in one job;
# each job verifies only its own Homebrew installation.
#
# watermark.sh (without --both) calls plain `brew`, which resolves to the
# first brew on PATH. For arm64, /opt/homebrew/bin/brew is native and works
# directly. For x86_64, the x86_64 Homebrew at /usr/local/bin/brew must be
# queried through `arch -x86_64` (the bootstrap script always uses that
# prefix), so we cannot rely on plain `brew` resolving to it correctly.
# Instead we do a direct, explicit dependency check per architecture.
# ---------------------------------------------------------------------------

ORIG_PATH="$PATH"

# The brew command (as an array to avoid eval) used to query installed
# dependencies for this architecture.
if [ "${ARCH}" = "arm64" ]; then
  export PATH="/opt/homebrew/bin:${ORIG_PATH}"
  VERIFY_BREW=(brew)
else
  export PATH="/usr/local/bin:${ORIG_PATH}"
  VERIFY_BREW=(arch -x86_64 /usr/local/bin/brew)
fi

echo "Verifying ${ARCH} Homebrew dependencies..."
ISSUES=""
for dep in "${BREW_DEPS[@]}"; do
  version="$("${VERIFY_BREW[@]}" list --versions "${dep}" 2>/dev/null || true)"
  # Homebrew alias fallback: "openssl" is an alias pointing to "openssl@3".
  # brew list --versions <alias> can behave differently across brew versions,
  # so retry with the concrete formula name if the alias lookup returned
  # nothing.
  if [ -z "${version}" ] && [ "${dep}" = "openssl" ]; then
    version="$("${VERIFY_BREW[@]}" list --versions "openssl@3" 2>/dev/null || true)"
  fi
  if [ -z "${version}" ]; then
    echo "  MISSING: ${dep}"
    ISSUES="${ISSUES}${dep} not installed in ${ARCH} Homebrew\n"
  else
    echo "  ${version}"
  fi
done

if [ -n "${ISSUES}" ]; then
  echo "Dependency issues detected for ${ARCH}:"
  printf '%b' "${ISSUES}"
  exit 1
fi
echo "${ARCH} dependencies OK."

# ---------------------------------------------------------------------------
# Build configuration
# ---------------------------------------------------------------------------

if [ -z "${MACOS_MIN_VERSION:-}" ]; then
  MACOS_MIN_VERSION_ARG=""
else
  MACOS_MIN_VERSION_ARG="--macos-min-version ${MACOS_MIN_VERSION}"
fi

echo "Building KiCad with:"
echo "  ARCH=${ARCH}"
echo "  KICAD_REF=${KICAD_REF}"
echo "  SYMBOLS_REF=${SYMBOLS_REF}"
echo "  FOOTPRINTS_REF=${FOOTPRINTS_REF}"
echo "  PACKAGES3D_REF=${PACKAGES3D_REF}"
echo "  TEMPLATES_REF=${TEMPLATES_REF}"
echo "  RELEASE_NAME=${RELEASE_NAME}"
echo "  EXTRA_VERSION=${EXTRA_VERSION:-}"
echo "  DOCS_TARBALL_URL=${DOCS_TARBALL_URL}"
echo "  MACOS_MIN_VERSION_ARG=${MACOS_MIN_VERSION_ARG}"
echo "  RELEASE_ARG=${RELEASE_ARG}"

# Use absolute path for the build directory.
BUILD_DIR="$(pwd)/build"
rm -rf "${BUILD_DIR}"

# Clean any stale CMake build state from a previous attempt.
"${SCRIPT_DIR}"/clean-cmake-builds.sh

start_time=$SECONDS

# ---------------------------------------------------------------------------
# ARM64 build
# ---------------------------------------------------------------------------
if [ "${ARCH}" = "arm64" ]; then

  echo "Running build.py for arm64..."
  export PATH="/opt/homebrew/bin:${ORIG_PATH}"

  ARM_PREFIX="$(/opt/homebrew/bin/brew --prefix)"

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

# ---------------------------------------------------------------------------
# x86_64 build (under Rosetta 2, /usr/local Homebrew)
# ---------------------------------------------------------------------------
elif [ "${ARCH}" = "x86_64" ]; then

  echo "Running build.py for x86_64..."
  export PATH="/usr/local/bin:${ORIG_PATH}"
  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
  export CPATH="/usr/local/include"
  export LIBRARY_PATH="/usr/local/lib"

  INTEL_PREFIX="$(/usr/local/bin/brew --prefix)"

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

fi

elapsed=$(( SECONDS - start_time ))
echo "${ARCH} build took ${elapsed} seconds."

# ---------------------------------------------------------------------------
# Verify the produced binary architecture (docs/split-packaging.md section 14)
# ---------------------------------------------------------------------------
echo "============================================================"
echo "Verifying ${ARCH} build output"
echo "============================================================"

# The kicad target installs KiCad.app into build/kicad-dest before the
# package-kicad-unified target copies it into the DMG template. Inspect the
# installed binary if it is still present.
KICAD_APP="$(find "${BUILD_DIR}/kicad-dest" -maxdepth 2 -name "KiCad.app" 2>/dev/null | head -n1 || true)"
if [ -n "${KICAD_APP}" ]; then
  KICAD_BIN="${KICAD_APP}/Contents/MacOS/kicad"
  if [ -f "${KICAD_BIN}" ]; then
    echo "file output for ${KICAD_BIN}:"
    file "${KICAD_BIN}"
  fi
else
  echo "Note: KiCad.app not found in kicad-dest (already moved into DMG)."
fi

echo ""
echo "DMG files produced:"
find "${BUILD_DIR}" -name "*.dmg" -print || true

echo ""
echo "${ARCH} build complete."
