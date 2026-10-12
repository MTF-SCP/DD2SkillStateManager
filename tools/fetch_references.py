"""Restore only pinned, hashed reference files listed in the source manifest."""
from __future__ import annotations

import hashlib
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    for manifest in ("references/manifest.json", "references/font-manifest.json"):
        for entry in json.loads((ROOT / manifest).read_text(encoding="utf-8")):
            if "sha256" not in entry:
                continue
            path = (ROOT / entry["path"]).resolve()
            if not path.is_relative_to(ROOT):
                raise ValueError("Manifest path leaves project")
            if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"]:
                continue
            data = urllib.request.urlopen(entry["url"], timeout=60).read()
            if hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise ValueError("Reference hash mismatch: " + entry["path"])
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            print(entry["path"])


if __name__ == "__main__":
    main()
