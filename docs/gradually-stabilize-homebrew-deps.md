# Task Spec — Gradually Stabilize Homebrew Dependencies for Universal KiCad Build

**Status:** IMPLEMENTATION TASK\
**Priority:** Delivery first\
**Principle:** No over-engineering; make the smallest change that restores reproducible ARM64/x86\_64 dependencies.

## 1. Objective

Stabilize the macOS universal KiCad build so that the ARM64 and x86\_64 build environments use **exactly the same Homebrew dependency versions** before producing the final universal bundle with `lipo`.

The current problem is that the two architectures can resolve different versions from Homebrew.

Example:

```text
ARM64:
openssl@3 3.6.4 3.6.2

x86_64:
openssl@3 3.6.2
```

This must fail because the final universal build requires the dependency versions to match.

Do **not** weaken the existing version comparison.

***

## 2. Known-good baseline

A previously successful GitHub Actions run is available locally:

```text
/Users/admin/code/kicad-mac-builder/docs/success_run.log
```

The successful run was on **2026-07-23** and produced matching dependency versions for ARM64 and x86\_64.

Use this file as the authoritative starting point for the dependency versions.

Known-good versions extracted from that run:

```text
glew         2.3.1
bison        3.8.2
opencascade  7.9.3
glm          1.0.3
boost        1.90.0_1
harfbuzz     14.2.1
cairo        1.18.4
doxygen      1.17.0
gettext      1.0
wget         1.25.0
libgit2      1.9.6
libtool      2.6.2
autoconf     2.73
automake     1.18.1_1
swig         4.4.1
openssl@3    3.6.3
unixodbc     2.3.14
ninja        1.13.2
protobuf     35.1
nng          1.12.0
zstd         1.5.7_1
libomp       22.1.8
```

The complete successful log must be inspected rather than assuming this list is complete.

***

## 3. Important historical observation

The successful July 23 run did **not** explicitly pin Homebrew Core.

It used:

```text
brew update
brew install glew bison opencascade ...
```

and Homebrew resolved:

```text
openssl@3 3.6.3
nng        1.12.0
```

for both architectures.

Therefore, do **not** immediately introduce a large Homebrew Core pinning mechanism.

The goal is to reproduce the known-good dependency versions with the smallest possible change.

***

# 4. Current bootstrap architecture

There are two bootstrap scripts:

```text
bootstrap/bootstrap-arm64-on-arm64
bootstrap/bootstrap-x86_64-on-arm64
```

Both source:

```text
src/brew_deps.sh
```

The x86\_64 script runs Homebrew under Rosetta:

```bash
arch -x86_64 /usr/local/bin/brew
```

The ARM64 script uses:

```text
/opt/homebrew/bin/brew
```

Keep this architecture model.

Do not introduce Docker, Nix, Conda, Bazel, a custom package manager, or another dependency-management framework.

***

# 5. Required strategy: gradual stabilization

Do **not** attempt to lock all 22 dependencies immediately.

Instead use the following loop:

```text
1. Start from normal Homebrew installation.
2. Run both architectures.
3. Compare dependency versions.
4. Identify the first mismatch.
5. Pin/fix only that dependency.
6. Run GitHub Actions again.
7. Compare again.
8. Repeat only if another mismatch remains.
```

This is intentional.

The objective is to discover the **minimum set of dependencies that actually require pinning**.

***

# 6. Preserve strict dependency verification

The existing verification must remain strict.

For every dependency in:

```bash
BREW_DEPS
```

the CI must print:

```text
arm64: <formula> <version>
x86_64: <formula> <version>
```

and fail when they differ.

Example:

```text
arm64: openssl@3 3.6.4
x86_64: openssl@3 3.6.2

Dependency issues detected:
Version mismatch for openssl@3 between arm64 and x86_64

Exiting.
```

Do not change this behavior to allow version differences.

***

# 7. First implementation step

Before changing dependency installation, inspect:

```text
/Users/admin/code/kicad-mac-builder/docs/success_run.log
```

Determine:

1. exact Homebrew version;
2. Homebrew Core state if available;
3. exact formula versions;
4. whether any formulas were explicitly pinned;
5. whether historical formulas were used;
6. whether Homebrew downloaded bottles or built from source;
7. any relevant environment variables;
8. the exact dependency installation commands.

