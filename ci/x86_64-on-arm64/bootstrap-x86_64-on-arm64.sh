#!/bin/bash

# Bootstrap an x86_64 Homebrew build environment on an Apple Silicon system.
#
# This script prepares an x86_64 Homebrew environment for building the
# x86_64 version of KiCad on an Apple Silicon Mac through Rosetta 2.
#
# On an Apple Silicon Mac there are two Homebrew installations:
#
#   Native ARM64:
#       /opt/homebrew/bin/brew
#
#   x86_64:
#       /usr/local/bin/brew
#
# This script intentionally uses the x86_64 Homebrew installation.
#
# All Homebrew formula definitions are pinned to a known-good
# homebrew/core commit.
#
# This is intentional because individual formulas can lose compatible
# bottles over time. For example:
#
#   - nng
#   - openssl@3
#   - xz
#   - lz4
#   - ...
#
# Rather than pinning individual formulas, the entire Homebrew Core
# dependency universe is pinned to one known-good revision.
#
# IMPORTANT:
#
# CORE_COMMIT should ideally be the homebrew/core commit from the last
# known-good KiCad build.
#
# The current value is the commit already known to provide the previously
# successful nng 1.12.0 bottle:
#
#   58656612e45244656656414088afd240fd85de08
#
# "nng: update 1.12.0 bottle"
#
# If the successful KiCad CI build used another homebrew/core revision,
# replace CORE_COMMIT with that revision.
#
#
# Rosetta:
#
# The complete build process should be launched as x86_64, for example:
#
#   arch -x86_64 ./build.py --target setup-kicad-dependencies
#
# or:
#
#   arch -x86_64 ./build.py --target kicad
#
# This script itself also explicitly invokes the x86_64 Homebrew binary
# through `arch -x86_64`.
#
#
# Notes:
#
# After this script completes, the x86_64 Homebrew environment is located
# at /usr/local.
#
# The native ARM64 Homebrew environment remains at /opt/homebrew.


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


# x86_64 Homebrew on Apple Silicon.
BREW="/usr/local/bin/brew"


# ---------------------------------------------------------------------------
# Check Rosetta 2
# ---------------------------------------------------------------------------

echo "Checking for Rosetta 2..."

if pgrep -q oahd; then
  echo "Rosetta 2 is installed."
else
  echo "Rosetta 2 is not installed."
  echo
  echo "Install it with:"
  echo
  echo "  /usr/sbin/softwareupdate --install-rosetta"
  echo
  exit 1
fi


# ---------------------------------------------------------------------------
# Check execution environment
# ---------------------------------------------------------------------------
#
# The host machine must be Apple Silicon, while the Homebrew process below
# must run as x86_64 under Rosetta.
#

HOST_MACHINE=$(machine)

echo "Host machine:"
echo "  ${HOST_MACHINE}"

if [ "${HOST_MACHINE}" != "arm64" ] && [ "${HOST_MACHINE}" != "arm64e" ]; then
  echo "ERROR: expected an Apple Silicon host."
  echo "       machine=${HOST_MACHINE}"
  exit 1
fi

echo "Apple Silicon host detected."


# ---------------------------------------------------------------------------
# Install x86_64 Homebrew if necessary
# ---------------------------------------------------------------------------

if [ ! -e "${BREW}" ]; then
  echo "Installing x86_64 Homebrew..."

  arch -x86_64 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    < /dev/null
fi


if [ ! -x "${BREW}" ]; then
  echo "ERROR: x86_64 Homebrew was not installed correctly."
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
# Homebrew may use the remote formula API instead of the locally checked-out
# homebrew/core repository.
#

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_INSTALL_FROM_API=1


# ---------------------------------------------------------------------------
# Homebrew information
# ---------------------------------------------------------------------------

echo "Using x86_64 Homebrew:"
arch -x86_64 "${BREW}" --version

echo "Homebrew configuration:"
arch -x86_64 "${BREW}" config


# ---------------------------------------------------------------------------
# Ensure homebrew/core is available locally
# ---------------------------------------------------------------------------
#
# We intentionally use a local checkout of homebrew/core rather than the
# current Homebrew API.
#

