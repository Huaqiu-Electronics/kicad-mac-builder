# Task Spec — Split macOS KiCad Packaging into Parallel ARM64 / x86_64 Builds

**Status:** FOR IMPLEMENTATION  
**Goal:** Replace the current macOS universal-build packaging with two independent architecture-specific DMG builds that run in parallel on GitHub Actions.

## 1. Objective

The current macOS packaging workflow builds both ARM64 and x86_64 KiCad variants in a single job and then creates a universal DMG.

This causes a very long wall-clock build time — currently approximately **5 hours**.

Change the packaging pipeline so that:

- ARM64 and x86_64 are built as **independent GitHub Actions jobs**.
- The two jobs run **in parallel**.
- Each job bootstraps and builds **only its own architecture**.
- Each job produces an architecture-specific DMG.
- The release contains two DMGs:
  - `kicad-huaqiu-<version>-macos-arm64.dmg`
  - `kicad-huaqiu-<version>-macos-x86_64.dmg`
- There is **no universal binary / universal DMG build**.
- Do not redesign the KiCad build system unnecessarily.

The primary optimization is reducing wall-clock time through parallelism, not introducing a sophisticated build farm.

---

## 2. Reference Repositories

Use these local repositories as **architecture and CI/CD design references**:

```text
/Users/admin/code/rustdesk
/Users/admin/code/electron-builder
```

Before modifying the KiCad packaging workflow, inspect their GitHub Actions workflows and relevant release/build scripts.

Focus specifically on:

### RustDesk

Study:

- architecture-specific builds
- GitHub Actions matrix/parallel execution
- native platform builds
- artifact naming
- release artifact publishing
- caching
- separation between build and release/upload stages

Do **not** copy RustDesk's overall CI complexity. Extract only patterns relevant to this task.

### electron-builder

Study:

- architecture-specific packaging
- macOS x64/arm64 handling
- GitHub Actions matrix builds
- artifact naming
- release publishing
- separation of build/package/publish concerns

Again, use it as a reference for the **general pattern**, not as something to reproduce literally.

---

## 3. Current Workflow

The current workflow is conceptually:

```text
single macOS job
    │
    ├── bootstrap ARM64
    ├── bootstrap x86_64
    │
    ├── build universal
    │     ├── ARM64
    │     └── x86_64
    │
    └── package universal DMG
```

The relevant existing workflow is:

```yaml
jobs:
  create_kicad_archive:
    runs-on: macos-14
```

and currently performs:

```bash
./ci/arm64-on-arm64/bootstrap-arm64-on-arm64.sh
./ci/x86_64-on-arm64/bootstrap-x86_64-on-arm64.sh
```

followed by:

```bash
./ci/src/make-universal-build-with-refs.sh
```

The new architecture should instead be:

```text
                         release
                            │
                 ┌──────────┴──────────┐
                 │                     │
              ARM64                  x86_64
                 │                     │
             bootstrap             bootstrap
                 │                     │
              build                 build
                 │                     │
              package              package
                 │                     │
              arm64 DMG           x86_64 DMG
                 │                     │
                 └──────────┬──────────┘
                            │
                      GitHub Release
```

---

## 4. Required Architecture

Use a GitHub Actions matrix or equivalent parallel-job mechanism.

Preferred structure:

```yaml
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - arch: arm64
            runner: macos-14

          - arch: x86_64
            runner: macos-14
```

The exact runner configuration should be determined from the existing repository and current GitHub Actions compatibility.

### Important

Do not switch macOS versions merely for this task unless required.

The current environment uses macOS 14 / Xcode 16.2 and that should remain the baseline unless investigation shows otherwise.

The immediate goal is:

> **split the two builds and run them concurrently.**

Runner modernization is a separate concern.

---

## 5. Bootstrap Requirements

Each architecture job must run **only its own bootstrap**.

ARM64:

```bash
./ci/arm64-on-arm64/bootstrap-arm64-on-arm64.sh
```

x86_64:

```bash
./ci/x86_64-on-arm64/bootstrap-x86_64-on-arm64.sh
```

Do not run both bootstrap scripts in either job.

The resulting architecture-specific dependency environment must remain isolated to that job.

---

## 6. Build Script Investigation

Before modifying the workflow, inspect:

