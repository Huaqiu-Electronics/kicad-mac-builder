#!/bin/bash

# ---------------------------------------------------------------------------
# fetch-edge-headless.sh — obtain, verify and extract the pinned
# `edge-headless` runtime that gets bundled into KiCad.app on Apple Silicon.
#
# This is a BUILD-TIME step only.  Nothing here runs on the user's machine and
# nothing is downloaded when KiCad starts: the resulting tree is copied into
# KiCad.app/Contents/Resources/edge-headless by the
# `install-edge-headless-into-app` step (see edge-headless.cmake), so the
# application is fully self-contained (and offline-capable) after install.
#
# The release is PINNED: version + asset name + SHA256 all come from
# build-config.json via edge-headless.cmake (or from the caller).  There is no "latest" and there is no
# silent fallback to a developer-local checkout — every failure below aborts
# the build with a non-zero exit status.
#
# Environment:
#   EDGE_HEADLESS_VERSION       Release tag (required, e.g. "0.1.3")
#   EDGE_HEADLESS_ASSET         Release asset name
#                               (default: edge-headless-darwin-arm64.zip)
#   EDGE_HEADLESS_SHA256        Expected SHA256 of the asset.
#                               Set EDGE_HEADLESS_REQUIRE_SHA256=0 to skip
#                               (never for release builds).
#   EDGE_HEADLESS_URL           Full URL override.  Accepts https://, file://
#                               or a plain filesystem path — this is how an
#                               unpublished artifact is staged locally.
#   EDGE_HEADLESS_REPO_URL      Release download base
#                               (default: https://github.com/Huaqiu-Electronics/edge-headless/releases/download)
#   EDGE_HEADLESS_ARCH          Required Mach-O architecture of bin/node
#                               (default: arm64)
#   EDGE_HEADLESS_DOWNLOAD_DIR  Scratch directory for the archive + extraction
#   EDGE_HEADLESS_DEST          Final destination of the extracted tree
#                               (…/edge-headless-dest)
# ---------------------------------------------------------------------------

set -euo pipefail

log()  { echo "[edge-headless] $*"; }
fail() { echo "[edge-headless] ERROR: $*" >&2; exit 1; }

: "${EDGE_HEADLESS_VERSION:?EDGE_HEADLESS_VERSION must be set (pinned release tag)}"
: "${EDGE_HEADLESS_DOWNLOAD_DIR:?EDGE_HEADLESS_DOWNLOAD_DIR must be set}"
: "${EDGE_HEADLESS_DEST:?EDGE_HEADLESS_DEST must be set}"

EDGE_HEADLESS_ASSET="${EDGE_HEADLESS_ASSET:-edge-headless-darwin-arm64.zip}"
EDGE_HEADLESS_REPO_URL="${EDGE_HEADLESS_REPO_URL:-https://github.com/Huaqiu-Electronics/edge-headless/releases/download}"
EDGE_HEADLESS_ARCH="${EDGE_HEADLESS_ARCH:-arm64}"
EDGE_HEADLESS_SHA256="${EDGE_HEADLESS_SHA256:-}"
EDGE_HEADLESS_REQUIRE_SHA256="${EDGE_HEADLESS_REQUIRE_SHA256:-1}"
EDGE_HEADLESS_URL="${EDGE_HEADLESS_URL:-}"

# ---------------------------------------------------------------------------
# 0. Re-use an already-fetched copy that matches this exact pin.
#    Avoids re-downloading a ~370 MB archive and re-extracting ~1 GB on every
#    incremental build.  The staged copy is still validated afterwards by
#    bin/verify-edge-headless.sh when it is installed into KiCad.app.
# ---------------------------------------------------------------------------
PIN_FILE="${EDGE_HEADLESS_DEST}/.kicad-mac-builder-pin"
WANTED_PIN="${EDGE_HEADLESS_VERSION}|${EDGE_HEADLESS_ASSET}|${EDGE_HEADLESS_SHA256}|${EDGE_HEADLESS_ARCH}"

if [ -f "${PIN_FILE}" ] && [ "$(cat "${PIN_FILE}")" = "${WANTED_PIN}" ] \
        && [ -x "${EDGE_HEADLESS_DEST}/bin/node" ]; then
    log "already fetched for pin '${WANTED_PIN}'; skipping download"
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Resolve the download source
# ---------------------------------------------------------------------------
if [ -n "${EDGE_HEADLESS_URL}" ]; then
    SRC="${EDGE_HEADLESS_URL}"
    log "source (override): ${SRC}"
else
    SRC="${EDGE_HEADLESS_REPO_URL}/${EDGE_HEADLESS_VERSION}/${EDGE_HEADLESS_ASSET}"
    log "source (release): ${SRC}"
