# Task Spec — Gradually Stabilize Homebrew Dependencies for Universal KiCad Build

**Status:** IMPLEMENTATION TASK  
**Priority:** Delivery first  
**Principle:** No over-engineering; make the smallest change that restores reproducible ARM64/x86_64 dependencies.

## 1. Objective

Stabilize the macOS universal KiCad build so that the ARM64 and x86_64 build environments use **exactly the same Homebrew dependency versions** before producing the final universal bundle with `lipo`.

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

---

## 2. Known-good baseline

A previously successful GitHub Actions run is available locally:

```text
/Users/admin/code/kicad-mac-builder/docs/success_run.log
```

The successful run was on **2026-07-23** and produced matching dependency versions for ARM64 and x86_64.

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

---

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

---

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

The x86_64 script runs Homebrew under Rosetta:

```bash
arch -x86_64 /usr/local/bin/brew
```

The ARM64 script uses:

```text
/opt/homebrew/bin/brew
```

Keep this architecture model.

Do not introduce Docker, Nix, Conda, Bazel, a custom package manager, or another dependency-management framework.

---

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

---

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

---

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

---

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

---

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

---

# 10. Special case: openssl@3

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

Do not simply accept 3.6.4 on ARM64 or 3.6.2 on x86_64.

Investigate the July 23 log and determine the smallest reliable way to obtain 3.6.3.

Pin **only openssl@3** initially.

Then run GitHub Actions again.

---

# 11. Special case: nng

The current build has already demonstrated that:

```text
nng 1.12.0
```

is available and matching on both architectures.

The existing pinned nng approach may therefore be retained if it is required by the current Homebrew state.

Do not redesign nng unless the verification demonstrates a mismatch.

---

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

---

# 13. Architecture verification

Do not use:

```bash
arch -x86_64 arch
```

This is invalid and previously caused:

```text
arch: Can't find any plists for arch
```

For the x86_64 Homebrew environment use:

```bash
arch -x86_64 /usr/local/bin/brew ...
```

For reporting architecture, use appropriate existing system information such as:

```bash
machine
arch
```

without wrapping the `arch` utility itself in Rosetta.

---

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

---

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

---

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
   - confirmation that ARM64/x86_64 versions match.

Do not add infrastructure that is not required by the observed GitHub runner failures.

---

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

---

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