```text
ci/src/
ci/arm64-on-arm64/
ci/x86_64-on-arm64/
```

and determine how:

```text
make-universal-build-with-refs.sh
```

currently invokes the underlying architecture builds.

Do not immediately create duplicate build scripts.

Prefer the smallest maintainable change.

Possible acceptable approaches:

### Preferred

Extract/reuse the common build logic:

```bash
make-build-with-refs.sh --arch arm64
make-build-with-refs.sh --arch x86_64
```

with thin architecture-specific wrappers if necessary.

### Also acceptable

Modify the existing build script to support an explicit architecture argument:

```bash
./ci/src/make-build-with-refs.sh --arch "$ARCH"
```

### Avoid

Creating large duplicated scripts such as:

```text
make-arm64-build-with-refs.sh
make-x86_64-build-with-refs.sh
make-universal-build-with-refs.sh
make-arm64-build-v2.sh
...
```

unless the existing build system makes this unavoidable.

**No over-engineering.**

---

## 7. Build Output

Each architecture must produce a normal standalone macOS DMG.

Expected release names:

```text
kicad-huaqiu-<tag>-macos-arm64.dmg
kicad-huaqiu-<tag>-macos-x86_64.dmg
```

Do not produce:

```text
kicad-unified-...
kicad-universal-...
```

Do not perform:

```text
lipo
```

or another universal-binary merge step.

The two applications should remain architecture-specific throughout packaging.

---

## 8. Release Publishing

The architecture builds may upload their artifacts to GitHub Actions artifacts first.

A simple and robust pattern is:

```text
build-arm64
    ↓
GitHub Actions artifact

build-x86_64
    ↓
GitHub Actions artifact

        ↓

publish-release
    ↓
arm64 DMG
x86_64 DMG
```

The publishing job should depend on both architecture builds:

```yaml
needs: build
```

and upload exactly two release assets.

Do not make one architecture depend on the other.

The dependency graph must remain:

```text
build-arm64 ──────┐
                  ├── publish
build-x86_64 ─────┘
```

not:

```text
build-arm64
     ↓
build-x86_64
     ↓
publish
```

---

## 9. Caching

Preserve the existing ccache approach:

```yaml
uses: actions/cache@v4
```

but make the cache architecture-specific.

For example:

```text
macos-arm64-ccache-...
macos-x86_64-ccache-...
```

Do not allow ARM64 and x86_64 compiler caches to collide.

Keep the current cache strategy initially.

Do **not** introduce additional dependency caches unless investigation shows a concrete measurable benefit.

The first objective is simply:

> two independent builds running simultaneously.

---

## 10. Existing Environment Variables

Preserve the existing release/build variables unless there is a concrete reason to change them:

```yaml
TAG
KICAD_REF
EXTRA_VERSION
RELEASE_ARG
SYMBOLS_REF
FOOTPRINTS_REF
PACKAGES3D_REF
TEMPLATES_REF
DOCS_TARBALL_URL
```

Change:

```yaml
RELEASE_NAME
```

to include architecture.

For example:

```text
huaqiu-<tag>-macos-arm64
huaqiu-<tag>-macos-x86_64
```

This prevents the two jobs from producing ambiguous output names.

---

## 11. Release Trigger

Preserve the current triggers:

```yaml
on:
  release:
    branches: [master]
    types: [published]
  workflow_dispatch:
```

Do not change release semantics as part of this task.

`workflow_dispatch` should continue to work.

---

## 12. Disk Cleanup

Preserve the existing disk-cleanup steps where they are necessary for KiCad's large build.

Do not aggressively redesign the cleanup logic.

The current workflow removes:

- unused Xcode versions
- CoreSimulator
- Xcode caches
- Android SDK
- Homebrew caches

Retain this behavior unless the reference repositories or actual runner behavior demonstrate that something is unnecessary.

Keep the workflow reliable before optimizing it further.

---

## 13. Important Constraint — Do Not Build a Universal Binary

The architectural decision for this task is:

> **Architecture-specific distribution is preferred over a universal distribution.**

Therefore, do not implement:

```text
arm64 + x86_64
        ↓
lipo
        ↓
universal executable
        ↓
universal DMG
```

The final release should simply contain:

```text
macos-arm64.dmg
macos-x86_64.dmg
```