fi

mkdir -p "${EDGE_HEADLESS_DOWNLOAD_DIR}"
ARCHIVE="${EDGE_HEADLESS_DOWNLOAD_DIR}/${EDGE_HEADLESS_ASSET}"

# ---------------------------------------------------------------------------
# 2. Download / copy the archive
# ---------------------------------------------------------------------------
log "fetching ${EDGE_HEADLESS_ASSET} (${EDGE_HEADLESS_VERSION}) ..."

case "${SRC}" in
    http://*|https://*)
        command -v curl >/dev/null 2>&1 || fail "curl is required to download ${SRC}"
        # -f: fail on HTTP errors, -L: follow redirects (GitHub release
        # assets are served from objects.githubusercontent.com).
        if ! curl -fL --retry 3 --retry-delay 2 -o "${ARCHIVE}" "${SRC}"; then
            rm -f "${ARCHIVE}"
            fail "download failed: ${SRC}"
        fi
        ;;
    file://*)
        LOCAL="${SRC#file://}"
        [ -f "${LOCAL}" ] || fail "local artifact not found: ${LOCAL}"
        cp "${LOCAL}" "${ARCHIVE}"
        ;;
    *)
        [ -f "${SRC}" ] || fail "local artifact not found: ${SRC}"
        cp "${SRC}" "${ARCHIVE}"
        ;;
esac

[ -s "${ARCHIVE}" ] || fail "archive is empty: ${ARCHIVE}"

# ---------------------------------------------------------------------------
# 3. Verify the pin
# ---------------------------------------------------------------------------
if [ -n "${EDGE_HEADLESS_SHA256}" ]; then
    command -v shasum >/dev/null 2>&1 || fail "shasum is required to verify ${EDGE_HEADLESS_ASSET}"
    ACTUAL="$(shasum -a 256 "${ARCHIVE}" | awk '{print $1}')"
    if [ "${ACTUAL}" != "${EDGE_HEADLESS_SHA256}" ]; then
        fail "SHA256 mismatch for ${EDGE_HEADLESS_ASSET}
  expected: ${EDGE_HEADLESS_SHA256}
  actual:   ${ACTUAL}
  archive:  ${ARCHIVE}
Update them together with kicad-mac-builder/bin/pin-edge-headless.py, or in build-config.json."
    fi
    log "SHA256 verified: ${ACTUAL}"
elif [ "${EDGE_HEADLESS_REQUIRE_SHA256}" != "0" ]; then
    fail "EDGE_HEADLESS_SHA256 is not set; the edge-headless release must be pinned.
Set EDGE_HEADLESS_REQUIRE_SHA256=0 only for throwaway local experiments."
else
    log "WARNING: SHA256 verification disabled (EDGE_HEADLESS_REQUIRE_SHA256=0)"
fi

# ---------------------------------------------------------------------------
# 4. Extract
# ---------------------------------------------------------------------------
EXTRACT_DIR="${EDGE_HEADLESS_DOWNLOAD_DIR}/extract"
rm -rf "${EXTRACT_DIR}"
mkdir -p "${EXTRACT_DIR}"

log "extracting ..."
# `ditto -x -k` is the native macOS unzipper: it preserves permissions,
# symlinks and extended attributes, which matters for bin/node and for the
# symlinked node_modules layout inside dsh/.
ditto -x -k "${ARCHIVE}" "${EXTRACT_DIR}" || fail "extraction failed: ${ARCHIVE}"

# macOS zip artifacts carry AppleDouble metadata; it is never needed.
rm -rf "${EXTRACT_DIR}/__MACOSX"

# The release layout contract is a single top-level `edge-headless/` directory.
TOP_LEVELS="$(find "${EXTRACT_DIR}" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort)"
if [ "${TOP_LEVELS}" != "edge-headless" ]; then
    fail "unexpected archive layout: expected a single top-level 'edge-headless/' directory, got:
${TOP_LEVELS}"
fi

# ---------------------------------------------------------------------------
# 5. Install into the staging destination (atomic replace)
# ---------------------------------------------------------------------------
rm -rf "${EDGE_HEADLESS_DEST}.tmp"
mv "${EXTRACT_DIR}/edge-headless" "${EDGE_HEADLESS_DEST}.tmp"

rm -rf "${EDGE_HEADLESS_DEST}"
mkdir -p "$(dirname "${EDGE_HEADLESS_DEST}")"
mv "${EDGE_HEADLESS_DEST}.tmp" "${EDGE_HEADLESS_DEST}"

log "extracted to ${EDGE_HEADLESS_DEST}"

