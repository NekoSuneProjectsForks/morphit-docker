#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

API_BASE = "https://git.agorise.net/api/v1/repos/agorise/morphit"
USER_AGENT = "NekoSuneProjectsForks/morphit-docker release fetcher"


def request_json(url: str):
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as handle:
        shutil.copyfileobj(response, handle, length=1024 * 1024)


def latest_release():
    releases = request_json(f"{API_BASE}/releases?limit=20&page=1")
    releases = [release for release in releases if not release.get("draft", False)]
    if not releases:
        raise RuntimeError("Forgejo returned no published Morphit releases")

    releases.sort(
        key=lambda release: release.get("published_at") or release.get("created_at") or "",
        reverse=True,
    )
    return releases[0]


def release_for_tag(tag: str):
    encoded = urllib.parse.quote(tag, safe="")
    return request_json(f"{API_BASE}/releases/tags/{encoded}")


def asset_url(asset: dict) -> str:
    url = asset.get("browser_download_url") or asset.get("download_url")
    if not url:
        raise RuntimeError(f"Release asset {asset.get('name', '<unknown>')} has no download URL")
    return url


def select_assets(release: dict, tag: str):
    assets = release.get("assets") or []
    preferred = f"morphit-{tag}.tar.gz"

    tar_asset = next((asset for asset in assets if asset.get("name") == preferred), None)
    if tar_asset is None:
        candidates = [
            asset
            for asset in assets
            if str(asset.get("name", "")).endswith(".tar.gz")
            and not str(asset.get("name", "")).endswith(".sha256")
        ]
        if len(candidates) == 1:
            tar_asset = candidates[0]
        else:
            raise RuntimeError(
                f"Could not uniquely find Morphit's release tarball for {tag}; "
                f"assets were: {[asset.get('name') for asset in assets]}"
            )

    tar_name = str(tar_asset.get("name"))
    checksum_asset = next(
        (asset for asset in assets if asset.get("name") == f"{tar_name}.sha256"),
        None,
    )
    if checksum_asset is None:
        candidates = [asset for asset in assets if str(asset.get("name", "")).endswith(".sha256")]
        if len(candidates) == 1:
            checksum_asset = candidates[0]
        else:
            raise RuntimeError(
                f"Could not uniquely find the SHA-256 asset for {tar_name}; "
                f"assets were: {[asset.get('name') for asset in assets]}"
            )

    return tar_asset, checksum_asset


def verify_checksum(tarball: Path, checksum_file: Path) -> None:
    checksum_text = checksum_file.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"\b([0-9a-fA-F]{64})\b", checksum_text)
    if not match:
        raise RuntimeError(f"No SHA-256 digest found in {checksum_file.name}")

    expected = match.group(1).lower()
    digest = hashlib.sha256()
    with tarball.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    actual = digest.hexdigest()

    if actual != expected:
        raise RuntimeError(
            f"SHA-256 mismatch for {tarball.name}: expected {expected}, got {actual}"
        )


def safe_extract(tarball: Path, destination: Path) -> None:
    destination_resolved = destination.resolve()
    with tarfile.open(tarball, "r:gz") as archive:
        for member in archive.getmembers():
            member_path = (destination / member.name).resolve()
            if member_path != destination_resolved and destination_resolved not in member_path.parents:
                raise RuntimeError(f"Unsafe path in release tarball: {member.name}")
        archive.extractall(destination)


def find_source_root(extracted: Path) -> Path:
    if (extracted / "package.json").is_file():
        return extracted

    direct = [path.parent for path in extracted.glob("*/package.json") if path.is_file()]
    if len(direct) == 1:
        return direct[0]

    candidates = [path.parent for path in extracted.rglob("package.json") if path.is_file()]
    if len(candidates) == 1:
        return candidates[0]

    raise RuntimeError(
        "Could not determine the Morphit release root after extraction "
        f"(found {len(candidates)} package.json candidates)"
    )


def fetch_release(tag: str, output: Path) -> None:
    release = release_for_tag(tag)
    tar_asset, checksum_asset = select_assets(release, tag)

    with tempfile.TemporaryDirectory(prefix="morphit-release-") as temp_name:
        temp = Path(temp_name)
        tarball = temp / str(tar_asset["name"])
        checksum = temp / str(checksum_asset["name"])
        extracted = temp / "extracted"
        extracted.mkdir()

        print(f"Downloading {tarball.name}", file=sys.stderr)
        download(asset_url(tar_asset), tarball)
        print(f"Downloading {checksum.name}", file=sys.stderr)
        download(asset_url(checksum_asset), checksum)
        verify_checksum(tarball, checksum)
        print(f"SHA-256 verified for {tarball.name}", file=sys.stderr)

        safe_extract(tarball, extracted)
        source_root = find_source_root(extracted)

        if output.exists():
            shutil.rmtree(output)
        shutil.copytree(source_root, output, symlinks=True)

    print(tag)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Find, download and verify published Agorise Morphit releases."
    )
    parser.add_argument("--tag", help="Specific release tag to fetch")
    parser.add_argument(
        "--latest-tag",
        action="store_true",
        help="Print the newest published release tag and exit without downloading",
    )
    parser.add_argument("--output", type=Path, help="Directory to extract the verified release into")
    args = parser.parse_args()

    release = release_for_tag(args.tag) if args.tag else latest_release()
    tag = str(release.get("tag_name") or "").strip()
    if not tag:
        raise RuntimeError("Morphit release has no tag_name")

    if args.latest_tag:
        print(tag)
        return 0

    if args.output is None:
        parser.error("--output is required unless --latest-tag is used")

    fetch_release(tag, args.output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