This is intentional.

---

## 14. Verification

The implementation is complete only when both architectures can be verified independently.

At minimum, the CI should print:

```bash
uname -m
```

before bootstrap/build.

The build logs should clearly identify:

```text
Building ARM64
```

or:

```text
Building x86_64
```

After packaging, inspect the generated application/binary with an appropriate macOS command, for example:

```bash
file <binary>
```

Expected results should clearly indicate the correct architecture.

Also verify:

```text
arm64 job
  → arm64 DMG

x86_64 job
  → x86_64 DMG
```

No universal artifact should be produced.

---

## 15. GitHub Actions Concurrency Requirement

The workflow should allow GitHub Actions to schedule both architecture jobs concurrently.

Do not introduce:

```yaml
needs: build-arm64
```

on the x86_64 build.

Do not serialize the architecture builds through a shared environment.

The intended execution is:

```text
T0 ────────────────────────────────>

ARM64:   bootstrap ── build ── DMG
          └───────────────────────┘

x86_64:  bootstrap ── build ── DMG
          └───────────────────────┘

         approximately max(ARM64, x86_64)
```

rather than:

```text
ARM64:   bootstrap ── build ── DMG
                                      \
                                       x86_64: bootstrap ── build ── DMG
```

---

## 16. What NOT to Do

Do not:

- redesign the entire KiCad build system
- introduce Docker
- introduce a custom build server
- introduce self-hosted runners
- introduce a new CI framework
- introduce Bazel/Nix/etc.
- rewrite existing bootstrap scripts unnecessarily
- duplicate large build scripts
- create a universal binary
- introduce complicated release orchestration
- optimize every cache before measuring
- change the KiCad version/release selection logic
- change unrelated packaging behavior

This task is specifically about:

> **separating architectures and running them in parallel.**

---

## 17. Deliverables

The agent should produce:

### 1. GitHub Actions workflow

Update the existing packaging workflow to create:

```text
arm64 build
x86_64 build
```

in parallel.

### 2. Minimal build-script changes

Only if required to support architecture-specific builds.

### 3. Release assets

The workflow must publish:

```text
kicad-huaqiu-<tag>-macos-arm64.dmg
kicad-huaqiu-<tag>-macos-x86_64.dmg
```

### 4. Documentation/comments

Add only concise comments explaining why the architecture matrix exists.

Do not create a large CI architecture document for this change.

---

## 18. Acceptance Criteria

### Functional

- [ ] `workflow_dispatch` succeeds.
- [ ] Release-triggered workflow succeeds.
- [ ] ARM64 and x86_64 jobs start independently.
- [ ] Both jobs can run concurrently.
- [ ] ARM64 only runs ARM64 bootstrap/build.
- [ ] x86_64 only runs x86_64 bootstrap/build.
- [ ] ARM64 produces an ARM64 DMG.
- [ ] x86_64 produces an x86_64 DMG.
- [ ] No universal DMG is generated.
- [ ] GitHub Release contains exactly the two architecture-specific DMGs.
- [ ] Existing version/ref selection remains unchanged.

### CI

- [ ] ccache remains enabled.
- [ ] ARM64/x86_64 caches do not collide.
- [ ] Disk cleanup remains sufficient.
- [ ] Build logs clearly identify architecture.
- [ ] Release publishing happens only after both builds succeed.

### Quality

- [ ] No unnecessary new dependency.
- [ ] No large duplicated build scripts.
- [ ] No unrelated repository changes.
- [ ] Existing build logic is reused wherever practical.
- [ ] Implementation is substantially simpler than maintaining a universal build.

---

## 19. Final Report Required From Agent

After implementation, report:

```text
1. Files changed
2. Architecture build strategy
3. How the existing build script was reused/modified
4. ARM64 build verification
5. x86_64 build verification
6. Final DMG paths/names
7. Whether both jobs actually execute in parallel
8. Build duration for each architecture
9. Any remaining bottleneck
10. Any follow-up optimization worth doing
```

For timing, explicitly compare:

```text
Previous:
~5 hours sequential universal build

New:
ARM64:   X
x86_64:  Y
wall:    Z
```

Do not perform additional optimization work unless it is required for the acceptance criteria or an obvious build-breaking issue is discovered.