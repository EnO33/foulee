#!/usr/bin/env python3
"""Render the watch app's launcher icons and the store icons from the iPhone
app icon, so Foulée has one identity on every device (#468).

Rendering is ImageMagick's job (`brew install imagemagick`), and librsvg's for
the store's hero image (`brew install librsvg`); this script only says what to
render, at the sizes devices.json pins per device. Re-run it whenever the
iPhone app icon or the device matrix changes, then commit:

    FouleeConnectIQ/tools/render_icons.py

The icons are grouped rather than written once per device (#472). Each screen
family gets one folder (`resources-round-454x454`), at the icon size most of
its devices use; a device whose icon differs gets its own folder
(`resources-venu3`), which the SDK picks over the family's. An icon at the
wrong size fails the build: the compiler rescales it and warns.
"""

from __future__ import annotations

import base64
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

# Memory-in-pixel screens show 64 colours: two bits per channel. The MIP
# store icon keeps the motif in white on the icon's main colour in that
# palette; a gradient posterized to it bands, and dithering turns it to noise.
MIP_ICON = "icon-128-mip.png"
MIP_ICON_PX = STORE_ICON_PX["icon-128.png"]
MIP_LEVELS = 4
MIP_MOTIF_LUMA = "80%"

# The hero image tops the listing, the same card as getfoulee.app's social
# card (getfoulee/web, scripts/generate-assets.mjs, dark theme), at the store's
# 1440 × 720 and with no sentence to translate: the store is worldwide.
HERO = "hero.png"
HERO_SVG = """\
<svg width="1440" height="720" viewBox="0 0 1440 720" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="a" cx="15%" cy="10%" r="70%"><stop offset="0" stop-color="#4a1380"/><stop offset="1" stop-color="#07040e" stop-opacity="0"/></radialGradient>
    <radialGradient id="b" cx="95%" cy="90%" r="60%"><stop offset="0" stop-color="#5a1450"/><stop offset="1" stop-color="#07040e" stop-opacity="0"/></radialGradient>
    <linearGradient id="t" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#d97aff"/><stop offset="0.5" stop-color="#bf5af2"/><stop offset="1" stop-color="#7c3aed"/></linearGradient>
    <clipPath id="icon"><rect x="940" y="180" width="360" height="360" rx="81" ry="81"/></clipPath>
  </defs>
  <rect width="100%" height="100%" fill="#07040e"/>
  <rect width="100%" height="100%" fill="url(#a)"/>
  <rect width="100%" height="100%" fill="url(#b)"/>
  <text x="120" y="340" font-family="Helvetica" font-size="150" font-weight="bold" fill="#f7f3ff" letter-spacing="-4">Foulée</text>
  <text x="124" y="430" font-family="Helvetica" font-size="48" font-weight="bold" fill="url(#t)">iPhone · Apple Watch · Garmin</text>
  <text x="124" y="530" font-family="Helvetica" font-size="32" font-weight="bold" fill="#d97aff">getfoulee.app</text>
  <image x="940" y="180" width="360" height="360" clip-path="url(#icon)" href="data:image/png;base64,{icon}"/>
</svg>
"""

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


def librsvg() -> str:
    path = shutil.which("rsvg-convert")
    if not path:
        sys.exit("rsvg-convert introuvable : brew install librsvg")
    return path


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


def render_mip(tool: str, output: str) -> None:
    resized = [tool, SOURCE, "-filter", "Lanczos", "-resize", f"{MIP_ICON_PX}x{MIP_ICON_PX}"]
    histogram = subprocess.run(
        [*resized, "+dither", "-posterize", str(MIP_LEVELS), "-format", "%c", "histogram:info:-"],
        check=True, capture_output=True, text=True,
    ).stdout
    # Lines read "  12544: (170,85,255) #AA55FF srgb(170,85,255)".
    counts = (line.split() for line in histogram.splitlines() if line.strip())
    background = max(counts, key=lambda fields: int(fields[0].rstrip(":")))[2]
    command = [
        *resized, "-colorspace", "Gray", "-threshold", MIP_MOTIF_LUMA,
        "-colorspace", "sRGB", "-type", "TrueColor", "-fill", background, "-opaque", "black",
        *STRIP, output,
    ]
    subprocess.run(command, check=True)
    print(f"  {os.path.relpath(output, os.path.dirname(ROOT))} ({MIP_ICON_PX} px, fond {background})")


def render_hero(tool: str, output: str) -> None:
    icon = subprocess.run(
        [tool, SOURCE, "-filter", "Lanczos", "-resize", "360x360", *STRIP, "png:-"],
        check=True, capture_output=True,
    ).stdout
    svg = HERO_SVG.replace("{icon}", base64.b64encode(icon).decode("ascii"))
    png = subprocess.run([librsvg(), "--format", "png"], input=svg.encode(), check=True, capture_output=True).stdout
    subprocess.run([tool, "png:-", *STRIP, output], input=png, check=True)
    print(f"  {os.path.relpath(output, os.path.dirname(ROOT))} (1440 × 720)")


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
    render_mip(tool, os.path.join(assets, MIP_ICON))
    render_hero(tool, os.path.join(assets, HERO))
    print(f"{len(folders)} dossiers d'icônes pour {len(devices)} appareils")
    return 0


if __name__ == "__main__":
    sys.exit(main())
