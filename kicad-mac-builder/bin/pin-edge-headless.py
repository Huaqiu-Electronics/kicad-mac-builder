#!/usr/bin/env python3
"""pin-edge-headless.py — read and update the pinned edge-headless release.

The single source of truth for the bundled hq-edge runtime is

    <repo>/build-config.json      ->  "edgeHeadless" { version, asset, sha256, ... }

kicad-mac-builder/edge-headless.cmake reads that file at configure time, so
writing it here "applies" the pin to the next build (per-build overrides
--edge-headless-version/-sha256/-url still win over the file).

Typical use when a new release is published:

    # published asset, hash computed from the artifact you downloaded:
    ./kicad-mac-builder/bin/pin-edge-headless.py \\
        --version 0.1.4 --local ~/Downloads/edge-headless-darwin-arm64.zip

    # or, with the hash you got from the release page:
    ./kicad-mac-builder/bin/pin-edge-headless.py \\
        --version 0.1.4 --sha256 <64-hex-digits>

    # before publishing, prove the local artifact is the one being pinned:
    ./kicad-mac-builder/bin/pin-edge-headless.py \\
        --check /Users/admin/code/hq-edge/dist/edge-headless.zip

Show what is currently pinned:

    ./kicad-mac-builder/bin/pin-edge-headless.py --print
"""

import argparse
import hashlib
import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CONFIG = os.path.normpath(os.path.join(SCRIPT_DIR, os.pardir, os.pardir, "build-config.json"))

SECTION = "edgeHeadless"
HEX64 = re.compile(r"^[0-9a-fA-F]{64}$")

