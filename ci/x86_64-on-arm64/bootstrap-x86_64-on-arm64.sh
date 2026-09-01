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
# Strategy (docs/gradually-stabilize-homebrew-deps.md):
#
#   * Use normal Homebrew (`arch -x86_64 /usr/local/bin/brew update` +
#     `arch -x86_64 /usr/local/bin/brew install`) for all KiCad dependencies.
#     This mirrors the 2026-07-23 known-good GitHub Actions run
#     (docs/success_run.log), which did NOT pin the homebrew/core repository
#     and still produced matching ARM64/x86_64 versions.
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
#   * Git is intentionally NOT executed through Rosetta. GitHub Actions'
#     Apple Silicon runners provide a native ARM64 Git, which can operate on
#     the x86_64 Homebrew checkout without any problem.
#
#   * Homebrew itself is always executed through Rosetta
#     (`arch -x86_64 /usr/local/bin/brew ...`). Per section 13, do NOT wrap
#     the `arch`/`machine` reporting utilities themselves in Rosetta.

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

BREW="/usr/local/bin/brew"

# Pin openssl@3 to the 2026-07-23 known-good version (3.6.3).
#
# This is the ONLY formula currently pinned, because it is the only observed
# architecture mismatch (section 10). Other formulas remain on the normal
# Homebrew API install path until/unless verification shows another mismatch.
#
# The commit below is the homebrew/core revision that carried the 3.6.3
# bottle active on 2026-07-23 ("openssl@3: update 3.6.3 bottle.").
OPENSSL_PIN_FORMULA="openssl@3"
# Use the brew_version_of helper from brew_versions.sh -- it is bash 3.2
# compatible (parallel indexed arrays), whereas ${BREW_VERSIONS[...]}
# associative-array syntax is not supported by macOS's /bin/bash.
OPENSSL_PIN_VERSION="$(brew_version_of "${OPENSSL_PIN_FORMULA}")"
OPENSSL_PIN_COMMIT="afd93f1b5d40319fef3976408e83f0b232de81ac"
OPENSSL_PIN_URL="https://raw.githubusercontent.com/Homebrew/homebrew-core/${OPENSSL_PIN_COMMIT}/Formula/o/openssl%403.rb"


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
#
# Per section 13: do NOT use `arch -x86_64 arch` to report the host
# architecture -- it produces "Can't find any plists for arch". Use the
# host's native `arch`/`machine` instead.
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

echo "Using x86_64 Homebrew:"
arch -x86_64 "${BREW}" --version

echo "Homebrew configuration:"
arch -x86_64 "${BREW}" config


# ---------------------------------------------------------------------------
# Update Homebrew (matches known-good run)
# ---------------------------------------------------------------------------

echo "Updating Homebrew..."
arch -x86_64 "${BREW}" update


# ---------------------------------------------------------------------------
# Install KiCad dependencies (normal Homebrew path)
# ---------------------------------------------------------------------------

echo "Installing KiCad dependencies..."
echo "Dependencies:"
printf '  %s\n' "${BREW_DEPS[@]}"

arch -x86_64 "${BREW}" install "${BREW_DEPS[@]}"


# ---------------------------------------------------------------------------
# Pin openssl@3 to the known-good version
# ---------------------------------------------------------------------------
#
# This is the only formula currently pinned, justified by the observed
# architecture mismatch (section 10). All other formulas rely on the normal
# Homebrew install above until CI verification shows another mismatch.
#
# The pin uses the historical Homebrew formula file from the homebrew/core
# commit that carried the desired 3.6.3 bottle. HOMEBREW_NO_INSTALL_FROM_API
# is set only for this install so the local .rb file is honoured.
#
# If the bottle is no longer downloadable, the install will fall back to a
# source build; that source build needs the Patches/ files from the
# homebrew/core checkout, which a URL install cannot provide. If we ever
# hit that case, switch to a small vendored tap (section 9, second choice).
# Until CI shows that failure, the URL install is the smallest mechanism.

echo "Pinning ${OPENSSL_PIN_FORMULA} to ${OPENSSL_PIN_VERSION}..."

CURRENT_OPENSSL_VERSION="$(
  arch -x86_64 "${BREW}" list --versions "${OPENSSL_PIN_FORMULA}" 2>/dev/null \
    | awk '{print $2}'
)"

echo "  current ${OPENSSL_PIN_FORMULA} version: ${CURRENT_OPENSSL_VERSION:-<none>}"
echo "  desired ${OPENSSL_PIN_FORMULA} version: ${OPENSSL_PIN_VERSION}"

if [ "${CURRENT_OPENSSL_VERSION}" = "${OPENSSL_PIN_VERSION}" ]; then
  echo "  already at ${OPENSSL_PIN_VERSION}; nothing to do."
else
  if [ -n "${CURRENT_OPENSSL_VERSION}" ]; then
    echo "  uninstalling existing ${OPENSSL_PIN_FORMULA} ${CURRENT_OPENSSL_VERSION}..."
    arch -x86_64 "${BREW}" uninstall --ignore-dependencies "${OPENSSL_PIN_FORMULA}" || true
  fi

  echo "  installing historical formula from:"
  echo "    ${OPENSSL_PIN_URL}"

  HOMEBREW_NO_INSTALL_FROM_API=1 \
    arch -x86_64 "${BREW}" install "${OPENSSL_PIN_URL}"
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

  arch -x86_64 "${BREW}" list --versions "${dep}" || true
done


# ---------------------------------------------------------------------------
# Explicitly verify openssl@3 (the only currently pinned formula)
# ---------------------------------------------------------------------------

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
echo "Done!"
