#!/usr/bin/env python3
"""Download and verify every binary target declared by ONLYOFFICE Editors v9.1.

The package manifest is the source of truth: an archive is retained only after
its SHA-256 equals the manifest's checksum.  This script does not unpack,
execute, or otherwise load framework binaries.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

TARGET = re.compile(
    r"\.binaryTarget\(\s*name:\s*\"(?P<name>[^\"]+)\"\s*,\s*"
    r"url:\s*\"(?P<url>[^\"]+)\"\s*,\s*"
    r"checksum:\s*\"(?P<checksum>[0-9a-f]{64})\"\s*\)",
    re.DOTALL,
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: Path) -> None:
    temporary = destination.with_suffix(destination.suffix + ".part")
    temporary.unlink(missing_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "onlyoffice-artifact-verifier/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output, length=1024 * 1024)
        temporary.replace(destination)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True, help="v9.1 Package.swift from the preserved fork")
    parser.add_argument("--directory", type=Path, required=True, help="directory for verified ZIP archives")
    parser.add_argument("--download", action="store_true", help="download missing or mismatched archives")
    args = parser.parse_args()

    manifest = args.manifest.resolve()
    entries = [match.groupdict() for match in TARGET.finditer(manifest.read_text(encoding="utf-8"))]
    if len(entries) != 22:
        print(f"ERROR: expected 22 binary targets in {manifest}, found {len(entries)}", file=sys.stderr)
        return 2

    args.directory.mkdir(parents=True, exist_ok=True)
    report: list[dict[str, str | int]] = []
    failures = 0
    for entry in entries:
        archive = args.directory / entry["url"].rsplit("/", 1)[-1]
        actual = sha256(archive) if archive.is_file() else None
        if actual != entry["checksum"] and args.download:
            print(f"DOWNLOAD {entry['name']} {entry['url']}", flush=True)
            try:
                download(entry["url"], archive)
                actual = sha256(archive)
            except Exception as error:
                print(f"ERROR {entry['name']}: {error}", file=sys.stderr)
                actual = None
        valid = actual == entry["checksum"]
        print(f"{'OK' if valid else 'FAIL'} {entry['name']} {archive.name} {actual or 'missing'}")
        report.append({
            "name": entry["name"], "url": entry["url"], "archive": archive.name,
            "expected_sha256": entry["checksum"], "actual_sha256": actual or "",
            "bytes": archive.stat().st_size if archive.is_file() else 0, "verified": valid,
        })
        if not valid:
            failures += 1

    output = args.directory / "verification-report.json"
    output.write_text(json.dumps({
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "manifest": str(manifest), "target_count": len(entries), "verified_count": len(entries) - failures,
        "artifacts": report,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"REPORT {output}")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
