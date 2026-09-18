# edge-headless / DSH integration (macOS)

Task source: `hq-edge/docs/tasks/kicad-dsh-mac-package.md`.

Goal: an Apple Silicon `KiCad.app` carries a self-contained arm64
`edge-headless` runtime (Node + hq-edge + DSH), while Intel macOS keeps the
existing online Copilot (`https://chat.eda.cn/`).

```text
KiCad.app arm64                      KiCad.app x86_64
  └── Contents/Resources/              └── (no edge-headless)
        edge-headless/                       │
          bin/node                           ▼
          bin/hq-edge-server.cjs       existing online Copilot
          bin/dsh                        → https://chat.eda.cn/
                │
                ▼
             hq-edge → DSH
```

Nothing is downloaded at application runtime, nothing is installed globally,
and `dsh` is **not** added to `PATH` (that stays a separate task).

## Architecture boundary

Download / verify / extract / staging all live in `kicad-mac-builder`; KiCad
itself only *consumes* the bundled tree:

| Concern | Owner |
|---|---|
| **the pin itself (version + SHA256 + asset)** | **`build-config.json`** |
| updating / inspecting / checking the pin | `bin/pin-edge-headless.py` |
| pinned release, download, SHA256, extraction | `bin/fetch-edge-headless.sh` |
| CMake wiring, reads the pin, arch gate, copy into the bundle | `kicad-mac-builder/edge-headless.cmake` |
| post-staging validation (incl. that the bundle matches the pin) | `bin/verify-edge-headless.sh` |
| code signing of bundled executables | `bin/apple.py` |
| runtime path resolution | KiCad `hq/runtime/src/hq_edge_launcher.cpp` |

The existing staging → signing → DMG → notarization flow is reused; no second
packaging pipeline was added.

## Pinned release

| Item | Value |
|---|---|
| Asset | `edge-headless-darwin-arm64.zip` |
| Version | `0.1.3` |
| SHA256 | `a8a9f222bb502f952d17344694771aa2f18ee85b6e796cfcc19eeff1f3fb5f64` |
| URL | `https://github.com/Huaqiu-Electronics/edge-headless/releases/download/0.1.3/edge-headless-darwin-arm64.zip` |

The pin (release tag + asset + SHA256) lives in exactly one
place — **`build-config.json`** at the top of this repository:

```json
{
  "edgeHeadless": {
    "enable": true,
    "version": "0.1.3",
    "asset": "edge-headless-darwin-arm64.zip",
    "sha256": "a8a9f222bb502f952d17344694771aa2f18ee85b6e796cfcc19eeff1f3fb5f64",
    "repoUrl": "https://github.com/Huaqiu-Electronics/edge-headless/releases/download",
    "url": ""
  }
}
```

`kicad-mac-builder/edge-headless.cmake` reads it with `string(JSON …)` at
configure time, so editing the file changes what the next `build.py` run
downloads — nothing else needs updating.

#### Managing the pin

```bash
# what is pinned right now (also shows the resolved download URL)
./kicad-mac-builder/bin/pin-edge-headless.py --print

# pin a new release, computing the SHA256 from the artifact you downloaded
./kicad-mac-builder/bin/pin-edge-headless.py --version 0.1.4 \
    --local ~/Downloads/edge-headless-darwin-arm64.zip

# or paste the hash from the release page (must be given together with --version)
./kicad-mac-builder/bin/pin-edge-headless.py --version 0.1.4 --sha256 <64 hex>

# before publishing: prove the artifact you built IS the one being pinned
./kicad-mac-builder/bin/pin-edge-headless.py --check path/to/edge-headless.zip

# stage a local artifact permanently (instead of passing --edge-headless-url)
./kicad-mac-builder/bin/pin-edge-headless.py --set-url /path/to/edge-headless.zip
```

The script refuses to write a version without a hash (or a hash without a
version), refuses malformed hashes, rewrites the file atomically, and preserves
the surrounding `_comment` block. Hand-editing the JSON is fine too — nothing
else caches these values.

#### How a build consumes it

| Where | Effect |
|---|---|
| `build-config.json` → `edge-headless.cmake` | default `EDGE_HEADLESS_VERSION/ASSET/SHA256/REPO_URL` |
| `build.py --edge-headless-*` | overrides the file for one build |
| `-DEDGE_HEADLESS_*=…` | overrides the file for one configure |

