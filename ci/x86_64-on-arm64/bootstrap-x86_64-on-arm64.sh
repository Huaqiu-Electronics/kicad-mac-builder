#!/bin/bash

# Bootstrap an x86_64 Homebrew build environment on an Apple Silicon system.
#
# This script prepares an x86_64 Homebrew environment for building the
# x86_64 version of KiCad on an Apple Silicon Mac through Rosetta 2.
#
# Homebrew:
#
#   Native ARM64:
#       /opt/homebrew/bin/brew
#
#   x86_64:
#       /usr/local/bin/brew
#
# This script intentionally uses the x86_64 Homebrew installation.
#
# The entire Homebrew Core repository is pinned to a known-good commit.
# This keeps all KiCad dependencies, including nng and openssl@3,
# on a consistent historical formula/bottle set.
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
# Git is intentionally NOT executed through Rosetta. GitHub Actions'
# Apple Silicon runners provide a native ARM64 Git, which can operate on
# the x86_64 Homebrew Core checkout without any problem.
#
# Homebrew itself is always executed through Rosetta.


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

CORE_COMMIT="58656612e45244656656414088afd240fd85de08"

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
# Check host architecture
# ---------------------------------------------------------------------------

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
# Do not let Homebrew automatically update or clean up dependencies.
#
# HOMEBREW_NO_INSTALL_FROM_API is important because we want Homebrew to use
# the locally checked-out homebrew/core repository at CORE_COMMIT.
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
# Git is native ARM64 on Apple Silicon.
#
# DO NOT use:
#
#   arch -x86_64 git
#
# The GitHub Actions runner's Git is ARM64 and should be used directly.
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
# All dependencies come from the pinned homebrew/core revision.
#
# No individual formula pinning is required.
#
# In particular:
#
#   nng
#   openssl@3
#   xz
#   lz4
#
# are all resolved from the same historical Core revision.
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
# Explicitly verify nng
# ---------------------------------------------------------------------------

echo
echo "Verifying nng..."

if printf '%s\n' "${BREW_DEPS[@]}" | grep -qx "nng"; then
  arch -x86_64 "${BREW}" list --versions nng
  arch -x86_64 "${BREW}" info nng
else
  echo "nng is not present in BREW_DEPS."
fi


# ---------------------------------------------------------------------------
# Explicitly verify openssl
# ---------------------------------------------------------------------------

echo
echo "Verifying openssl..."

if printf '%s\n' "${BREW_DEPS[@]}" | grep -qx "openssl"; then
  arch -x86_64 "${BREW}" list --versions openssl
  arch -x86_64 "${BREW}" info openssl
else
  echo "openssl is not present in BREW_DEPS."
fi


# ---------------------------------------------------------------------------
# Clean up Homebrew
# ---------------------------------------------------------------------------

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
echo "Homebrew:"
arch -x86_64 "${BREW}" --version

echo
echo "Homebrew prefix:"
arch -x86_64 "${BREW}" --prefix

echo
echo "Homebrew configuration:"
arch -x86_64 "${BREW}" config

echo
echo "Homebrew Core:"
git -C "${CORE_REPO}" log -1 --oneline

echo
echo "Homebrew Core revision:"
git -C "${CORE_REPO}" rev-parse HEAD

echo
echo "Done!"