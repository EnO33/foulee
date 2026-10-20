#!/usr/bin/env python3
"""List the Garmin watches Foulée can run on, from the device profiles.

The SDK manager downloads one folder per device, each with a `compiler.json`
describing the hardware (`connect-iq-sdk-manager device download
--download-all`). This script reads them all and keeps the watches that can
run the app: a watch app with a background service, on Connect IQ at least
`MIN_API_LEVEL` (the manifest's `minApiLevel`, pinned by validate_project.py),
with a colour screen.

The profiles cannot be committed (the Connect IQ agreement bars redistributing
them), so this runs where they are downloaded: the `Garmin devices` workflow,
or a developer's machine. It prints a Markdown table for a person, `--json`
lines for a script, and with `--write` updates the matrix itself:
`devices.json` (the hardware facts the other tools read) and the manifest's
`<iq:products>`. `--from` reads `--json` lines saved from a workflow run
instead of the profiles.

    FouleeConnectIQ/tools/device_catalog.py [--devices DIR | --from FILE] [--json | --write]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_project import DEVICES_FILE, MIN_API_LEVEL, ROOT

DEFAULT_DEVICES = os.path.expanduser("~/.Garmin/ConnectIQ/Devices")
MAC_DEVICES = os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Devices")

REQUIRED_APP_TYPES = {"watchApp", "background"}

# Products that run watch apps without being watches: bike computers and
# handheld GPS units. Foulée is worn.
NOT_WATCHES = ("edge", "etrex", "gpsmap", "montana", "oregon", "rino")

# The facts kept in devices.json, in this order.
MATRIX_FIELDS = ("id", "name", "family", "display", "bpp", "icon", "ciq", "app_kb")


def version(raw: str) -> tuple[int, ...]:
    return tuple(int(part) for part in raw.split(".") if part.isdigit())


def memory(profile: dict, app_type: str) -> int | None:
    for entry in profile.get("appTypes", []):
        if entry.get("type") == app_type:
            return entry.get("memoryLimit")
    return None


def describe(profile: dict) -> dict:
    """The facts about one device that decide whether and how it is added."""
    versions = [version(p["connectIQVersion"]) for p in profile.get("partNumbers", []) if p.get("connectIQVersion")]
    icon = profile.get("launcherIcon", {})
    return {
        "id": profile.get("deviceId", ""),
        "name": profile.get("displayName", ""),
        "group": profile.get("deviceGroup", ""),
        "ciq": ".".join(str(n) for n in max(versions)) if versions else "",
        "family": profile.get("deviceFamily", ""),
        "display": profile.get("displayType", ""),
        "bpp": profile.get("bitsPerPixel"),
        "icon": icon.get("width"),
        "app_kb": (memory(profile, "watchApp") or 0) // 1024,
        "background_kb": (memory(profile, "background") or 0) // 1024,
        "app_types": sorted(entry.get("type", "") for entry in profile.get("appTypes", [])),
    }


def eligible(device: dict) -> bool:
    """A watch that can run the app as it is written.

    One-bit screens are left out: the app draws in colour, and those watches
    (Instinct 3 Solar, Instinct E) also give a watch app 128 KB, a fraction of
    what a session needs (ADR 0009, D10).
    """
    return (
        REQUIRED_APP_TYPES.issubset(device["app_types"])
        and bool(device["ciq"])
        and version(device["ciq"]) >= MIN_API_LEVEL
        and not device["id"].startswith(NOT_WATCHES)
        and (device["bpp"] or 0) > 1
    )


def read_profiles(folder: str) -> list[dict]:
    paths = sorted(glob.glob(os.path.join(folder, "*", "compiler.json")))
    if not paths:
        sys.exit(f"aucun profil d'appareil dans {folder}")
    devices = []
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            devices.append(describe(json.load(handle)))
    return devices


def read_lines(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip().startswith("{")]


def write_matrix(kept: list[dict]) -> None:
    """devices.json and the manifest's products, both from the same rows."""
    rows = [{field: device[field] for field in MATRIX_FIELDS} for device in kept]
    with open(os.path.join(ROOT, DEVICES_FILE), "w", encoding="utf-8") as handle:
        handle.write("[\n")
        handle.write(",\n".join("  " + json.dumps(row, ensure_ascii=False) for row in rows))
        handle.write("\n]\n")

    manifest_path = os.path.join(ROOT, "manifest.xml")
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = handle.read()
    products = "".join(f'            <iq:product id="{row["id"]}"/>\n' for row in rows)
    manifest, count = re.subn(
        r"(<iq:products>\n).*?(\s*</iq:products>)",
        lambda match: match.group(1) + products.rstrip("\n") + match.group(2),
        manifest,
        flags=re.DOTALL,
    )
    if count != 1:
        sys.exit("manifest.xml : bloc <iq:products> introuvable")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        handle.write(manifest)
    print(f"{DEVICES_FILE} et manifest.xml : {len(rows)} appareils")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default = DEFAULT_DEVICES if os.path.isdir(DEFAULT_DEVICES) else MAC_DEVICES
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--devices", default=default, help="dossier des profils d'appareils")
    source.add_argument("--from", dest="lines", help="lignes --json enregistrées depuis le workflow")
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--json", action="store_true", help="une ligne JSON par appareil retenu")
    output.add_argument("--write", action="store_true", help="met à jour devices.json et le manifeste")
    args = parser.parse_args()

    devices = read_lines(args.lines) if args.lines else read_profiles(args.devices)
    kept = sorted((d for d in devices if eligible(d)), key=lambda d: d["id"])

    if args.write:
        write_matrix(kept)
        return 0
    if args.json:
        for device in kept:
            print(json.dumps(device, ensure_ascii=False, sort_keys=True))
        return 0

    floor = ".".join(str(n) for n in MIN_API_LEVEL)
    print(f"{len(kept)} montres retenues sur {len(devices)} profils (watch app + background, CIQ ≥ {floor}, couleur)\n")
    print("| Appareil | Identifiant | CIQ | Famille | Écran | bpp | Icône | App (ko) | Fond (ko) |")
    print("|---|---|---|---|---|---|---|---|---|")
    for d in kept:
        print(
            f"| {d['name']} | `{d['id']}` | {d['ciq']} | {d['family']} | {d['display']} "
            f"| {d['bpp']} | {d['icon']} | {d['app_kb']} | {d['background_kb']} |"
        )
    # What the filter sees, so a profile format that moved on shows up here
    # rather than as an empty table.
    seen = sorted({t for d in devices for t in d.get("app_types", [])})
    print(f"\nTypes d'app rencontrés dans les profils : {', '.join(seen)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