Guard rails: a missing `build-config.json`, an empty version/asset/SHA256, or a
non-hex hash is a **configure-time FATAL_ERROR** (arm64 only — x86_64 never
bundles anything, so it never needs a pin), and overriding only one half of the
(version, SHA256) pair emits a warning naming the file. The expected version is
then passed into `verify-edge-headless.sh`, which fails the build if the
artifact staged into `KiCad.app` reports a different release.

The artifact's own `VERSION` file currently reports
`HQ_EDGE_VERSION=0.1.3-25-g5365af5`; `0.1.3` is the release line it belongs
to (same line as the Windows `edge-headless-win-x64.zip` pin).

### Staging an unpublished artifact

The macOS asset has not been published yet. Until it is, build with the local
artifact instead of the GitHub URL:

```bash
./build.py --arch=arm64 --target package-kicad-unified \
    --edge-headless-url /Users/admin/code/hq-edge/dist/edge-headless.zip ...
```

`--edge-headless-url` accepts `https://`, `file://…` or a plain path. Once the
release exists, drop the flag — or clear it globally with
`pin-edge-headless.py --clear-url` — and re-pin the published artifact with
`pin-edge-headless.py --version <tag> --local <downloaded.zip>` so
`version` + `sha256` describe the real release.

## Destination inside KiCad.app

```text
KiCad.app/Contents/Resources/edge-headless/
├── bin/node                  bundled Node 24 (arm64)
├── bin/hq-edge-server.cjs    hq-edge entrypoint
├── bin/dsh, bin/dsh-cli.cjs  DSH CLI launcher (bundle-internal)
├── config/runtime.env        runtime + DSH configuration
├── dsh/                      the runnable DSH
├── dsh-plugins/              HQ Edge bridge / erc plugins
├── node_modules/
└── VERSION, package.json, public/
```

`Contents/Resources` (rather than a bespoke `Contents/edge-headless`) was
chosen because it is the canonical macOS location for material shipped inside
a bundle, it matches KiCad's existing convention of putting bundled
third-party material there (`Contents/Resources/Licenses`), and
`bin/apple.py` already walks `Contents/Resources` when collecting code to
sign. `Contents/MacOS` stays reserved for KiCad's own binaries.

## HQ_EDGE_LAUNCHER resolution

`hq/runtime/src/hq_edge_launcher.cpp` resolves the runtime from the **running
executable**, so the app works from `/Applications`, `~/Applications`, any
custom location, or a Gatekeeper-translocated mount:

```text
running executable
    → walk up to the OUTERMOST *.app that contains Contents/Resources/edge-headless
    → <bundle>/Contents/Resources/edge-headless/
        ├── bin/node
        └── bin/hq-edge-server.cjs
```

"Outermost" matters because KiCad launches several executables out of one
bundle, and the nested editor bundles are themselves `.app`s:

```text
KiCad.app/Contents/MacOS/kicad                                   → KiCad.app
KiCad.app/Contents/Applications/eeschema.app/Contents/MacOS/...  → KiCad.app   (not eeschema.app)
```

The work directory is the `edge-headless` root itself (not
`Contents/Resources`), because hq-edge resolves the bundled DSH
(`<runtime-dir>/dsh`) and `config/runtime.env` relative to it.

## arm64 vs x86_64 behaviour

The split is a **compile-time** decision (`HQ_EDGE_MAC_*` in
`hq_edge_launcher.cpp`), not a runtime CPU check:

| Build | Bundled runtime | Launcher | Copilot panel |
|---|---|---|---|
| macOS arm64, packaged | yes (`HQ_EDGE_MAC_BUNDLED`) | starts bundled hq-edge | `http://localhost:<edgePort>/dsh/` |
| macOS arm64, Debug | developer checkout (`HQ_EDGE_MAC_DEV_CHECKOUT`) | unchanged | as today |
| macOS x86_64 (any) | none (`HQ_EDGE_MAC_UNSUPPORTED`) | `Start()` returns immediately | `get_webview_chat_path()` → `https://chat.eda.cn/` |
| Windows | next to the executable | unchanged | unchanged |

The Intel path required **no new code**: `HQ_EDGE_LAUNCHER::Start()` refuses,
so `GetPort()` stays `0`, and the existing fallback in
`copilot_panel_container.h` / `pcb_copilot_panel_init.h` already loads the
online Copilot in that case. No Rosetta, no Intel build of edge-headless, no
universal binary.

Gate: `CMAKE_APPLE_SILICON_PROCESSOR` (i.e. `build.py --arch`), falling back to
`CMAKE_HOST_SYSTEM_PROCESSOR` for Intel-host builds where `--arch` is
optional. Override with `-DEDGE_HEADLESS_ENABLE=OFF` / `--no-edge-headless`.

