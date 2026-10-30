#!/bin/zsh

# ---------------------------------------------------------------------------
# release-local.sh — build the arm64 macOS KiCad installer WITHOUT GitHub.
#
# Why this exists: GitHub is not stable in this environment, so the two inputs
# that used to come from GitHub are now supplied from local disk:
#   * KiCad source   -> /Users/admin/code/kicad  (used as-is, no clone)
#   * edge-headless  -> /Users/admin/code/hq-edge/dist/edge-headless-darwin-arm64.zip
#
# The remaining library repos (symbols / footprints / packages3D / templates)
# and the docs tarball still come from gitlab.com (gitlab is reachable), pinned
# to a release tag so nothing floats.  Only arm64 is produced.
#
# This mirrors what .github/workflows/kicad-package.yml + release.sh do, but
# through build.py with --kicad-source-dir (a source-dir build cannot be a
# `--release` build, so --build-type Release is used instead).
#
# Usage:
#   ./release-local.sh [TAG] [--dry-run] [--clean] [--zip <path>] \
#       [--source <path>] [--lib-ref <ref>] [--target <target>]
#
#   TAG      Version used in the DMG/release name (default: nearest tag of the
#            local KiCad source, e.g. "10.0.7").  Library repos + docs are
#            pinned to this tag too.
#   --dry-run  Only print the build.py invocation, don't build.
#   --clean    Remove the staged kicad build output first (like release.sh).
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# --- defaults -------------------------------------------------------------
KICAD_SOURCE_DIR="${KICAD_SOURCE_DIR:-/Users/admin/code/kicad}"
LIBRARIES_DIR="${LIBRARIES_DIR:-/Users/admin/code/kicad-libraries}"
EDGE_HEADLESS_ZIP="${EDGE_HEADLESS_ZIP:-/Users/admin/code/hq-edge/dist/edge-headless-darwin-arm64.zip}"
ARCH="arm64"                       # scope: arm64 only
TARGET="${TARGET:-package-kicad-unified}"
EXTRA_VERSION="${EXTRA_VERSION:--huaqiu}"
LIB_REF="${LIB_REF:-}"             # gitlab fallback ref (ignored when local libs are used)
TAG="${TAG:-}"

DRY_RUN=0
CLEAN=0

# --- parse args: first non-option arg is TAG, the rest are flags ----------
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --clean)   CLEAN=1;  shift ;;
        --zip)     EDGE_HEADLESS_ZIP="$2"; shift 2 ;;
        --source)  KICAD_SOURCE_DIR="$2"; shift 2 ;;
        --lib-dir) LIBRARIES_DIR="$2"; shift 2 ;;
        --lib-ref) LIB_REF="$2"; shift 2 ;;
        --target)  TARGET="$2"; shift 2 ;;
        --extra-version) EXTRA_VERSION="$2"; shift 2 ;;
        --*)
            echo "ERROR: unknown option: $1" >&2; exit 1 ;;
        *)
            if [[ -z "$TAG" ]]; then
                TAG="$1"
            else
                echo "ERROR: unexpected extra argument: $1" >&2; exit 1
            fi
            shift ;;
    esac
done

# --- only arm64 -----------------------------------------------------------
if [[ "$ARCH" != "arm64" ]]; then
    echo "ERROR: only arm64 is supported by this script (got '$ARCH')." >&2
    exit 1
fi

# --- validate inputs ------------------------------------------------------
if [[ ! -d "$KICAD_SOURCE_DIR" ]]; then
    echo "ERROR: KiCad source dir not found: $KICAD_SOURCE_DIR" >&2
    exit 1
fi
if [[ ! -f "$EDGE_HEADLESS_ZIP" ]]; then
    echo "ERROR: edge-headless zip not found: $EDGE_HEADLESS_ZIP" >&2
    exit 1
fi

