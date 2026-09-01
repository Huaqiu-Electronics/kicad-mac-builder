#!/bin/bash

set -euo pipefail

# Print out details of the environment, and verify that the ARM64 and x86_64
# Homebrew installs expose the *same* version for every BREW_DEPS entry.
#
# This is the strict dependency verification described in
# docs/gradually-stabilize-homebrew-deps.md section 6: the build is failed
# whenever ARM64 and x86_64 disagree on a dependency version.
#
# Section 12: a formula with multiple historical kegs (e.g. "openssl@3 3.6.4
# 3.6.2") is *not* by itself a dependency mismatch -- what matters is the
# version Homebrew actually hands to the build (the first version token
# returned by `brew list --versions`). The full keg list is still surfaced
# for visibility.
#
# Section 14: the ci/src/brew_versions.sh baseline (the 2026-07-23
# known-good versions) is also compared. Baseline drift is informational
# only -- it does not fail the build, because the spec is "evidence-driven"
# (section 9): a single drift on both architectures is fine as long as the
# two architectures agree. The hard invariant remains ARM64 == x86_64.
#
# If you have installed some of the dependencies outside of Homebrew or in a
# weird way, this script might not work right :)

BOTH_BREWS=0

if [ $# -gt 0 ]; then
  if [ "$1" == "--both" ]; then
    BOTH_BREWS=1
  else
    BOTH_BREWS=0
  fi
fi

echo "PATH: ${PATH}"
echo "MacOS version: $(sw_vers -productVersion | cut -d. -f1-2)"
echo "Host architecture (cpu.brand_string): $(sysctl -n machdep.cpu.brand_string)"
echo "'arch': $(arch)"
echo "which brew: $(which brew)"
echo "which python3: $(which python3)"
echo "python3 --version: $(python3 --version)"
echo ""
echo "Dependencies:"
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source "${SCRIPT_DIR}/brew_deps.sh"
# Section 14: load the known-good version baseline. Sourced optionally so a
# missing file does not break the strict arch-vs-arch check.
#
# brew_versions.sh uses parallel indexed arrays + a `brew_version_of` helper
# (NOT an associative array) so it works under macOS's default bash 3.2.
# Lookups below go through `brew_version_of` for the same reason.
if [ -f "${SCRIPT_DIR}/brew_versions.sh" ]; then
  source "${SCRIPT_DIR}/brew_versions.sh"
else
  echo "WARNING: ${SCRIPT_DIR}/brew_versions.sh not found; baseline check disabled."
fi

# Extract the active version (first version token after the formula name)
# from a `brew list --versions <formula>` line. Returns "" if input is empty.
active_version() {
  # `brew list --versions openssl@3` -> "openssl@3 3.6.3"
  # multi-keg: "openssl@3 3.6.4 3.6.2" -> active version is the first token
  # after the formula name, i.e. "3.6.4".
  awk '{ print $2 }' <<<"$1"
}

ISSUES=""
WARNINGS=""

for dep in "${BREW_DEPS[@]}"; do
  echo ""
  if [ "$BOTH_BREWS" -eq 1 ]; then

    set +e
    arm64_version=$(/opt/homebrew/bin/brew list --version "$dep") # does this die if error?
    x86_64_version=$(arch -x86_64 /usr/local/bin/brew list --version "$dep")
    set -e


    if [ -z "$arm64_version" ]; then
      ISSUES="${ISSUES}arm64 version of $dep not installed\n"
    fi

    if [ -z "$x86_64_version" ]; then
      ISSUES="${ISSUES}x86_64 version of $dep not installed\n"
    fi

    arm64_active=$(active_version "$arm64_version")
    x86_64_active=$(active_version "$x86_64_version")

    # Strict invariant (section 6/17): the active version Homebrew hands to
    # the build MUST match between architectures.
    if [ -n "$arm64_active" ] && [ -n "$x86_64_active" ] \
       && [ "$arm64_active" != "$x86_64_active" ]; then
      ISSUES="${ISSUES}Version mismatch for $dep between arm64 and x86_64\n"
    fi

    # Section 12: multiple kegs alone are not a mismatch, but they are
    # surfaced as a warning so they can be cleaned up for reproducibility.
    arm64_extra_kegs=$(awk '{ print NF - 2 }' <<<"$arm64_version")
    x86_64_extra_kegs=$(awk '{ print NF - 2 }' <<<"$x86_64_version")
    if [ "${arm64_extra_kegs:-0}" -gt 0 ] 2>/dev/null; then
      WARNINGS="${WARNINGS}arm64 $dep has $arm64_extra_kegs extra historical keg(s): ${arm64_version#* }\n"
    fi
    if [ "${x86_64_extra_kegs:-0}" -gt 0 ] 2>/dev/null; then
      WARNINGS="${WARNINGS}x86_64 $dep has $x86_64_extra_kegs extra historical keg(s): ${x86_64_version#* }\n"
    fi

    # Section 14 baseline check (informational only).
    baseline_status="no-baseline"
    if baseline_version=$(brew_version_of "$dep"); then
      if [ "$arm64_active" = "$baseline_version" ] \
         && [ "$x86_64_active" = "$baseline_version" ]; then
        baseline_status="baseline-OK"
      else
        baseline_status="baseline-DRIFT (expected ${baseline_version})"
        WARNINGS="${WARNINGS}$dep drifted from July-23 baseline (expected ${baseline_version}, got arm64=${arm64_active:-<none>} x86_64=${x86_64_active:-<none>})\n"
      fi
    fi

    # Per-dep status line (section 8 expected output format).
    if [ -n "$arm64_active" ] && [ -n "$x86_64_active" ] \
       && [ "$arm64_active" = "$x86_64_active" ]; then
      status="OK"
    else
      status="MISMATCH"
    fi

    echo "arm64: $arm64_version"
    echo "x86_64: $x86_64_version"
    echo "status: $status ($baseline_status)"
  else
    set +e
    version=$(brew list --version "$dep")
    set -e
    echo "$version"
    if [ -z "$version" ]; then
      ISSUES="${ISSUES}Homebrew at $(which brew) says $dep not installed\n"
    fi
  fi
done

echo ""

if [ -n "$WARNINGS" ]; then
  echo "Dependency warnings (non-blocking, evidence for next pinning round):"
  echo -e "$WARNINGS"
  echo
fi

if [ -n "$ISSUES" ]; then
  echo "Dependency issues detected:"
  echo -e "$ISSUES"
  echo "Exiting."
  exit 1
else
  echo "Dependency verification: PASS"
  echo "Done."
  exit 0
fi
