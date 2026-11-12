#!/usr/bin/env python3
"""Fetch the published extension catalog for the video's Extension Catalog scene.

Downloads the signed index, its signature and every listing icon from the fixed catalog URL the app
uses (ExtensionCatalog.baseURL, the same paths VolantFetchHost.fetchCatalogFile reads), checks the
Ed25519 signature against the app's public key (ExtensionCatalogKey) and each icon's size and SHA-256
against the signed index, and writes them under the output folder at their catalog paths, with
fetched.json recording what was fetched and when, as the host's local date and time. Nothing is installed and no package is downloaded.
The fixture checks them again with the app's own code in the render VM.
"""
import argparse
import base64
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import urllib.request

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

ROOT = Path(__file__).resolve().parents[3]
BASE = re.search(r'baseURL = URL\(string: "([^"]+)"\)', (ROOT / "Core/Sources/VolantCore/Extensions/ExtensionCatalog.swift").read_text())[1]
KEY = re.search(r'static let publicKey = "([^"]+)"', (ROOT / "Volant/Extensions/ExtensionCatalogClient.swift").read_text())[1]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuses redirects, as the fetch helper does."""

    def redirect_request(self, *args, **kwargs):
        return None


def fetch(path, limit):
    """Downloads one catalog file, refusing redirects and anything over `limit` bytes."""
    opener = urllib.request.build_opener(NoRedirect)
    with opener.open(BASE + path, timeout=30) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise SystemExit(f"{path} is larger than {limit} bytes")
    return data


def main():
    """Fetches, verifies and writes the catalog fixture."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist-video/catalog")
    args = parser.parse_args()
    index = fetch("catalog.json", 1_000_000)
    signature = fetch("catalog.json.sig", 1_000)
    Ed25519PublicKey.from_public_bytes(base64.b64decode(KEY)).verify(base64.b64decode(signature.strip()), index)
    catalog = json.loads(index)
    files = {"catalog.json": index, "catalog.json.sig": signature}
    for listing in catalog["extensions"]:
        if not listing.get("icon"):
            continue
        path = f"packages/{listing['id']}/{listing['version']}/{listing['icon']}"
        expected = listing["iconFile"]
        icon = fetch(path, expected["size"])
        if len(icon) != expected["size"] or hashlib.sha256(icon).hexdigest() != expected["sha256"]:
            raise SystemExit(f"{path} doesn't match the signed catalog")
        files[path] = icon
    for path, data in files.items():
        target = args.output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    now = datetime.now().astimezone()
    fetched = {"source": BASE, "fetched": now.strftime("%Y-%m-%d"), "fetchedAt": now.isoformat(timespec="seconds"), "sequence": catalog["sequence"],
               "extensions": len(catalog["extensions"]), "icons": len(files) - 2}
    (args.output / "fetched.json").write_text(json.dumps(fetched, indent=2) + "\n")
    print(f"Verified catalog sequence {fetched['sequence']}: {fetched['extensions']} extensions, {fetched['icons']} icons, fetched {fetched['fetched']}")


if __name__ == "__main__":
    main()