# --- local KiCad library checkouts (used offline instead of gitlab) ----------
# Layout of LIBRARIES_DIR must match the repo names exactly.
LIB_MAP=( "symbols|kicad-symbols"
          "footprints|kicad-footprints"
          "packages3d|kicad-packages3D"
          "templates|kicad-templates" )
declare -A LIB_SOURCE_DIR
for pair in "${LIB_MAP[@]}"; do
    key="${pair%%|*}"
    name="${pair##*|}"
    LIB_SOURCE_DIR[$key]="$LIBRARIES_DIR/$name"
    if [[ ! -d "${LIB_SOURCE_DIR[$key]}" ]]; then
        echo "ERROR: local library checkout not found: ${LIB_SOURCE_DIR[$key]}" >&2
        echo "       (put the four KiCad library clones under $LIBRARIES_DIR, or pass --lib-dir)" >&2
        exit 1
    fi
done

# --- derive TAG from local KiCad source if not given ----------------------
if [[ -z "$TAG" ]]; then
    TAG="$(git -C "$KICAD_SOURCE_DIR" describe --tags --abbrev=0 2>/dev/null \
        || true)"
    if [[ -z "$TAG" ]]; then
        echo "ERROR: cannot derive TAG from $KICAD_SOURCE_DIR; pass it as \$1." >&2
        exit 1
    fi
fi
[[ -z "$LIB_REF" ]] && LIB_REF="$TAG"

RELEASE_NAME="huaqiu-${TAG}-macos-${ARCH}"

# --- native arm64 Homebrew ------------------------------------------------
BREW_BIN=""
if [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_BIN=/opt/homebrew/bin/brew
elif command -v brew >/dev/null 2>&1; then
    BREW_BIN="$(command -v brew)"
else
    echo "ERROR: Homebrew not found; required to build KiCad on macOS." >&2
    exit 1
fi
BREW_PREFIX="$($BREW_BIN --prefix 2>/dev/null)"

# --- edge-headless version + SHA256 from the local zip ---------------------
EDGE_HEADLESS_SHA256="$(shasum -a 256 "$EDGE_HEADLESS_ZIP" | awk '{print $1}')"

# Pull HQ_EDGE_VERSION=... out of edge-headless/VERSION inside the zip.
EDGE_HEADLESS_VERSION=""
EXTRACT_TMP="$(mktemp -d)"
if unzip -o -q "$EDGE_HEADLESS_ZIP" 'edge-headless/VERSION' -d "$EXTRACT_TMP" 2>/dev/null; then
    EDGE_HEADLESS_VERSION="$(
        sed -n 's/^[[:space:]]*HQ_EDGE_VERSION=[[:space:]]*//p' \
            "$EXTRACT_TMP/edge-headless/VERSION" 2>/dev/null | tr -d '[:space:]'
    )"
fi
rm -rf "$EXTRACT_TMP"
if [[ -z "$EDGE_HEADLESS_VERSION" ]]; then
    echo "ERROR: could not read HQ_EDGE_VERSION from $EDGE_HEADLESS_ZIP." >&2
    exit 1
fi

# Docs are intentionally skipped for this distribution (--skip-docs => -DKMB_ENABLE_DOCS=OFF).

# --- tool checks ----------------------------------------------------------
for tool in cmake make lipo shasum; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required tool not found: $tool" >&2; exit 1; }
done

echo "===================================================================="
echo " Local KiCad packaging (offline: local source + local libraries)"
echo "  arch             : $ARCH"
echo "  kicad source     : $KICAD_SOURCE_DIR"
echo "  lib dir          : $LIBRARIES_DIR"
echo "    symbols        : ${LIB_SOURCE_DIR[symbols]}"
echo "    footprints     : ${LIB_SOURCE_DIR[footprints]}"
echo "    packages3d     : ${LIB_SOURCE_DIR[packages3d]}"
echo "    templates      : ${LIB_SOURCE_DIR[templates]}"
echo "  edge-headless zip: $EDGE_HEADLESS_ZIP"
echo "  edge version/sha : $EDGE_HEADLESS_VERSION / ${EDGE_HEADLESS_SHA256:0:12}…"
echo "  tag / release    : $TAG"
echo "  lib ref (fallback): $LIB_REF"
echo "  docs             : skipped (KMB_ENABLE_DOCS=OFF)"
echo "  brew prefix      : $BREW_PREFIX"
echo "  target           : $TARGET"
echo "===================================================================="