## Packaging order

`edge-headless.cmake` attaches `install-edge-headless-into-app` to the
existing `kicad` ExternalProject, and `kicad.cmake` adds it to the
`DEPENDEES` of `sign-app`:

```text
kicad: install
    → collect-licenses / install-*-into-app
    → install-edge-headless-into-app     (rsync + verify)
    → sign-app                            (apple.py)
    → verify-*, notarize-app
    → package-kicad-unified               (bin/package.sh → DMG)
```

The step exists unconditionally (a no-op on x86_64) so `sign-app`'s
dependency list needs no per-architecture branch.

## Signing implications

`edge-headless` is executable code, so it must be signed **before** the outer
bundle. `bin/apple.py::get_kicad_paths_for_signing()` now walks
`Contents/Resources/edge-headless` and appends every Mach-O image it finds
(detected by magic number, not extension — the tree holds thousands of `.js`
files that must not be handed to `codesign`), and the bundle itself is still
appended last.

Detected in the current artifact: **22** images — `bin/node`, the darwin
`.node` addons (better-sqlite3, sharp/koffi/rolldown/lightningcss/fsevents,
node-pty), `libvips-cpp…dylib`, and vendored CLIs (`rg`, `codex`, `zsh`,
`claude`, `esbuild`, `spawn-helper`). The win32/linux prebuilds in the archive
are PE/ELF and are skipped.

The repository's existing identity and `signing/entitlements.plist` are
reused — no new identity. That plist already grants
`com.apple.security.cs.disable-executable-page-protection` and
`disable-library-validation`, which bundled Node/V8 needs under Hardened
Runtime. `verify_signing()` also checks the secure timestamp on the bundled
`bin/node`.

Verified locally with ad-hoc signing:

```text
codesign -vvv --deep --strict /tmp/kmb-eh-test/KiCad.app   → valid on disk
codesign --verify --verbose=4 .../Contents/Resources/edge-headless/bin/node → valid
```

### Gotcha: dangling symlinks break the whole signature

A dangling symlink inside a sealed resource directory makes
`codesign --verify --deep --strict` fail on the **entire app** with
`No such file or directory`. The published artifact currently ships
`dsh/.dsh/` — a DSH_HOME materialised on the build machine — containing ~482
symlinks into a pnpm store that is not in the archive. It is removed at
staging time (see below), and `verify-edge-headless.sh` now asserts zero
dangling symlinks.

## Verification performed

* `fetch-edge-headless.sh` — download, SHA256 match, single-root layout,
  required files, `lipo -archs` = arm64, bundled `node -v`, no
  `DSH_LOCAL_PATH` override. Negative cases (SHA mismatch, missing SHA) exit 1.
* `verify-edge-headless.sh` on a staged `KiCad.app` — required files, arm64
  node, `node -v`, `hq-edge-server.cjs` parses, `bin/dsh --version` →
  `0.1.5-rc.2`, no dangling symlinks, no `/Users/admin/code` in bundled config.
* `bin/dsh --hq-paths` **from inside the bundle**:
  `installRoot` and `nodeExecutable` resolve into `KiCad.app`,
  `dshHome = ~/.hq-edge/<version>/dsh-home` (`hq-managed`).
* `HQ_EDGE_LAUNCHER` bundle-walk algorithm — resolves correctly from
  `Contents/MacOS/kicad`, from the nested `eeschema.app`/`pcbnew.app`, and
  returns empty for a bundle without the runtime and for a non-bundle path.
* Compile-checked `hq_edge_launcher.cpp` in all three configurations
  (arm64 release, arm64 debug, x86_64) with KiCad's real compile flags.

## Known issues / follow-ups (not fixed here)

* **`dsh/.dsh/` in the artifact** — a stale DSH_HOME carrying a developer
  `.credentials.yaml` and dangling symlinks. It is stripped during staging
  (it is never read: `dsh --hq-paths` shows an hq-managed home outside the
  bundle), but the correct fix is to stop producing it in hq-edge packaging.
* **Dead weight** — the archive ships win32/linux `.node` prebuilds and is
  ~1.0 GB uncompressed (373 MB zipped). Trimming cross-platform prebuilds per
  target would shrink the DMG considerably.
* **No runtime smoke test of the full KiCad → hq-edge → DSH chain** — that
  needs a launched KiCad on a clean Apple Silicon machine (task §17/§18).