# ---------------------------------------------------------------------------
# 5b. Drop developer state baked into the artifact
#
# `dsh/.dsh` is a DSH_HOME that got materialised on the machine that BUILT the
# artifact.  It is never read at runtime: hq-edge resolves DSH_HOME itself and
# injects it into the bundled CLI -- `bin/dsh --hq-paths` run from inside a
# staged bundle reports
#     "dshHome": "~/.hq-edge/<version>/dsh-home", "dshHomeSource": "hq-managed"
# i.e. outside the bundle entirely (so DSH state does not invalidate the app's
# code signature either).
#
# Shipping it would (a) leak a developer's .credentials.yaml, and (b) break
# code signing: the directory is ~500 symlinks into a pnpm store that is not
# part of the archive, and a dangling symlink inside a sealed resource
# directory makes `codesign --verify --deep --strict` fail on the WHOLE app
# with "No such file or directory".
# ---------------------------------------------------------------------------
rm -rf "${EDGE_HEADLESS_DEST}/dsh/.dsh"

# Defensive: no dangling symlink may reach the bundle, for the reason above.
DANGLING="$(find "${EDGE_HEADLESS_DEST}" -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')"

if [ "${DANGLING}" != "0" ]; then
    log "pruning ${DANGLING} dangling symlink(s) from the runtime"
    find "${EDGE_HEADLESS_DEST}" -type l ! -exec test -e {} \; -delete 2>/dev/null || true

    DANGLING="$(find "${EDGE_HEADLESS_DEST}" -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')"

    [ "${DANGLING}" = "0" ] || fail "could not prune ${DANGLING} dangling symlink(s)"
fi

# ---------------------------------------------------------------------------
# 6. Validate the runtime before it is allowed into the bundle
# ---------------------------------------------------------------------------
REQUIRED_FILES=(
    "VERSION"
    "bin/node"
    "bin/hq-edge-server.cjs"
    "bin/dsh"
    "bin/dsh-cli.cjs"
    "config/runtime.env"
    "config/dsh.lock.yaml"
    "dsh/package.json"
    "dsh-plugins/manifest.json"
)

for rel in "${REQUIRED_FILES[@]}"; do
    [ -f "${EDGE_HEADLESS_DEST}/${rel}" ] \
        || fail "missing required runtime file: edge-headless/${rel}"
done
log "required files present ($((${#REQUIRED_FILES[@]})) checked)"

# Executable bits do not always survive the round-trip.
chmod +x "${EDGE_HEADLESS_DEST}/bin/node" "${EDGE_HEADLESS_DEST}/bin/dsh"

[ -x "${EDGE_HEADLESS_DEST}/bin/node" ] || fail "bin/node is not executable"
[ -x "${EDGE_HEADLESS_DEST}/bin/dsh" ]  || fail "bin/dsh is not executable"

# The bundled Node must be a native binary for the architecture we are
# packaging — an x86_64 node here would silently depend on Rosetta.
command -v lipo >/dev/null 2>&1 || fail "lipo is required to verify bin/node"
NODE_ARCHS="$(lipo -archs "${EDGE_HEADLESS_DEST}/bin/node" 2>/dev/null || true)"
case " ${NODE_ARCHS} " in
    *" ${EDGE_HEADLESS_ARCH} "*) ;;
    *) fail "bin/node does not contain ${EDGE_HEADLESS_ARCH} (lipo -archs: ${NODE_ARCHS})" ;;
esac
log "bin/node architecture: ${NODE_ARCHS}"

# Prove the bundled Node actually runs (catches Gatekeeper/adhoc-signing
# problems and wrong-architecture binaries before packaging continues).
NODE_VERSION="$("${EDGE_HEADLESS_DEST}/bin/node" -v 2>&1)" \
    || fail "bundled node does not run: ${NODE_VERSION}"
log "bundled node runs: ${NODE_VERSION}"

# Developer-only overrides must never reach a release artifact.
if grep -q '^[[:space:]]*DSH_LOCAL_PATH[[:space:]]*=' "${EDGE_HEADLESS_DEST}/config/runtime.env"; then
    fail "config/runtime.env contains a developer-only DSH_LOCAL_PATH override"
fi

printf '%s' "${WANTED_PIN}" > "${EDGE_HEADLESS_DEST}/.kicad-mac-builder-pin"

if [ -f "${EDGE_HEADLESS_DEST}/VERSION" ]; then
    log "artifact VERSION: $(tr '\n' ' ' < "${EDGE_HEADLESS_DEST}/VERSION")"
fi

log "edge-headless ${EDGE_HEADLESS_VERSION} (${EDGE_HEADLESS_ASSET}) ready"
