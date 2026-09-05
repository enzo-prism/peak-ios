#!/usr/bin/env python3
"""Record clean source before archive/export; bind inspected artifacts afterward.

Store receipts outside the checkout (or in ignored .asc/artifacts). This is a
local audit trail, not signed provenance or proof the compiler used this source.
No build, upload, signing, or App Store mutation is performed.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import zipfile


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def clean_source(repo):
    if git(repo, "status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none"):
        raise ValueError("Source checkout must be clean, including untracked files and submodules")
    return {"commit": git(repo, "rev-parse", "HEAD"), "tree": git(repo, "rev-parse", "HEAD^{tree}")}


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def archive_hash(path):
    # Canonical sorted manifest binds relative paths, file bytes, and symlink
    # targets; timestamps and permissions are intentionally excluded.
    manifest = []
    for item in sorted(path.rglob("*")):
        relative = item.relative_to(path).as_posix()
        if item.is_symlink():
            manifest.append([relative, "symlink", os.readlink(item)])
        elif item.is_file():
            manifest.append([relative, "file", sha256(item)])
    encoded = json.dumps(manifest, separators=(",", ":"), ensure_ascii=True).encode()
    return hashlib.sha256(encoded).hexdigest()


def bundle(info):
    return {"bundle_id": info["CFBundleIdentifier"],
            "version": str(info["CFBundleShortVersionString"]),
            "build": str(info["CFBundleVersion"])}


def inspect_artifacts(archive, ipa, version, build):
    apps = list((archive / "Products" / "Applications").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("Archive must contain exactly one application")
    app = apps[0]
    archive_bundles = [bundle(plistlib.loads(p.read_bytes())) for p in
                       [app / "Info.plist", *sorted(app.glob("PlugIns/*.appex/Info.plist"))]]
    with zipfile.ZipFile(ipa) as z:
        main = [n for n in z.namelist() if n.startswith("Payload/")
                and n.count("/") == 2 and n.endswith(".app/Info.plist")]
        if len(main) != 1:
            raise ValueError("IPA must contain exactly one application")
        prefix = main[0].removesuffix("Info.plist")
        extensions = sorted(n for n in z.namelist() if n.startswith(prefix + "PlugIns/")
                            and n.count("/") == 4 and n.endswith(".appex/Info.plist"))
        ipa_bundles = [bundle(plistlib.loads(z.read(n))) for n in [main[0], *extensions]]
    key = lambda item: item["bundle_id"]
    if sorted(archive_bundles, key=key) != sorted(ipa_bundles, key=key):
        raise ValueError("Archive and IPA application/extension metadata differ")
    if any(item["version"] != version or item["build"] != build for item in ipa_bundles):
        raise ValueError("App and every extension must match the requested version/build")
    return {"archive": {"name": archive.name, "sha256": archive_hash(archive),
                         "hash_format": "sha256(sorted compact JSON [relative path, file|symlink, file sha256|link target] manifest)"},
            "ipa": {"name": ipa.name, "sha256": sha256(ipa)}, "bundles": ipa_bundles}


def save(path, value, exclusive=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    if exclusive:
        with path.open("x") as out:
            json.dump(value, out, indent=2)
            out.write("\n")
    else:
        temporary = path.with_name(path.name + ".tmp")
        with temporary.open("x") as out:
            json.dump(value, out, indent=2)
            out.write("\n")
        temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    begin = commands.add_parser("begin", help="Run before archive/export from a clean checkout")
    begin.add_argument("--repo", type=Path, default=Path.cwd())
    begin.add_argument("--version", required=True)
    begin.add_argument("--build", required=True)
    begin.add_argument("--output", type=Path, required=True)
    finish = commands.add_parser("finish", help="Run after archive/export; verify source and artifact pairing")
    finish.add_argument("--receipt", type=Path, required=True)
    finish.add_argument("--archive", type=Path, required=True)
    finish.add_argument("--ipa", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "begin":
        repo = Path(git(args.repo, "rev-parse", "--show-toplevel")).resolve()
        receipt = {"schema_version": 1, "state": "begun", "began_at": now(),
                   "checkout": str(repo), "source": clean_source(repo),
                   "version": args.version, "build": args.build,
                   "provenance": "Local before/after source observation and artifact hashes; not cryptographic proof of compiler inputs"}
        save(args.output, receipt, exclusive=True)
        # A receipt inside a nonignored checkout would dirty the source itself.
        try:
            clean_source(repo)
        except ValueError:
            args.output.unlink()
            raise ValueError("Place receipt outside the checkout or in an ignored directory")
        print(f"Began receipt: {args.output}")
    else:
        receipt = json.loads(args.receipt.read_text())
        if receipt.get("schema_version") != 1 or receipt.get("state") != "begun":
            raise ValueError("Expected an unfinished schema-version-1 receipt")
        repo = Path(receipt["checkout"])
        if clean_source(repo) != receipt["source"]:
            raise ValueError("Source commit/tree changed since begin")
        artifacts = inspect_artifacts(args.archive, args.ipa, receipt["version"], receipt["build"])
        if clean_source(repo) != receipt["source"]:
            raise ValueError("Source changed while inspecting artifacts")
        receipt.update(state="finished", finished_at=now(), artifacts=artifacts)
        save(args.receipt, receipt)
        print(f"Finished receipt: {args.receipt}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