MUTABLE_KEYS = ("version", "asset", "sha256", "repoUrl", "url", "enable", "notes")


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def save(path, config):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(config, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dump(section):
    print("build-config.json -> {} ({}):".format(SECTION, "bundled" if section.get("enable", True) else "disabled"))
    for key in ("version", "asset", "sha256", "repoUrl", "url", "notes"):
        value = section.get(key, "")
        if key == "repoUrl" and value:
            value += "/" + section.get("version", "<version>") + "/" + section.get("asset", "<asset>")
        if key == "url" and not value:
            value = "(default GitHub release URL)"
        print("  {:<8} {}".format(key, value if value != "" else "(unset)"))


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Pin / inspect the edge-headless release bundled into KiCad.app.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--config", default=DEFAULT_CONFIG, help="Pin file (default: %(default)s).")
    parser.add_argument("--print", action="store_true", help="Print the current pin and exit.")
    parser.add_argument("--check", metavar="FILE",
                        help="Verify FILE's SHA256 matches the pin (use before publishing).")
    parser.add_argument("--version", help="Release tag to pin (e.g. 0.1.4).")
    parser.add_argument("--sha256", help="Expected SHA256 of the asset.")
    parser.add_argument("--local", metavar="FILE",
                        help="Compute the SHA256 of a local artifact and pin it. Requires --version.")
    parser.add_argument("--asset", help="Release asset name to pin.")
    parser.add_argument("--repo-url", help="Release download base URL.")
    parser.add_argument("--set-url", metavar="URL",
                        help="Pin an explicit fetch location (https://, file:// or a local path).")
    parser.add_argument("--clear-url", action="store_true", help="Remove the explicit URL override.")
    parser.add_argument("--notes")
    parser.add_argument("--enable", dest="enable", action="store_true", default=None,
                        help="Bundle edge-headless (default).")
    parser.add_argument("--disable", dest="enable", action="store_false",
                        help="Never bundle edge-headless (the Intel macOS behaviour).")
    parser.add_argument("--dry-run", action="store_true", help="Show the change without writing.")
    args = parser.parse_args(argv)

    if not os.path.exists(args.config):
        print("ERROR: pin file not found: {}".format(args.config), file=sys.stderr)
        return 1

    try:
        config = load(args.config)
    except ValueError as exc:
        print("ERROR: {} is not valid JSON: {}".format(args.config, exc), file=sys.stderr)
        return 1

    section = config.setdefault(SECTION, {})

    # ---- read-only operations -------------------------------------------
    if args.check:
        actual = sha256_of(args.check)
        expected = section.get("sha256", "")
        label = "{} {}".format(section.get("version", "<unpinned>"), os.path.basename(args.check))
        if actual == expected:
            print("OK  {} matches the pin: {}".format(label, actual))
            return 0
        print("MISMATCH {}\n  pinned: {}\n  actual: {}".format(label, expected, actual), file=sys.stderr)
        return 1

    write_ops = bool(args.version or args.sha256 or args.local or args.asset or args.repo_url
                     or args.set_url or args.clear_url or args.notes is not None
                     or args.enable is not None)

    if not write_ops or args.print or args.dry_run:
        dump(section)

    if not write_ops:
        return 0

    # ---- compute the update set -----------------------------------------
    updates = {}

    if args.local:
        if not os.path.exists(args.local):
            print("ERROR: no such artifact: {}".format(args.local), file=sys.stderr)
            return 1
        digest = sha256_of(args.local)
        print("computed SHA256({}) = {}".format(args.local, digest))
        updates["sha256"] = digest

    if args.sha256:
        if not HEX64.match(args.sha256.strip()):
            print("ERROR: --sha256 must be 64 hex digits, got {!r}".format(args.sha256), file=sys.stderr)
            return 1
        updates["sha256"] = args.sha256.strip().lower()

    if args.version:
        updates["version"] = args.version.strip()

    if args.asset:
        updates["asset"] = args.asset.strip()

    if args.repo_url:
        updates["repoUrl"] = args.repo_url.strip()

    if args.set_url:
        updates["url"] = args.set_url.strip()

    if args.clear_url:
        updates["url"] = ""

    if args.notes is not None:
        updates["notes"] = args.notes.strip()

    if args.enable is not None:
        updates["enable"] = bool(args.enable)

    # version and sha256 identify one immutable artifact, so they must always
    # be pinned together.
    # be pinned together.
    gave_version = args.version is not None
    gave_hash = bool(args.local or args.sha256)

    if gave_version and not gave_hash:
        print("ERROR: cannot pin version {!r} without its SHA256.\n"
              "  pin-edge-headless.py --version {} --local <artifact.zip>\n"
              "  pin-edge-headless.py --version {} --sha256 <64 hex digits>".format(
                  args.version, args.version, args.version), file=sys.stderr)
        return 1

    if gave_hash and not gave_version:
        print("ERROR: a SHA256 without a version does not pin a release; add "
              "--version <tag> (or omit both to inspect the current pin).", file=sys.stderr)
        return 1

    new_version = section.get("version", "")
    new_sha = section.get("sha256", "")

    if gave_version:
        new_version = args.version.strip()

    if "sha256" in updates:
        new_sha = updates["sha256"]

    if not HEX64.match(new_sha or ""):
        print("ERROR: refusing to write an empty or malformed sha256 ({!r}); "
              "use --local <artifact> to compute one.".format(new_sha), file=sys.stderr)
        return 1

    if gave_hash and updates["sha256"] == section.get("sha256"):
        print("WARNING: the new pin has the same SHA256 as the old one "
              "({}) -- this is only correct when the same artifact was re-tagged.".format(new_sha))

    original = dict(section)
    for key in MUTABLE_KEYS:
        if key in updates:
            section[key] = updates[key]

    print("")
    print("Pin changes:")
    for key in MUTABLE_KEYS:
        if key in updates:
            print("  {:<8} {!r} -> {!r}".format(key, original.get(key, "<unset>"), updates[key]))

    if args.dry_run:
        print("\n--dry-run: {} not modified".format(args.config))
        return 0

    save(args.config, config)
    print("\nWrote {}".format(args.config))
    print("Applies to the next configure/build automatically.")
    if section.get("url"):
        print("NOTE: an explicit url override is pinned ({}) -- clear it with "
              "--clear-url once the release is public.".format(section["url"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
