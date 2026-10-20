#!/usr/bin/env python3
"""Render the watch app's launcher icons and the store icons from the iPhone
app icon, so Foulée has one identity on every device (#468).

Rendering is ImageMagick's job (`brew install imagemagick`); this script only
says what to render, at the sizes devices.json pins per device. Re-run it
whenever the iPhone app icon or the device matrix changes, then commit:

    FouleeConnectIQ/tools/render_icons.py

The icons are grouped rather than written once per device (#472). Each screen
family gets one folder (`resources-round-454x454`), at the icon size most of
its devices use; a device whose icon differs gets its own folder
(`resources-venu3`), which the SDK picks over the family's. An icon at the
wrong size fails the build: the compiler rescales it and warns.
"""

from __future__ import annotations

import collections
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_project import ROOT, load_devices

SOURCE = os.path.join(
    os.path.dirname(ROOT), "Foulee/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
)

# Connect IQ brand guidelines: 500 px for the listing, 128 px for the store
# embedded on the watch (store/README.md § 2).
STORE_ICON_PX = {"icon-500.png": 500, "icon-128.png": 128}

# Deterministic output: no metadata, no timestamps, so a re-run on an
# unchanged source changes no file.
STRIP = ["-strip", "-define", "png:exclude-chunks=date,time"]

ICON_FILE = "launcher_icon.png"
DRAWABLES_XML = """\
<drawables xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd">
    <bitmap id="LauncherIcon" filename="launcher_icon.png" dithering="none" />
</drawables>
"""


def imagemagick() -> str:
    for name in ("magick", "convert"):
        path = shutil.which(name)
        if path:
            return path
    sys.exit("ImageMagick introuvable : brew install imagemagick")


def plan(devices: dict[str, dict]) -> dict[str, int]:
    """Icon folder → icon size: one per family, one per device that differs."""
    by_family: dict[str, list[dict]] = collections.defaultdict(list)
    for device in devices.values():
        by_family[device["family"]].append(device)
    folders = {}
    for family, members in by_family.items():
        # Most common size, the larger one on a tie, so the result never
        # depends on the order of devices.json.
        counts = collections.Counter(device["icon"] for device in members)
        size = max(counts, key=lambda px: (counts[px], px))
        folders[f"resources-{family}"] = size
        for device in members:
            if device["icon"] != size:
                folders[f"resources-{device['id']}"] = device["icon"]
    return folders


def render(tool: str, size: int, output: str) -> None:
    command = [tool, SOURCE, "-filter", "Lanczos", "-resize", f"{size}x{size}", *STRIP, output]
    subprocess.run(command, check=True)
    print(f"  {os.path.relpath(output, os.path.dirname(ROOT))} ({size} px)")


def main() -> int:
    tool = imagemagick()
    devices = load_devices()
    folders = plan(devices)

    # Folders this script owns but no longer needs: a device that now shares
    # its family's icon, a family that left the matrix.
    owned = {f"resources-{d['id']}" for d in devices.values()}
    for entry in sorted(os.listdir(ROOT)):
        if entry.startswith("resources-") and entry not in folders:
            path = os.path.join(ROOT, entry)
            if entry in owned or os.path.isfile(os.path.join(path, "drawables", ICON_FILE)):
                shutil.rmtree(path)
                print(f"  {entry}/ supprimé")

    print(f"Rendu depuis {os.path.relpath(SOURCE, os.path.dirname(ROOT))}")
    for folder, size in sorted(folders.items()):
        drawables = os.path.join(ROOT, folder, "drawables")
        os.makedirs(drawables, exist_ok=True)
        with open(os.path.join(drawables, "drawables.xml"), "w", encoding="utf-8") as handle:
            handle.write(DRAWABLES_XML)
        render(tool, size, os.path.join(drawables, ICON_FILE))

    assets = os.path.join(ROOT, "store", "assets")
    os.makedirs(assets, exist_ok=True)
    for name, size in STORE_ICON_PX.items():
        render(tool, size, os.path.join(assets, name))
    print(f"{len(folders)} dossiers d'icônes pour {len(devices)} appareils")
    return 0


if __name__ == "__main__":
    sys.exit(main())
