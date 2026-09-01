#!/bin/bash

# Bootstrap a native Apple Silicon build environment on an Apple Silicon system.
#
# This script prepares an ARM64 Homebrew environment for building KiCad
# natively on Apple Silicon.
#
# Strategy (docs/gradually-stabilize-homebrew-deps.md):
#
#   * Use normal Homebrew (`brew update` + `brew install`) for all KiCad
#     dependencies. This mirrors the 2026-07-23 known-good GitHub Actions
#     run (docs/success_run.log), which did NOT pin the homebrew/core
#     repository and still produced matching ARM64/x86_64 versions.
#
#   * Do NOT freeze the entire homebrew/core repository. The previous
#     whole-repo pin was over-engineering and is explicitly discouraged by
#     the task spec (section 9: "freeze the entire Homebrew repository
#     without evidence that it is necessary").
#
#   * Pin only the dependencies that actually show an architecture mismatch
#     in CI. The first observed mismatch is openssl@3 (ARM64 3.6.4 vs
#     x86_64 3.6.2; known-good 3.6.3). The pin uses the smallest Homebrew-
#     native mechanism available: the historical formula file checked into
#     homebrew/core at the commit that carried the desired bottle.
#
#   * Verification (ci/src/watermark.sh --both, run later by the build
#     script) remains strict: ARM64 and x86_64 versions must match exactly
#     for every BREW_DEPS entry, and the script fails the build on any
#     drift from the shared baseline in ci/src/brew_versions.sh.

set -x
set -e


# ---------------------------------------------------------------------------
# Script setup
# ---------------------------------------------------------------------------

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "${SCRIPT_DIR}/../src/brew_deps.sh"
source "${SCRIPT_DIR}/../src/brew_versions.sh"


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Native Apple Silicon Homebrew.
BREW="/opt/homebrew/bin/brew"

# Pin openssl@3 to the 2026-07-23 known-good version (3.6.3).
#
# This is the ONLY formula currently pinned, because it is the only observed
# architecture mismatch (section 10). Other formulas remain on the normal
# Homebrew API install path until/unless verification shows another mismatch.
#
# The commit below is the homebrew/core revision that carried the 3.6.3
# bottle active on 2026-07-23 ("openssl@3: update 3.6.3 bottle.").
#
# To find a replacement commit, query the homebrew/core history for the
# openssl@3 formula and pick a commit whose message and tree carry the
# desired version + bottle SHA.
OPENSSL_PIN_FORMULA="openssl@3"
# Use the brew_version_of helper from brew_versions.sh -- it is bash 3.2
# compatible (parallel indexed arrays), whereas ${BREW_VERSIONS[...]}
# associative-array syntax is not supported by macOS's /bin/bash.
OPENSSL_PIN_VERSION="$(brew_version_of "${OPENSSL_PIN_FORMULA}")"
OPENSSL_PIN_COMMIT="afd93f1b5d40319fef3976408e83f0b232de81ac"
OPENSSL_PIN_URL="https://raw.githubusercontent.com/Homebrew/homebrew-core/${OPENSSL_PIN_COMMIT}/Formula/o/openssl%403.rb"


# ---------------------------------------------------------------------------
# Check architecture
# ---------------------------------------------------------------------------

echo "Checking Apple Silicon architecture..."

ARCH=$(arch)
MACHINE=$(machine)

echo "  arch:    ${ARCH}"
echo "  machine: ${MACHINE}"

if [ "$ARCH" != "arm64" ]; then
  echo "ERROR: expected native arm64 execution."
  echo "       arch=${ARCH}"
  exit 1
fi

if [ "$MACHINE" != "arm64" ] && [ "$MACHINE" != "arm64e" ]; then
  echo "ERROR: unexpected machine architecture."
  echo "       machine=${MACHINE}"
  exit 1
fi

echo "Native Apple Silicon environment detected."


# ---------------------------------------------------------------------------
# Install native Homebrew if necessary
# ---------------------------------------------------------------------------

if [ ! -e "${BREW}" ]; then
  echo "Installing native Homebrew..."

  /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    < /dev/null
fi


if [ ! -x "${BREW}" ]; then
  echo "ERROR: native Homebrew was not installed correctly."
  echo "       expected: ${BREW}"
  exit 1
fi


# ---------------------------------------------------------------------------
# Homebrew configuration
# ---------------------------------------------------------------------------
#
# Match the 2026-07-23 known-good run: only HOMEBREW_NO_ANALYTICS is set.
# Do NOT set HOMEBREW_NO_INSTALL_FROM_API globally here -- the normal API
# install path is what produced the known-good dependency versions.
# HOMEBREW_NO_INSTALL_FROM_API is only enabled locally for the historical
# openssl@3 formula install below.
#

export HOMEBREW_NO_ANALYTICS=1


# ---------------------------------------------------------------------------
# Homebrew information
# ---------------------------------------------------------------------------

echo "Using native ARM64 Homebrew:"
"${BREW}" --version

echo "Homebrew configuration:"
"${BREW}" config


# ---------------------------------------------------------------------------
# Update Homebrew (matches known-good run)
# ---------------------------------------------------------------------------

echo "Updating Homebrew..."
"${BREW}" update


# ---------------------------------------------------------------------------
# Install KiCad dependencies (normal Homebrew path)
# ---------------------------------------------------------------------------

