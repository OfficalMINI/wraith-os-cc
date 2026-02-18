#!/usr/bin/env python3
"""Generate manifest.lua for Wraith OS auto-updater.

Run from the wraith/ repo root:
    python generate_manifest.py

Outputs: manifest.lua
"""

import os
import re

SCAN_DIR = "."
MANIFEST_PATH = "manifest.lua"

# Directories to skip entirely
EXCLUDE_DIRS = {"clients", "__pycache__", ".git"}

# Basename patterns to exclude
EXCLUDE_PATTERNS = [
    r".*_config\.lua$",
    r".*_data\.lua$",
    r".*\.tmp$",
    r"^manifest\.lua$",
    r"^crash\.log$",
    r"^storage_debug\.log$",
    r"^generate_manifest\.py$",
]


def compute_hash(content: bytes) -> str:
    """Same hash as CC:Tweaked updater: sum of bytes * 31 mod 2147483647."""
    s = 0
    for b in content:
        s = (s * 31 + b) % 2147483647
    return str(s)


def should_exclude(rel_path: str) -> bool:
    parts = rel_path.replace("\\", "/").split("/")
    for part in parts:
        if part in EXCLUDE_DIRS:
            return True
    basename = parts[-1]
    for pattern in EXCLUDE_PATTERNS:
        if re.match(pattern, basename):
            return True
    return False


def main():
    files = {}

    for dirpath, dirnames, filenames in os.walk(SCAN_DIR):
        # Prune excluded dirs
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]

        rel_dir = os.path.relpath(dirpath, SCAN_DIR)
        if rel_dir == ".":
            rel_dir = ""

        for filename in sorted(filenames):
            if not filename.endswith(".lua"):
                continue

            if rel_dir:
                rel_path = f"{rel_dir}/{filename}".replace("\\", "/")
            else:
                rel_path = filename

            if should_exclude(rel_path):
                continue

            full_path = os.path.join(dirpath, filename)
            with open(full_path, "rb") as f:
                content = f.read()

            # Normalize to \n (matches what CC:Tweaked stores)
            content = content.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
            files[rel_path] = compute_hash(content)

    # Write manifest.lua as a Lua table literal
    lines = ["{\n"]
    for path in sorted(files.keys()):
        lines.append(f'  ["{path}"] = "{files[path]}",\n')
    lines.append("}\n")

    with open(MANIFEST_PATH, "w", newline="\n") as f:
        f.write("".join(lines))

    print(f"manifest.lua generated — {len(files)} files tracked")
    return 0


if __name__ == "__main__":
    exit(main())