Do not infer these values when they can be obtained from the log.

***

# 8. First GitHub verification

After inspection, make the smallest bootstrap change possible.

Run the GitHub Actions workflow.

The first objective is simply to establish the current delta against the July 23 baseline.

Expected output should clearly show something like:

```text
Dependency version comparison

glew:
  arm64:   2.3.1
  x86_64:  2.3.1
  status:  OK

...

openssl@3:
  arm64:   3.6.4
  x86_64:  3.6.2
  status:  MISMATCH

...

nng:
  arm64:   1.12.0
  x86_64:  1.12.0
  status:  OK
```

Do not modify dependencies that already match.

***

# 9. Pinning policy

When a dependency differs:

### First choice

Use the simplest Homebrew-native mechanism that can install the required historical version.

Prefer:

```text
historical Homebrew formula
```

over introducing new infrastructure.

### Second choice

If Homebrew cannot install the required version directly because the historical formula is no longer available, pin only that formula using a small local/internal tap or equivalent minimal mechanism.

### Do not

- create a general dependency manager;

- vendor all Homebrew formulas;

- freeze the entire Homebrew repository without evidence that it is necessary;

- add a lockfile system for transitive dependencies;

- manually maintain 22 formula revisions before they are needed;

- change the successful build architecture;

- weaken version validation.

***

# 10. Special case: openssl\@3

The first known mismatch is:

```text
ARM64:   openssl@3 3.6.4
x86_64:  openssl@3 3.6.2
```

The known-good July 23 version was:

```text
openssl@3 3.6.3
```

Therefore the desired result is:

```text
ARM64:   openssl@3 3.6.3
x86_64:  openssl@3 3.6.3
```

Do not simply accept 3.6.4 on ARM64 or 3.6.2 on x86\_64.

Investigate the July 23 log and determine the smallest reliable way to obtain 3.6.3.

Pin **only openssl\@3** initially.

Then run GitHub Actions again.

***

# 11. Special case: nng

The current build has already demonstrated that:

```text
nng 1.12.0
```

is available and matching on both architectures.

The existing pinned nng approach may therefore be retained if it is required by the current Homebrew state.

Do not redesign nng unless the verification demonstrates a mismatch.

***

# 12. Handling multiple installed versions

Do not consider multiple historical kegs alone to be a dependency mismatch.

For example:

```text
openssl@3 3.6.4 3.6.2
```

requires determining which version Homebrew is actually providing to the build.

However, for CI reproducibility, prefer a clean environment and avoid leaving unintended versions active.

The final verification must represent the version actually used by the build.

If the implementation needs to remove an unwanted version, keep the cleanup targeted.

Do not introduce a generalized keg-management framework.

***

# 13. Architecture verification

Do not use:

```bash
arch -x86_64 arch
```

This is invalid and previously caused:

```text
arch: Can't find any plists for arch
```

For the x86\_64 Homebrew environment use:

```bash
arch -x86_64 /usr/local/bin/brew ...
```

For reporting architecture, use appropriate existing system information such as:

```bash
machine
arch
```

without wrapping the `arch` utility itself in Rosetta.

***

# 14. Shared version baseline

Once the actual dependency versions are confirmed from the successful log, it is acceptable to add a small shared version declaration such as:

```text
src/brew_versions.sh
```

Example:

```bash
declare -A BREW_VERSIONS=(
  [glew]="2.3.1"
  [bison]="3.8.2"
  [opencascade]="7.9.3"
  ...
  [openssl@3]="3.6.3"
  ...
  [nng]="1.12.0"
)
```

However, this file is primarily a **verification baseline** initially.

Do not make all 22 dependencies manually version-installed unless GitHub verification shows that this is necessary.

***

# 15. Success criteria

The task is complete when the GitHub Actions runner produces:

```text
arm64: glew 2.3.1
x86_64: glew 2.3.1

arm64: bison 3.8.2
x86_64: bison 3.8.2

...

arm64: openssl@3 3.6.3
x86_64: openssl@3 3.6.3

...

arm64: nng 1.12.0
x86_64: nng 1.12.0

...

Dependency issues detected:
(none)

Dependency verification: PASS
```

and the universal KiCad build proceeds successfully.