echo "Installing KiCad dependencies..."
echo "Dependencies:"
printf '  %s\n' "${BREW_DEPS[@]}"

"${BREW}" install "${BREW_DEPS[@]}"


# ---------------------------------------------------------------------------
# Pin openssl@3 to the known-good version
# ---------------------------------------------------------------------------
#
# This is the only formula currently pinned, justified by the observed
# architecture mismatch (section 10). All other formulas rely on the normal
# Homebrew install above until CI verification shows another mismatch.
#
# The pin uses the historical Homebrew formula file from the homebrew/core
# commit that carried the desired 3.6.3 bottle.
#
# Implementation note (section 9 second-choice fallback): modern Homebrew
# (4.x and later, including the macos-14-arm64 GitHub Actions runner image)
# refuses to install a formula from a raw HTTPS URL or a local .rb file --
# "Homebrew requires formulae to be in a tap". The previous URL install
# (brew install <https://raw.githubusercontent.com/.../openssl%403.rb>)
# failed on the 2026-09-01 runner with:
#
#     No available formula or cask with the name "https://..."
#     This command requires the tap https:/.
#
# The smallest mechanism that still satisfies section 9's first choice
# (historical homebrew-core formula, no new package manager) is to create a
# tiny runtime vendored tap under Homebrew's Library/Taps and install from
# there. The tap is created on demand; no repo-side tap directory is needed.
#
# If the 3.6.3 bottle has been GCRed from GHCR and the source build also
# fails (patches are absolute URLs in this formula revision, so a source
# build should still work), the next round will pre-vendor the .rb into the
# repo and ship the patch files alongside it.

echo "Pinning ${OPENSSL_PIN_FORMULA} to ${OPENSSL_PIN_VERSION}..."

CURRENT_OPENSSL_VERSION="$(
  "${BREW}" list --versions "${OPENSSL_PIN_FORMULA}" 2>/dev/null \
    | awk '{print $2}'
)"

echo "  current ${OPENSSL_PIN_FORMULA} version: ${CURRENT_OPENSSL_VERSION:-<none>}"
echo "  desired ${OPENSSL_PIN_FORMULA} version: ${OPENSSL_PIN_VERSION}"

if [ "${CURRENT_OPENSSL_VERSION}" = "${OPENSSL_PIN_VERSION}" ]; then
  echo "  already at ${OPENSSL_PIN_VERSION}; nothing to do."
else
  if [ -n "${CURRENT_OPENSSL_VERSION}" ]; then
    echo "  uninstalling existing ${OPENSSL_PIN_FORMULA} (all kegs)..."
    # Use --force so ALL historical kegs are removed. A plain
    # `brew uninstall --ignore-dependencies` removes only the active keg
    # and leaves older kegs behind; those then become the new active
    # version and silently break the pin (section 12).
    "${BREW}" uninstall --force --ignore-dependencies "${OPENSSL_PIN_FORMULA}" || true
  fi

  # Runtime vendored tap (modern Homebrew requires formulas to live in a tap).
  TAP_USER="kicadpin"
  TAP_REPO="kicad-pin"
  TAP_DIR="$("${BREW}" --repository)/Library/Taps/${TAP_USER}/homebrew-${TAP_REPO}"
  TAP_FORMULA_DIR="${TAP_DIR}/Formula"
  TAP_FORMULA_FILE="${TAP_FORMULA_DIR}/${OPENSSL_PIN_FORMULA}.rb"

  echo "  creating local tap ${TAP_USER}/${TAP_REPO} at:"
  echo "    ${TAP_DIR}"
  mkdir -p "${TAP_FORMULA_DIR}"

  echo "  downloading historical formula from:"
  echo "    ${OPENSSL_PIN_URL}"
  curl -fsSL "${OPENSSL_PIN_URL}" -o "${TAP_FORMULA_FILE}"

  echo "  installing ${TAP_USER}/${TAP_REPO}/${OPENSSL_PIN_FORMULA}"
  HOMEBREW_NO_INSTALL_FROM_API=1 \
    "${BREW}" install "${TAP_USER}/${TAP_REPO}/${OPENSSL_PIN_FORMULA}"
fi


# ---------------------------------------------------------------------------
# Verify installed dependencies
# ---------------------------------------------------------------------------

echo "Installed KiCad dependencies:"

for dep in "${BREW_DEPS[@]}"; do
  echo
  echo "============================================================"
  echo "Dependency: ${dep}"
  echo "============================================================"

  "${BREW}" list --versions "${dep}" || true
done


# ---------------------------------------------------------------------------
# Explicitly verify openssl@3 (the only currently pinned formula)
# ---------------------------------------------------------------------------

echo
echo "Verifying openssl@3..."

if printf '%s\n' "${BREW_DEPS[@]}" | grep -qx "openssl@3"; then
  "${BREW}" list --versions openssl@3
  "${BREW}" info openssl@3
else
  echo "openssl@3 is not present in BREW_DEPS."
fi


# ---------------------------------------------------------------------------
# Clean up Homebrew
# ---------------------------------------------------------------------------

echo "Cleaning up Homebrew..."

"${BREW}" cleanup -s


# ---------------------------------------------------------------------------
# Final environment summary
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "Bootstrap complete"
echo "============================================================"

echo "Architecture:"
echo "  arch:    ${ARCH}"
echo "  machine: ${MACHINE}"

echo
echo "Homebrew:"
"${BREW}" --version

echo
echo "Done!"
