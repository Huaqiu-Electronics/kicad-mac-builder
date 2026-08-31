#!/bin/bash

set -x
set -e

# This script helps you set up an M1 Mac to build the x86_64 version of KiCad.
# This is not intended to be the complete answer to "M1 support".
#
# Notes:
#
# If you are on an Mx Mac, /usr/local/bin/brew is for x86_64 things, and the
# default M1-y Homebrew is in /opt/homebrew.
#
# Many folks would only need the M1-y Homebrew, but if you are building
# x86_64 KiCad on an M1 Mac you are not most folks.
#
# One way of handling this multiverse of madness is to have the M1-y Homebrew
# in your path first. When you type `brew`, it means the M1 Homebrew.
# If you need to use the x86_64 Homebrew, run:
#
#   arch -x86_64 /usr/local/bin/brew
#
# After running this script, you could set up CLion, for instance, with:
#
#   arch -x86_64 ./build.py --target setup-kicad-dependencies
#
# checking out KiCad, opening it in Intel CLion (I am not sure if the Apple
# Silicon CLion will work), copying the CMake arguments in, and then doing
# Build > Install in CLion.
#
# To do a regular package build using kicad-mac-builder, you'll need to
# install dyldstyle to get wrangle-bundle, which you can do with:
#
#   ci/src/get-wrangle-bundle.sh
#
# Add it to your PATH, so `wrangle-bundle` works at the CLI.
#
# Then you can use build.py like:
#
#   arch -x86_64 ./build.py --target kicad


SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "${SCRIPT_DIR}/../src/brew_deps.sh"


# ---------------------------------------------------------------------------
# Check Rosetta 2
# ---------------------------------------------------------------------------

echo "Checking for Rosetta 2..."

if pgrep -q oahd; then
  echo "Rosetta 2 is installed."
else
  echo "Rosetta 2 is not installed."
  echo "You'll need to install it. One way is with:"
  echo "/usr/sbin/softwareupdate --install-rosetta"
  exit 1
fi


# ---------------------------------------------------------------------------
# Install x86_64 Homebrew if necessary
# ---------------------------------------------------------------------------

if [ ! -e /usr/local/bin/brew ]; then
  echo "Installing x86_64 Homebrew..."

  arch -x86_64 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)" \
    < /dev/null
fi


# ---------------------------------------------------------------------------
# Homebrew configuration
# ---------------------------------------------------------------------------

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

BREW="/usr/local/bin/brew"

echo "Using x86_64 Homebrew:"
arch -x86_64 "${BREW}" --version

echo "Homebrew configuration:"
arch -x86_64 "${BREW}" config


# ---------------------------------------------------------------------------
# Update x86_64 Homebrew
# ---------------------------------------------------------------------------
#
# We intentionally do NOT run `brew upgrade`.
#
# The build should not unexpectedly upgrade dependencies between CI runs.
#

echo "Updating Homebrew..."
arch -x86_64 "${BREW}" update


# ---------------------------------------------------------------------------
# Install normal KiCad dependencies
# ---------------------------------------------------------------------------
#
# nng is intentionally NOT included in BREW_DEPS.
#
# The current nng 1.12.4 formula has no compatible bottle for this
# x86_64-under-Rosetta / macOS 14 environment.
#
# We instead install the known-good nng 1.12.0 formula from:
#
#   homebrew-core commit:
#   58656612e45244656656414088afd240fd85de08
#
# "nng: update 1.12.0 bottle"
#
# This is the version used by the previously successful KiCad build.
#

echo "Installing KiCad dependencies..."

BREW_DEPS_WITHOUT_NNG=()

for dep in "${BREW_DEPS[@]}"; do
  if [ "$dep" != "nng" ]; then
    BREW_DEPS_WITHOUT_NNG+=("$dep")
  fi
done

arch -x86_64 "${BREW}" install "${BREW_DEPS_WITHOUT_NNG[@]}"

echo "Installing pinned nng 1.12.0..."

# historical nng installation follows...


# ---------------------------------------------------------------------------
# Install known-good nng 1.12.0
# ---------------------------------------------------------------------------

NNG_COMMIT="58656612e45244656656414088afd240fd85de08"
NNG_FORMULA_URL="https://raw.githubusercontent.com/Homebrew/homebrew-core/${NNG_COMMIT}/Formula/n/nng.rb"
NNG_FORMULA_PATH="$(mktemp "${TMPDIR:-/tmp}/nng.XXXXXX.rb")"

echo "Preparing nng 1.12.0 from homebrew-core commit ${NNG_COMMIT}..."
echo "Formula: ${NNG_FORMULA_URL}"

# Download the historical formula.
curl -fsSL \
  "${NNG_FORMULA_URL}" \
  -o "${NNG_FORMULA_PATH}"

echo "Downloaded historical nng formula:"
cat "${NNG_FORMULA_PATH}"

# Install the historical formula.
#
# Homebrew no longer accepts the raw GitHub URL directly as a formula
# argument, so download it first and install the local formula file.
echo "Installing pinned nng 1.12.0..."

arch -x86_64 "${BREW}" install "${NNG_FORMULA_PATH}"

# Verify the installed version.
echo "Installed nng version:"
arch -x86_64 "${BREW}" list --versions nng

echo "nng information:"
arch -x86_64 "${BREW}" info nng

# Remove temporary formula.
rm -f "${NNG_FORMULA_PATH}"


# Verify the installed version.
echo "Installed nng version:"
arch -x86_64 "${BREW}" list --versions nng

echo "nng information:"
arch -x86_64 "${BREW}" info nng


# ---------------------------------------------------------------------------
# Clean up Homebrew
# ---------------------------------------------------------------------------

echo "Cleaning up Homebrew..."

arch -x86_64 "${BREW}" cleanup -s


echo "Done!"