***

# 16. Deliverables

Produce:

1. Updated `bootstrap-arm64-on-arm64`.
2. Updated `bootstrap-x86_64-on-arm64`.
3. Any minimal shared version information required.
4. Any minimal pinned formula/tap changes required.
5. Updated dependency verification.
6. A short document or commit message explaining:

   - the July 23 known-good versions;

   - which dependencies actually required pinning;

   - why each pin was necessary;

   - confirmation that ARM64/x86\_64 versions match.

Do not add infrastructure that is not required by the observed GitHub runner failures.

***

# 17. Engineering constraints

### Delivery first

Prefer a small, understandable shell-script solution.

### No over-engineering

Do not implement a complete Homebrew lockfile/package manager.

### Evidence-driven

Every new pin should be justified by an actual architecture mismatch or inability to reproduce the known-good version.

### Gradual verification

After every meaningful dependency change:

```text
commit
→ GitHub Actions
→ inspect versions
→ fix next mismatch
```

Do not make a large speculative change covering all dependencies.

### Preserve the final invariant

The invariant is non-negotiable:

```text
ARM64 dependency version == x86_64 dependency version
```

for every dependency that participates in the KiCad build/bundle.

***

# 18. Final expected architecture

The intended solution should remain simple:

```text
                 brew_deps.sh
                      │
                      ▼
             normal Homebrew install
                      │
             ┌────────┴────────┐
             │                 │
          ARM64             x86_64
             │                 │
             └────────┬────────┘
                      ▼
             dependency comparison
                      │
             ┌────────┴────────┐
             │                 │
           MATCH            MISMATCH
             │                 │
             ▼                 ▼
          continue       pin ONLY affected
                              formula
                                 │
                                 └────→ GitHub Actions
                                             │
                                             └────→ repeat
```

The final solution should be the **smallest set of pins necessary to make the two architectures converge**, based on actual GitHub runner evidence.

***

# 19. Implementation Summary (first pass)

This section records the first-pass implementation described above. It is
intentionally short and is meant to be read alongside the diff for the
files listed in section 16 (Deliverables).

## 19.1 Findings from `docs/success_run.log` (section 7)

Inspection of the 2026-07-23 known-good GitHub Actions run:

1. **Homebrew version** — `brew --version` output is not explicitly captured
   in the log. The runner installed Homebrew from
   `https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh`
   (lines 1939-1947), so it was the latest Homebrew as of 2026-07-23.
   `portable-ruby-4.0.6` was poured during install (line 1945), which
   matches that era of Homebrew 4.x.
2. **Homebrew Core state** — **not pinned**. The run used the standard
   Homebrew JSON API (`packages.sonoma.jws.json`). There is no
   `HOMEBREW_NO_INSTALL_FROM_API`, no `git -C ... checkout` of
   `homebrew/core`, and no tap pinning anywhere in the log.
3. **Exact formula versions** — listed in section 2 of this doc and
   confirmed by the `Pouring <formula>--<version>...bottle.tar.gz` lines
   in the log (e.g. `openssl@3--3.6.3.arm64_sonoma.bottle.1.tar.gz` at
   line 559 for ARM64, `openssl@3--3.6.3.sonoma.bottle.1.tar.gz` at line
   2242 for x86\_64). The final `watermark.sh --both` output at lines
   2742-2806 shows matching versions on both architectures.
4. **Explicitly pinned formulas** — **none**. No formula was pinned by
   name, version, or commit.
5. **Historical formulas used** — **none**. Every formula came from the
   current Homebrew API on 2026-07-23.
6. **Bottles vs source** — **bottles**. Every KiCad dependency was poured
   from a pre-built bottle (the `Pouring <formula>--<version>...bottle`
   lines). No source builds occurred.
7. **Relevant environment variables** — only `HOMEBREW_NO_ANALYTICS=1`
   was set (line 1966 for the x86\_64 bootstrap; the ARM64 bootstrap used
   the runner's default environment with `HOMEBREW_NO_ANALYTICS` set
   implicitly via the bootstrap).
