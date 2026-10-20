#!/usr/bin/env python3
"""Render the watch app's launcher icons and the store icons from the iPhone
app icon, so Foulée has one identity on every device (#468).

Rendering is ImageMagick's job (`brew install imagemagick`); this script only
says what to render, at the sizes `validate_project.py` already pins per
device. Re-run it whenever the iPhone app icon changes, then commit the PNGs:

    FouleeConnectIQ/tools/render_icons.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_project import LAUNCHER_ICON_PX, ROOT

SOURCE = os.path.join(
    os.path.dirname(ROOT), "Foulee/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
)

# Connect IQ brand guidelines: 500 px for the listing, 128 px for the store
# embedded on the watch (store/README.md § 2).
STORE_ICON_PX = {"icon-500.png": 500, "icon-128.png": 128}

# Deterministic output: no metadata, no timestamps, so a re-run on an
# unchanged source changes no file.
STRIP = ["-strip", "-define", "png:exclude-chunks=date,time"]


def imagemagick() -> str:
    for name in ("magick", "convert"):
        path = shutil.which(name)
        if path:
            return path
    sys.exit("ImageMagick introuvable : brew install imagemagick")


def render(tool: str, size: int, output: str) -> None:
    command = [tool, SOURCE, "-filter", "Lanczos", "-resize", f"{size}x{size}", *STRIP, output]
    subprocess.run(command, check=True)
    print(f"  {os.path.relpath(output, os.path.dirname(ROOT))} ({size} px)")


def main() -> int:
    tool = imagemagick()
    print(f"Rendu depuis {os.path.relpath(SOURCE, os.path.dirname(ROOT))}")
    for device, size in sorted(LAUNCHER_ICON_PX.items()):
        render(tool, size, os.path.join(ROOT, f"resources-{device}", "drawables", "launcher_icon.png"))
    assets = os.path.join(ROOT, "store", "assets")
    os.makedirs(assets, exist_ok=True)
    for name, size in STORE_ICON_PX.items():
        render(tool, size, os.path.join(assets, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
