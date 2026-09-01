#!/bin/bash

# Shared Homebrew dependency version baseline.
#
# Source of truth: docs/success_run.log (GitHub Actions run dated 2026-07-23
# that produced matching ARM64/x86_64 dependency versions and a successful
# universal KiCad bundle).
#
# Per docs/gradually-stabilize-homebrew-deps.md section 14 this file is
# primarily a *verification baseline*. It is consumed by ci/src/watermark.sh
# to flag drift from the known-good versions. It is NOT a hard install lock:
# the bootstrap scripts still install dependencies through normal Homebrew and
# only pin a formula when verification shows an architecture mismatch.
#
# Only add an entry here once the corresponding version has actually been
# reproduced on both architectures in CI; do not pre-populate speculative
# pins (section 9, "evidence-driven").
#
# Implementation note: macOS ships bash 3.2 as /bin/bash, which does NOT
# support `declare -A` (associative arrays). This file therefore uses two
# parallel indexed arrays -- BREW_VERSION_FORMULAS and BREW_VERSION_VALUES --
# and a helper `brew_version_of <formula>` for lookups. Indexed arrays are
# supported by bash 3.2.

# Parallel indexed arrays of (formula, expected-version) pairs.
#
# Order matters: BREW_VERSION_FORMULAS[i] pairs with
# BREW_VERSION_VALUES[i]. The version string is the first token returned
# by `brew list --versions <formula>` after the formula name (e.g.
# "openssl@3 3.6.3" -> "3.6.3").
BREW_VERSION_FORMULAS=(
  glew
  bison
  opencascade
  glm
  boost
  harfbuzz
  cairo
  doxygen
  gettext
  wget
  libgit2
  libtool
  autoconf
  automake
  swig
  "openssl@3"
  unixodbc
  ninja
  protobuf
  nng
  zstd
  libomp
)

BREW_VERSION_VALUES=(
  "2.3.1"
  "3.8.2"
  "7.9.3"
  "1.0.3"
  "1.90.0_1"
  "14.2.1"
  "1.18.4"
  "1.17.0"
  "1.0"
  "1.25.0"
  "1.9.6"
  "2.6.2"
  "2.73"
  "1.18.1_1"
  "4.4.1"
  "3.6.3"
  "2.3.14"
  "1.13.2"
  "35.1"
  "1.12.0"
  "1.5.7_1"
  "22.1.8"
)

# Look up the expected version for a formula in the baseline above.
# Echoes the version string, or returns non-zero if the formula has no
# baseline entry. Safe to call under `set -u`.
brew_version_of() {
  local formula="$1"
  local i
  local count=${#BREW_VERSION_FORMULAS[@]}
  for (( i = 0; i < count; i++ )); do
    if [ "${BREW_VERSION_FORMULAS[i]}" = "${formula}" ]; then
      echo "${BREW_VERSION_VALUES[i]}"
      return 0
    fi
  done
  return 1
}
