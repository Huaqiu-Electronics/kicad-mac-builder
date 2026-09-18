#!/bin/bash
set -x
set -e

# Easy hack to get a timeout command
function timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "${SCRIPT_DIR}/../src/brew_deps.sh"

for _ in 1 2 3; do
  if ! command -v brew >/dev/null; then
    echo "Installing Homebrew ..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)" < /dev/null
  else
    echo "Homebrew installed."
    break
  fi
done

PATH=$PATH:/usr/local/bin
export HOMEBREW_NO_ANALYTICS=1

echo "Updating Homebrew..."
brew update

echo "Updating SSH"
brew install openssh || true

echo "Installing some dependencies"

# ---------------------------------------------------------------------------
# x86_64 macOS (Intel) is Tier 3 in homebrew-core. Several critical formulas
# no longer ship prebuilt bottles for this architecture. The three formulas
# below are the root-level "no bottle available!" failures that would
# otherwise cascade into failures for their transitive dependents
# (opencascade, harfbuzz, cairo, wget, libgit2, swig, nng).
# Force them to build from source BEFORE the bulk install so that the rest
# of BREW_DEPS can resolve their dependencies from bottles normally.
# ---------------------------------------------------------------------------
brew install --build-from-source openssl@3 || true
brew install --build-from-source nng       || true
brew install --build-from-source pcre2     || true

# Bulk install / upgrade of the remaining BREW_DEPS. || true keeps the
# script progressing past transient batch-install issues; the authoritative
# dependency gate is ci/src/make-build-with-refs.sh which runs afterwards
# and will abort the build if anything is truly missing.
brew install "${BREW_DEPS[@]}" || true
brew upgrade "${BREW_DEPS[@]}" || true

# Reclaim disk space from the Homebrew cache before the heavy build step.
brew cleanup -s

echo "Done."
