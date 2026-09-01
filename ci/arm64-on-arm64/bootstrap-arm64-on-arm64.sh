#!/bin/bash

# Bootstrap a native Apple Silicon build environment on an Apple Silicon system.
#
# This script prepares an ARM64 Homebrew environment for building KiCad
# natively on Apple Silicon.
#
# The Homebrew package definitions (homebrew/core) are pinned to a known-good
# commit instead of using the current Homebrew formula/API state.
#
# This is intentional:
#
#   - nng may lose compatible bottles
#   - openssl@3 may lose compatible bottles
#   - other KiCad dependencies may also change or lose bottles
#
# Pinning the entire homebrew/core repository keeps the dependency universe
# consistent instead of maintaining individual formula pins.
#
# IMPORTANT:
#
# CORE_COMMIT should ideally be the homebrew/core commit from the last
# known-good KiCad build. The current value is the commit already known to
# provide the previously successful nng 1.12.0 bottle.
#
#     58656612e45244656656414088afd240fd85de08
#
# "nng: update 1.12.0 bottle"
#
# If a later/earlier known-good KiCad CI build has a different homebrew/core
# revision, replace CORE_COMMIT with that revision.


set -x
set -e


# ---------------------------------------------------------------------------
# Script setup
# ---------------------------------------------------------------------------

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "${SCRIPT_DIR}/../src/brew_deps.sh"


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Known-good Homebrew Core revision.
#
# Prefer replacing this with the exact homebrew/core commit from the last
# successful KiCad build if that information is available.
#
CORE_COMMIT="58656612e45244656656414088afd240fd85de08"


# Native Apple Silicon Homebrew.
BREW="/opt/homebrew/bin/brew"


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
# Do not let Homebrew automatically move the environment forward.
#
# HOMEBREW_NO_INSTALL_FROM_API is important here. Without it, modern
# Homebrew may use the remote formula API rather than the locally checked-out
# homebrew/core repository.
#

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_INSTALL_FROM_API=1


# ---------------------------------------------------------------------------
# Homebrew information
# ---------------------------------------------------------------------------

echo "Using native ARM64 Homebrew:"
"${BREW}" --version

echo "Homebrew configuration:"
"${BREW}" config


# ---------------------------------------------------------------------------
# Ensure homebrew/core is available locally
# ---------------------------------------------------------------------------
#
# We intentionally use a local checkout of homebrew/core rather than the
# current Homebrew API.
#

echo "Checking homebrew/core..."

if ! "${BREW}" tap | grep -q '^homebrew/core$'; then
  echo "Adding homebrew/core..."

  "${BREW}" tap --force homebrew/core
fi


# ---------------------------------------------------------------------------
# Locate homebrew/core repository
# ---------------------------------------------------------------------------

CORE_REPO="$("${BREW}" --repository homebrew/core)"

echo "Homebrew Core repository:"
echo "  ${CORE_REPO}"


if [ ! -d "${CORE_REPO}/.git" ]; then
  echo "ERROR: homebrew/core is not a Git repository:"
  echo "       ${CORE_REPO}"
  exit 1
fi


# ---------------------------------------------------------------------------
# Pin homebrew/core
# ---------------------------------------------------------------------------
#
# Do NOT run `brew update` here.
#
# Updating Homebrew would move homebrew/core away from the pinned revision.
#
# Instead, fetch exactly the requested commit and checkout that commit in
# detached HEAD state.
#

echo "Pinning homebrew/core..."
echo "  Commit: ${CORE_COMMIT}"

git -C "${CORE_REPO}" fetch --force origin "${CORE_COMMIT}"

git -C "${CORE_REPO}" checkout --detach "${CORE_COMMIT}"


# ---------------------------------------------------------------------------
# Verify homebrew/core revision
# ---------------------------------------------------------------------------

ACTUAL_CORE_COMMIT="$(
  git -C "${CORE_REPO}" rev-parse HEAD
)"

echo "Homebrew Core revision:"
echo "  Expected: ${CORE_COMMIT}"
echo "  Actual:   ${ACTUAL_CORE_COMMIT}"

if [ "${ACTUAL_CORE_COMMIT}" != "${CORE_COMMIT}" ]; then
  echo "ERROR: homebrew/core revision mismatch."
  exit 1
fi

echo "Homebrew Core successfully pinned."


# ---------------------------------------------------------------------------
# Show pinned Core revision
# ---------------------------------------------------------------------------

echo "Homebrew Core commit information:"
git -C "${CORE_REPO}" log -1 --oneline --decorate


# ---------------------------------------------------------------------------
# Install KiCad dependencies
# ---------------------------------------------------------------------------
#
# All dependencies, including nng and openssl@3, are installed from the
# pinned homebrew/core revision.
#
# There is intentionally NO special handling for nng.
# There is intentionally NO special handling for openssl@3.
#
# This is the key difference from the previous bootstrap.
#

echo "Installing KiCad dependencies from pinned homebrew/core..."

echo "Dependencies:"
printf '  %s\n' "${BREW_DEPS[@]}"


"${BREW}" install "${BREW_DEPS[@]}"


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
# Explicitly verify the previously problematic packages
# ---------------------------------------------------------------------------

echo
echo "Verifying nng..."

if printf '%s\n' "${BREW_DEPS[@]}" | grep -qx "nng"; then
  "${BREW}" list --versions nng
  "${BREW}" info nng
else
  echo "nng is not present in BREW_DEPS."
fi


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
#
# Keep cleanup disabled during installation, but explicitly clean at the end.
#

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
echo "Homebrew Core:"
git -C "${CORE_REPO}" log -1 --oneline

echo
echo "Homebrew Core revision:"
git -C "${CORE_REPO}" rev-parse HEAD

echo
echo "Done!"