# --- optional clean (mirrors release.sh) -----------------------------------
if [[ "$CLEAN" == "1" ]]; then
    echo "Cleaning staged KiCad build output (build/kicad/src/kicad-build)..."
    rm -rf build/kicad/src/kicad-build/*
fi

# NOTE: --release-name is deliberately NOT passed.  With a local source dir
# (--kicad-source-dir) build.py sets -DRELEASE_NAME, which would make
# kicad.cmake take its release branch and demand KICAD_TAG -> FATAL.  package.sh
# auto-names the DMG (kicad-unified-<now>-<rev>.dmg) and the rename step below
# renames it to the release asset name.
BUILD_CMD=(./build.py
    --arch="$ARCH"
    --kicad-source-dir "$KICAD_SOURCE_DIR"
    --symbols-source-dir "${LIB_SOURCE_DIR[symbols]}"
    --footprints-source-dir "${LIB_SOURCE_DIR[footprints]}"
    --packages3d-source-dir "${LIB_SOURCE_DIR[packages3d]}"
    --templates-source-dir "${LIB_SOURCE_DIR[templates]}"
    --target "$TARGET"
    --build-type Release
    --extra-version="$EXTRA_VERSION"
    --skip-docs
    --symbols-ref "$LIB_REF"
    --footprints-ref "$LIB_REF"
    --packages3d-ref "$LIB_REF"
    --templates-ref "$LIB_REF"
    --edge-headless-version "$EDGE_HEADLESS_VERSION"
    --edge-headless-sha256 "$EDGE_HEADLESS_SHA256"
    --edge-headless-url "$EDGE_HEADLESS_ZIP"
)

echo "Running: ${BUILD_CMD[*]}"
if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] not building."
    exit 0
fi

CFLAGS="-I${BREW_PREFIX}/include" \
CXXFLAGS="-I${BREW_PREFIX}/include" \
WX_SKIP_DOXYGEN_VERSION_CHECK=1 \
"${BUILD_CMD[@]}"

# --- rename DMG to release asset name (as kicad-package.yml does) -----------
SRC="$(find build/dmg -name 'kicad-unified-*.dmg' 2>/dev/null | head -n1)"
if [[ -z "$SRC" ]]; then
    echo "ERROR: no kicad-unified-*.dmg found in build/dmg/" >&2
    ls -la build/dmg/ 2>/dev/null || true
    exit 1
fi
DST="build/dmg/kicad-${RELEASE_NAME}.dmg"
echo "Renaming:"
echo "  $SRC"
echo "  -> $DST"
mv "$SRC" "$DST"

# --- verify the packaged binary is arm64 (mirrors kicad-package.yml) --------
MNT="$(mktemp -d /tmp/kicad-local-dmg.XXXXXX)"
hdiutil attach "$DST" -mountpoint "$MNT" -nobrowse -readonly -noautoopen >/dev/null
BIN="$(find "$MNT" -path '*/MacOS/kicad' -type f | head -n1)"
if [[ -n "$BIN" ]]; then
    echo "file output for $BIN:"
    file "$BIN"
else
    echo "Note: kicad binary not found inside DMG to inspect."
fi
hdiutil detach "$(hdiutil info | grep -A1 "$MNT" | grep '^/dev/' | awk '{print $1}')" -force >/dev/null 2>&1 || true

echo
echo "Done. Installer: $DST"
echo "  kicad source      : $KICAD_SOURCE_DIR"
echo "  edge-headless     : $EDGE_HEADLESS_ZIP (sha256 ${EDGE_HEADLESS_SHA256})"