echo "Checking homebrew/core..."

if ! arch -x86_64 "${BREW}" tap | grep -q '^homebrew/core$'; then
  echo "Adding homebrew/core..."

  arch -x86_64 "${BREW}" tap --force homebrew/core
fi


# ---------------------------------------------------------------------------
# Locate homebrew/core repository
# ---------------------------------------------------------------------------

CORE_REPO="$(
  arch -x86_64 "${BREW}" --repository homebrew/core
)"

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
# Git itself is executed under Rosetta so that the operation is performed
# entirely within the x86_64 Homebrew environment.
#

echo "Pinning homebrew/core..."
echo "  Commit: ${CORE_COMMIT}"

arch -x86_64 git \
  -C "${CORE_REPO}" \
  fetch --force origin "${CORE_COMMIT}"

arch -x86_64 git \
  -C "${CORE_REPO}" \
  checkout --detach "${CORE_COMMIT}"


# ---------------------------------------------------------------------------
# Verify homebrew/core revision
# ---------------------------------------------------------------------------

ACTUAL_CORE_COMMIT="$(
  arch -x86_64 git \
    -C "${CORE_REPO}" \
    rev-parse HEAD
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

arch -x86_64 git \
  -C "${CORE_REPO}" \
  log -1 --oneline --decorate


# ---------------------------------------------------------------------------
# Install KiCad dependencies
# ---------------------------------------------------------------------------
#
# All dependencies, including nng and openssl@3, are installed from the
# pinned homebrew/core revision.
#
# There is intentionally NO special handling for:
#
#   nng
#   openssl@3
#   xz
#   lz4
#
# The entire dependency set is controlled by CORE_COMMIT.
#

echo "Installing KiCad dependencies from pinned homebrew/core..."

echo "Dependencies:"
printf '  %s\n' "${BREW_DEPS[@]}"


arch -x86_64 "${BREW}" install "${BREW_DEPS[@]}"


# ---------------------------------------------------------------------------
# Verify installed dependencies
# ---------------------------------------------------------------------------

echo "Installed KiCad dependencies:"

for dep in "${BREW_DEPS[@]}"; do
  echo
  echo "============================================================"
  echo "Dependency: ${dep}"
  echo "============================================================"

  arch -x86_64 "${BREW}" list --versions "${dep}" || true
done


# ---------------------------------------------------------------------------
# Explicitly verify the previously problematic packages
# ---------------------------------------------------------------------------

echo
echo "Verifying nng..."

if printf '%s\n' "${BREW_DEPS[@]}" | grep -qx "nng"; then
  arch -x86_64 "${BREW}" list --versions nng
  arch -x86_64 "${BREW}" info nng
else
  echo "nng is not present in BREW_DEPS."
fi


echo
echo "Verifying openssl@3..."

if printf '%s\n' "${BREW_DEPS[@]}" | grep -qx "openssl@3"; then
  arch -x86_64 "${BREW}" list --versions openssl@3
  arch -x86_64 "${BREW}" info openssl@3
else
  echo "openssl@3 is not present in BREW_DEPS."
fi


# ---------------------------------------------------------------------------
# Clean up Homebrew
# ---------------------------------------------------------------------------
#
# Keep automatic cleanup disabled during installation, then explicitly
# clean at the end.
#

echo "Cleaning up Homebrew..."

arch -x86_64 "${BREW}" cleanup -s


# ---------------------------------------------------------------------------
# Final environment summary
# ---------------------------------------------------------------------------

echo
echo "============================================================"
echo "Bootstrap complete"
echo "============================================================"

echo "Host architecture:"
echo "  machine: ${HOST_MACHINE}"

echo
echo "Execution architecture:"
arch -x86_64 arch

echo
echo "Homebrew:"
arch -x86_64 "${BREW}" --version

echo
echo "Homebrew Core:"
arch -x86_64 git \
  -C "${CORE_REPO}" \
  log -1 --oneline

echo
echo "Homebrew Core revision:"
arch -x86_64 git \
  -C "${CORE_REPO}" \
  rev-parse HEAD

echo
echo "Homebrew prefix:"
arch -x86_64 "${BREW}" --prefix

echo
echo "Done!"