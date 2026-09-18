#!/bin/bash

# ---------------------------------------------------------------------------
# verify-edge-headless.sh — validate the edge-headless runtime that has already
# been staged into the KiCad application bundle.
#
# Runs twice in the packaging flow:
#   * after `install-edge-headless-into-app` (inside build/kicad-dest/KiCad.app)
#   * and can be run by hand against an installed KiCad.app
#
# It is the guard that makes "the bundled runtime is broken" a BUILD failure
# instead of a silent runtime fallback: HQ_EDGE_LAUNCHER logs a warning and
# skips hq-edge when these files are missing, and the Copilot panel would then
# quietly fall back to the online https://chat.eda.cn/ chat.
#
# Usage:
#   verify-edge-headless.sh <path-to-KiCad.app>
#   verify-edge-headless.sh <path-to-KiCad.app> <relative-path-inside-bundle>
#
# Environment:
#   EDGE_HEADLESS_ARCH     Required Mach-O architecture of bin/node (arm64)
#   EDGE_HEADLESS_RUN_DSH  Set to 0 to skip the `bin/dsh --version` smoke test
#   EDGE_HEADLESS_VERSION  Expected release tag from build-config.json; checked
#                          against the artifact's own VERSION manifest when set
#                          (the packaging step always sets it)
# ---------------------------------------------------------------------------

set -euo pipefail

log()  { echo "[verify-edge-headless] $*"; }
fail() { echo "[verify-edge-headless] ERROR: $*" >&2; exit 1; }

APP="${1:?usage: verify-edge-headless.sh <KiCad.app> [relative-path]}"
EDGE_REL="${2:-Contents/Resources/edge-headless}"
EDGE_HEADLESS_ARCH="${EDGE_HEADLESS_ARCH:-arm64}"
EDGE_HEADLESS_RUN_DSH="${EDGE_HEADLESS_RUN_DSH:-1}"
EDGE_HEADLESS_VERSION="${EDGE_HEADLESS_VERSION:-}"

[ -d "${APP}" ] || fail "not a directory: ${APP}"

EDGE_DIR="${APP}/${EDGE_REL}"
log "checking ${EDGE_DIR}"

[ -d "${EDGE_DIR}" ] || fail "bundled edge-headless not found at ${EDGE_DIR}"

# Everything hq-edge / DSH needs at runtime must be inside the bundle.
REQUIRED_FILES=(
    "bin/node"
    "bin/hq-edge-server.cjs"
    "bin/dsh"
    "bin/dsh-cli.cjs"
    "config/runtime.env"
    "dsh/package.json"
    "dsh-plugins/manifest.json"
)

for rel in "${REQUIRED_FILES[@]}"; do
    [ -f "${EDGE_DIR}/${rel}" ] || fail "missing bundled runtime file: ${EDGE_REL}/${rel}"
done
log "required files present ($((${#REQUIRED_FILES[@]})) checked)"

[ -x "${EDGE_DIR}/bin/node" ] || fail "bundled bin/node is not executable"
[ -x "${EDGE_DIR}/bin/dsh" ]  || fail "bundled bin/dsh is not executable"

# ---------------------------------------------------------------------------
# Architecture
# ---------------------------------------------------------------------------
NODE_ARCHS="$(lipo -archs "${EDGE_DIR}/bin/node" 2>/dev/null || true)"
case " ${NODE_ARCHS} " in
    *" ${EDGE_HEADLESS_ARCH} "*) ;;
    *) fail "bundled bin/node does not contain ${EDGE_HEADLESS_ARCH} (lipo -archs: ${NODE_ARCHS})" ;;
esac
log "bin/node architecture: ${NODE_ARCHS}"

# ---------------------------------------------------------------------------
# Smoke tests — prove the bundled runtime works from inside the bundle, with
# no PATH node and no developer checkout involved.
# ---------------------------------------------------------------------------
NODE_VERSION="$("${EDGE_DIR}/bin/node" -v 2>&1)" \
    || fail "bundled node does not run: ${NODE_VERSION}"
log "bundled node runs: ${NODE_VERSION}"

CJS="${EDGE_DIR}/bin/hq-edge-server.cjs"
if ! "${EDGE_DIR}/bin/node" --check "${CJS}" >/dev/null 2>&1; then
    fail "bundled hq-edge-server.cjs failed a syntax check"
fi
log "hq-edge-server.cjs parses"

if [ "${EDGE_HEADLESS_RUN_DSH}" != "0" ]; then
    DSH_VERSION="$("${EDGE_DIR}/bin/dsh" --version 2>&1)" \
        || fail "bundled dsh does not run: ${DSH_VERSION}"
    log "bundled dsh runs: ${DSH_VERSION}"
fi

# A dangling symlink inside a sealed resource directory makes
# `codesign --verify --deep --strict` fail on the whole application with
# "No such file or directory", so it must never reach the bundle.
DANGLING="$(find "${EDGE_DIR}" -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')"

if [ "${DANGLING}" != "0" ]; then
    fail "${DANGLING} dangling symlink(s) under ${EDGE_REL}; codesign cannot seal the bundle"
fi
log "no dangling symlinks"

# ---------------------------------------------------------------------------
# The staged runtime must be the one the build pinned in build-config.json.
# The artifact's VERSION manifest is `HQ_EDGE_VERSION=<describe>` (e.g.
# 0.1.3 or 0.1.3-25-g5365af5), so the pin is matched as a prefix.
# ---------------------------------------------------------------------------
if [ -n "${EDGE_HEADLESS_VERSION}" ] && [ -f "${EDGE_DIR}/VERSION" ]; then
    ARTIFACT_VERSION="$(sed -n 's/^HQ_EDGE_VERSION=//p' "${EDGE_DIR}/VERSION" | head -1)"

    case "${ARTIFACT_VERSION}" in
        "${EDGE_HEADLESS_VERSION}"|"${EDGE_HEADLESS_VERSION}"-*)
            log "pin matches bundled runtime: ${ARTIFACT_VERSION} (pin ${EDGE_HEADLESS_VERSION})" ;;
        *)
            fail "bundled runtime reports '${ARTIFACT_VERSION:-<unknown>}' but the pin is '${EDGE_HEADLESS_VERSION}'" ;;
    esac
fi

# ---------------------------------------------------------------------------
# Release hygiene: no developer machine paths may leak into the bundle.
# ---------------------------------------------------------------------------
if grep -Rlqs "/Users/admin/code" "${EDGE_DIR}/config" "${EDGE_DIR}/VERSION" 2>/dev/null; then
    fail "developer checkout path (/Users/admin/code) leaked into the bundled runtime config"
fi
log "no developer paths in bundled config"

log "OK: ${EDGE_REL}"