8. **Exact dependency installation commands**:

   - ARM64: `brew update` then `brew install glew bison opencascade glm
     boost harfbuzz cairo doxygen gettext wget libgit2 libtool autoconf
     automake swig openssl unixodbc ninja protobuf nng zstd libomp`
     (line 391 onwards; the `+ brew install ...` line is hidden by the
     runner's redaction but the dependency list and the per-formula
     "already installed" warnings at lines 638-659 confirm it).

   - x86\_64: `arch -x86_64 /usr/local/bin/brew update` then
     `arch -x86_64 /usr/local/bin/brew install glew bison opencascade glm
     boost harfbuzz cairo doxygen gettext wget libgit2 libtool autoconf
     automake swig openssl unixodbc ninja protobuf nng zstd libomp`
     (line 1975).

The July 23 run is therefore a plain "normal Homebrew" install. There is
no evidence that pinning the entire `homebrew/core` repository is
required to reproduce it.

## 19.2 Smallest change made (section 5 / 9)

The previous bootstrap scripts pinned the **entire** `homebrew/core`
repository to a single commit (`CORE_COMMIT`) via
`HOMEBREW_NO_INSTALL_FROM_API=1` plus a `git -C ... checkout --detach`
in the locally-tapped `homebrew/core`. That was over-engineering: it
froze all 22 KiCad dependencies (and their transitive closure) without
evidence that any of them beyond `openssl@3` and `nng` actually needed
freezing (section 9 "Do not ... freeze the entire Homebrew repository
without evidence that it is necessary").

The first-pass implementation removes that whole-repo pin and replaces
it with:

- **Normal Homebrew install** for all `BREW_DEPS`, mirroring the July 23
  known-good run exactly: `brew update` then `brew install <deps>`.
  Only `HOMEBREW_NO_ANALYTICS=1` is exported globally, matching the
  known-good environment.

- **A targeted** **`openssl@3`** **pin** for the only formula with an observed
  architecture mismatch (section 10: ARM64 3.6.4 vs x86\_64 3.6.2,
  known-good 3.6.3). The pin uses the smallest Homebrew-native
  mechanism available (section 9, first choice): the historical formula
  `.rb` file checked into `homebrew/core` at a commit that carried the
  desired bottle. `HOMEBREW_NO_INSTALL_FROM_API=1` is set only for that
  one install command, not globally.

## 19.3 Files changed (section 16 deliverables)

1. **`ci/arm64-on-arm64/bootstrap-arm64-on-arm64.sh`** — rewrote to drop
   the `homebrew/core` pin entirely. Now does `brew update` + `brew
   install <BREW_DEPS>` (matching the July 23 run), then installs the
   historical `openssl@3` formula from the pinned homebrew/core commit
   URL if the active version is not already 3.6.3. Architecture check
   uses native `arch`/`machine` (section 13).
2. **`ci/x86_64-on-arm64/bootstrap-x86_64-on-arm64.sh`** — same shape as
   the ARM64 script, but every `brew` invocation is wrapped in
   `arch -x86_64 /usr/local/bin/brew` (Homebrew itself runs under
   Rosetta, but `arch`/`machine` reporting is not wrapped — section 13).
3. **`ci/src/brew_versions.sh`** (new) — the shared verification
   baseline from section 14. Declares the 22 July-23 known-good versions
   as two parallel indexed arrays (`BREW_VERSION_FORMULAS` /
   `BREW_VERSION_VALUES`) plus a `brew_version_of <formula>` helper for
   lookups. This shape (not `declare -A BREW_VERSIONS`, despite the
   section 14 example) is deliberate: GitHub Actions' `macos-14` runners
   ship bash 3.2 as `/bin/bash`, which does not support associative
   arrays, and the previous `${BREW_VERSIONS[...]}` syntax crashed both
   `watermark.sh` and the bootstrap scripts under `set -u`. Sourced by
   both bootstraps (for the `openssl@3` target version) and by
   `watermark.sh` (for the baseline drift check). Initially a
   verification baseline only — no formula is force-installed to this
   version unless the bootstrap logic for that formula decides to do so.
4. **`ci/src/watermark.sh`** — kept the strict ARM64-vs-x86\_64
   invariant (section 6/17) and the existing `arm64: ...` / `x86_64: ...`
   output format. Added:

   - A `status: OK|MISMATCH (baseline-OK|baseline-DRIFT|no-baseline)`
     line per dependency (section 8 expected format).

   - Section 12 handling: a formula with multiple historical kegs (e.g.
     `openssl@3 3.6.4 3.6.2`) is no longer flagged as an architecture
     mismatch on its own — the comparison is on the **active** version
     (the first version token `brew list --versions` returns, which is
     the version Homebrew actually hands to the build). Extra kegs are
     surfaced as non-blocking warnings.

   - Section 14 baseline drift check via `brew_version_of` (not
     `${BREW_VERSIONS[...]}` — see item 3 above for the bash 3.2 reason).
     Drift is non-blocking (it does not weaken the ARM64==x86\_64
     invariant); it is the evidence the next pinning round will use.
5. **A runtime vendored tap is created on demand** (section 9, second
   choice — see section 19.7 for why this was switched from the original
   URL install after the first CI run). The bootstrap does **not** add a
   repo-side tap directory; instead it `mkdir -p`s
   `$(brew --repository)/Library/Taps/kicadpin/homebrew-kicad-pin/Formula/`,
   `curl`s the historical `openssl@3.rb` from the same `homebrew/core`
   commit (`afd93f1b...`) into that directory, and runs
   `HOMEBREW_NO_INSTALL_FROM_API=1 brew install kicadpin/kicad-pin/openssl@3`.
   The pinning is still the smallest mechanism that satisfies section 9
   (historical homebrew-core formula, no new package manager); the
   vendored tap is purely the delivery vehicle that modern Homebrew
   requires. If the 3.6.3 bottle has been GCRed from GHCR and the
   source build also fails, the next round will pre-vendor the `.rb`
   into the repo and ship the patch files alongside it.
6. **`docs/gradually-stabilize-homebrew-deps.md`** — this section
   (section 19) added.

## 19.4 Which dependencies actually required pinning (so far)

| Formula     | Reason                                                                               | Mechanism                                                                |
| ----------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `openssl@3` | First observed architecture mismatch (section 10): 3.6.4 vs 3.6.2, known-good 3.6.3. | Historical formula `.rb` from `homebrew/core` commit `afd93f1b...`.      |
| `nng`       | No mismatch in the July 23 baseline (1.12.0 on both architectures).                  | None. Kept on normal Homebrew install per section 11.                    |
| all others  | No mismatch observed in the July 23 baseline.                                        | None. Kept on normal Homebrew install per section 9 ("evidence-driven"). |

The `homebrew/core` commit used for the `openssl@3` pin is
`afd93f1b5d40319fef3976408e83f0b232de81ac` — the
"openssl\@3: update 3.6.3 bottle." commit dated 2026-07-06, which is the
formula revision that was active during the 2026-07-23 successful run.
A newer 3.6.3-bump commit (`ac0bc95fef0e5aed25b3662f6271020410cfbc3d`,
dated 2026-08-25) also exists; if GitHub Actions reports that the
older bottle SHA has been GCRed from GHCR, swap `OPENSSL_PIN_COMMIT`
for that newer commit before re-running.

## 19.5 Confirmation of the invariant

`ci/src/watermark.sh --both` is invoked by
`ci/src/make-universal-build-with-refs.sh` immediately before the
universal `lipo` combine. With the first-pass implementation above, the
expected output on a clean GitHub Actions `macos-14` runner is:

```text
arm64: openssl@3 3.6.3
x86_64: openssl@3 3.6.3
status: OK (baseline-OK)
...
Dependency verification: PASS
```

The hard invariant (section 17: ARM64 dependency version == x86\_64
dependency version for every dependency that participates in the KiCad
build/bundle) is preserved unchanged.

## 19.6 Next round trigger (section 5 step 7-8)

After the first GitHub Actions run on this change:

- If `watermark.sh` reports `status: OK (baseline-OK)` for every
  `BREW_DEPS` entry, the task is complete (section 15).

- If any non-`openssl@3` formula shows `MISMATCH`, add a targeted pin
  for *only that formula* using the same runtime vendored tap mechanism
  (see section 19.7), bump its `brew_version_of` entry in
  `ci/src/brew_versions.sh` to whatever both architectures converged
  on, and re-run. Do **not** pre-emptively pin formulas that already
  match.

- If `openssl@3` itself still mismatches (e.g. the historical 3.6.3
  bottle has been GCRed from GHCR and both arches fell back to source
  builds that diverged), pre-vendor the `.rb` plus its patch files into
  the repo so the source build can complete reproducibly on both arches.

## 19.7 First CI run result (2026-09-01) and second-pass fix

The first GitHub Actions run after section 19's first-pass implementation
failed during the ARM64 bootstrap's `openssl@3` pin step (process exit
code 1). The failure was **not** the "bottle GCRed" failure mode
anticipated in section 19.3 item 5 — it was a different, more
fundamental incompatibility:

