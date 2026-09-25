#!/usr/bin/env python3
"""Single source of truth for MacOSFixer version metadata.

Usage:
    python3 Version.py            # print current version
    python3 Version.py 1.2.3      # set version (updates all consumers)
    python3 Version.py patch      # bump patch
    python3 Version.py minor      # bump minor
    python3 Version.py major      # bump major
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VERSION_FILE = ROOT / "VERSION"
PACKAGE = ROOT / "Package.swift"
MAKEFILE = ROOT / "Makefile"
INFO_PLIST = ROOT / "Resources" / "Info.plist"

VERSION_RE = re.compile(r'version:\s*"([^"]+)"')


def read_version() -> str:
    return VERSION_FILE.read_text().strip()


def write_version(version: str) -> None:
    VERSION_FILE.write_text(version + "\n")


def update_package(version: str) -> None:
    text = PACKAGE.read_text()
    new = VERSION_RE.sub(f'version: "{version}"', text, count=1)
    PACKAGE.write_text(new)


def update_makefile(version: str) -> None:
    text = MAKEFILE.read_text()
    new = re.sub(r'DMG_NAME = MacOSFixer-[^\s]+\.dmg',
                 f'DMG_NAME = MacOSFixer-{version}.dmg', text, count=1)
    MAKEFILE.write_text(new)


def update_info_plist(version: str) -> None:
    text = INFO_PLIST.read_text()
    new = re.sub(r'<key>CFBundleVersion</key>\s*<string>[^<]+</string>',
                 f'<key>CFBundleVersion</key>\n\t<string>{version}</string>', text, count=1)
    new = re.sub(r'<key>CFBundleShortVersionString</key>\s*<string>[^<]+</string>',
                 f'<key>CFBundleShortVersionString</key>\n\t<string>{version}</string>', new, count=1)
    INFO_PLIST.write_text(new)


def bump(current: str, kind: str) -> str:
    parts = current.split(".")
    while len(parts) < 3:
        parts.append("0")
    major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])
    if kind == "major":
        major, minor, patch = major + 1, 0, 0
    elif kind == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return f"{major}.{minor}.{patch}"


def main() -> int:
    if len(sys.argv) == 1:
        print(read_version())
        return 0

    arg = sys.argv[1]
    if arg in {"patch", "minor", "major"}:
        version = bump(read_version(), arg)
    elif arg.startswith("--bump"):
        kind = arg.split("=", 1)[1] if "=" in arg else "patch"
        if kind not in {"patch", "minor", "major"}:
            print(f"Unknown bump kind: {kind}", file=sys.stderr)
            return 1
        version = bump(read_version(), kind)
    else:
        version = arg

    if not re.match(r"^\d+\.\d+\.\d+$", version):
        print(f"Invalid version (expected x.y.z): {version}", file=sys.stderr)
        return 1

    old = read_version()
    write_version(version)
    update_package(version)
    update_makefile(version)
    update_info_plist(version)
    subprocess.run(["git", "add", "VERSION", "Package.swift", "Makefile",
                    "Resources/Info.plist"], check=True, cwd=ROOT)
    print(f"Version: {old} -> {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())