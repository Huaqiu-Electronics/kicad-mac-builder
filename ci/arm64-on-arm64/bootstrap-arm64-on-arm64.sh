#!/bin/bash

# Bootstrap a native Apple Silicon build environment on an Apple Silicon system.
#
# This script is intended for building the ARM64 version of KiCad natively
# on an Apple Silicon Mac.
#
# Homebrew:
#
#   Native ARM64 Homebrew:
#       /opt/homebrew/bin/brew
#
# Unlike the x86_64-on-ARM64 bootstrap, this script does not use Rosetta 2.
#
# nng:
#
# nng is intentionally NOT installed directly from the current Homebrew
# formula. We pin it to the known-good nng 1.12.0 formula used by the
# successful KiCad build.
#
# Homebrew Core commit:
#
#   58656612e45244656656414088afd240fd85de08
#
# "nng: update 1.12.0 bottle"
#
# The pinned formula is installed through a temporary/local tap:
#
#   huaqiu/nng-pin
#
# This keeps the native ARM64 bootstrap aligned with the
# x86_64-under-Rosetta bootstrap.


set -x
set -e


# ---------------------------------------------------------------------------
# Script setup
# ---------------------------------------------------------------------------

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "${SCRIPT_DIR}/../src/brew_deps.sh"


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
# Homebrew configuration
# ---------------------------------------------------------------------------

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

BREW="/opt/homebrew/bin/brew"


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
# Homebrew information
# ---------------------------------------------------------------------------

echo "Using native ARM64 Homebrew:"
"${BREW}" --version

echo "Homebrew configuration:"
"${BREW}" config


# ---------------------------------------------------------------------------
# Update Homebrew
# ---------------------------------------------------------------------------
#
# We intentionally do NOT run `brew upgrade`.
#
# The build should not unexpectedly upgrade dependencies between CI runs.
#
# `brew update` only refreshes the formula metadata. The actual dependency
# versions are controlled by the formulas installed below, with nng pinned
# explicitly.

echo "Updating Homebrew..."
"${BREW}" update


# ---------------------------------------------------------------------------
# Install normal KiCad dependencies
# ---------------------------------------------------------------------------
#
# nng is intentionally NOT included here.
#
# It is installed separately from the pinned 1.12.0 formula below so that
# both ARM64-native and x86_64-under-Rosetta builds use the same nng version.
#

echo "Installing KiCad dependencies..."

BREW_DEPS_WITHOUT_NNG=()

for dep in "${BREW_DEPS[@]}"; do
  if [ "$dep" != "nng" ]; then
    BREW_DEPS_WITHOUT_NNG+=("$dep")
  fi
done

"${BREW}" install "${BREW_DEPS_WITHOUT_NNG[@]}"


# ---------------------------------------------------------------------------
# Install known-good nng 1.12.0
# ---------------------------------------------------------------------------

NNG_COMMIT="58656612e45244656656414088afd240fd85de08"
NNG_FORMULA_URL="https://raw.githubusercontent.com/Homebrew/homebrew-core/${NNG_COMMIT}/Formula/n/nng.rb"

NNG_TAP="huaqiu/nng-pin"

echo "Preparing pinned nng 1.12.0..."
echo "  Commit:  ${NNG_COMMIT}"
echo "  Formula: ${NNG_FORMULA_URL}"


# ---------------------------------------------------------------------------
# Create temporary/local Homebrew tap
# ---------------------------------------------------------------------------

if ! "${BREW}" tap | grep -q "^${NNG_TAP}$"; then
  echo "Creating temporary Homebrew tap: ${NNG_TAP}"

  "${BREW}" tap-new "${NNG_TAP}"
fi


# ---------------------------------------------------------------------------
# Install pinned nng formula
# ---------------------------------------------------------------------------

NNG_TAP_PATH="$(
  "${BREW}" --repository
)/Library/Taps/huaqiu/homebrew-nng-pin"

NNG_FORMULA_PATH="${NNG_TAP_PATH}/Formula/nng.rb"


echo "Installing pinned nng formula:"
echo "  ${NNG_FORMULA_PATH}"

curl -fsSL \
  "${NNG_FORMULA_URL}" \
  -o "${NNG_FORMULA_PATH}"


echo "Installing nng 1.12.0..."

"${BREW}" install "${NNG_TAP}/nng"


# ---------------------------------------------------------------------------
# Verify nng
# ---------------------------------------------------------------------------

echo "Installed nng version:"
"${BREW}" list --versions nng

echo "nng information:"
"${BREW}" info nng


# ---------------------------------------------------------------------------
# Clean up Homebrew
# ---------------------------------------------------------------------------

echo "Cleaning up Homebrew..."

"${BREW}" cleanup -s


# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

echo "Done!"