```text
+ HOMEBREW_NO_INSTALL_FROM_API=1
+ /opt/homebrew/bin/brew install \
    https://raw.githubusercontent.com/Homebrew/homebrew-core/afd93f1b.../Formula/o/openssl%403.rb
##[warning]No available formula or cask with the name
"https://raw.githubusercontent.com/homebrew/homebrew-core/.../openssl%403.rb".
This command requires the tap https:/.
If you trust this tap, tap it explicitly and then try again:
  brew tap https:/
##[error]Process completed with exit code 1.
```

Modern Homebrew (4.x and later, including the `macos-14-arm64` GitHub
Actions runner image dated 20260629.0180.1) **refuses to install a
formula from a raw HTTPS URL** — it interprets the URL as a tap
reference (`https:/`) rather than as a fetchable formula file. Local
testing on Homebrew 6.0.20 confirmed that `brew install --formula <local-file.rb>` is **also** rejected ("Homebrew requires formulae to
be in a tap"). The only modern-Homebrew-compatible way to install a
specific historical formula revision is to place the `.rb` inside a
tap.

A second, lesser bug was also surfaced by the same log: the bootstrap's
existing `brew uninstall --ignore-dependencies openssl@3` removed only
the **active** 3.6.4 keg and left the 3.6.2 keg behind
(`openssl@3 3.6.2 is still installed.`). The next install would have
silently seen 3.6.2 as the new active version, breaking the pin
(section 12).

### Second-pass fix (this commit)

Both bootstrap scripts were updated:

1. `brew uninstall --ignore-dependencies` → `brew uninstall --force --ignore-dependencies` so **all** historical kegs are removed before
   the pinned install.
2. The raw-URL `brew install` was replaced with a runtime vendored tap:
   `mkdir -p $(brew --repository)/Library/Taps/kicadpin/homebrew-kicad-pin/Formula`,
   `curl -fsSL <OPENSSL_PIN_URL> -o .../Formula/openssl@3.rb`, then
   `HOMEBREW_NO_INSTALL_FROM_API=1 brew install kicadpin/kicad-pin/openssl@3`.
   The x86\_64 bootstrap wraps every `brew` invocation in
   `arch -x86_64` (including `brew --repository`, which returns
   `/usr/local/Homebrew` rather than `/opt/homebrew`).

Local verification on Homebrew 6.0.20 (bash 3.2.57):

- `bash -n` syntax check passes on both bootstrap scripts.

- The runtime vendored tap is created, the historical `.rb` is
  downloaded (8617 bytes, valid `class OpensslAT3 < Formula`), and
  `brew install --dry-run kicadpin/kicad-pin/openssl@3` recognises the
  formula (`==> Trusted formula kicadpin/kicad-pin/openssl@3`). The
  dry-run only stops because the host's existing `openssl@3` from
  `homebrew/core` blocks it — a condition the `--force --ignore-
  dependencies` uninstall step in the bootstrap clears first.

### Second-pass expected outcome

After the next GitHub Actions run:

- If `watermark.sh --both` reports `status: OK (baseline-OK)` for every
  `BREW_DEPS` entry, the task is complete (section 15).

- If the 3.6.3 bottle has been GCRed from GHCR, the install will fall
  back to a source build. The historical formula revision
  (`afd93f1b...`) uses absolute GitHub URLs for its `patch do; url
  ...; end` blocks, so a source build should still complete. If it does
  not, pre-vendor the `.rb` plus its patch files into the repo.

- If any non-`openssl@3` formula shows `MISMATCH`, add a targeted pin
  for *only that formula* using the same runtime vendored tap mechanism
  (bump its `brew_version_of` entry to whatever both arches converged
  on). Do **not** pre-emptively pin formulas that already match.

