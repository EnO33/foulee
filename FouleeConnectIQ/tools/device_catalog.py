#!/usr/bin/env python3
"""List the Garmin devices Foulée can run on, from the device profiles.

The SDK manager downloads one folder per device, each with a `compiler.json`
describing the hardware (`connect-iq-sdk-manager device download
--download-all`). This script reads them all and keeps the watches that can
run the app: a watch app with a background service, on Connect IQ at least
`MIN_API_LEVEL` (the manifest's `minApiLevel`, pinned by validate_project.py).

The profiles cannot be committed (the Connect IQ agreement bars redistributing
them), so this runs where they are downloaded: the `Garmin devices` workflow,
or a developer's machine. It prints a Markdown table, for a person deciding
what to add, and with `--json` the same rows for a script.

    FouleeConnectIQ/tools/device_catalog.py [--devices DIR] [--json]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from validate_project import MIN_API_LEVEL

DEFAULT_DEVICES = os.path.expanduser("~/.Garmin/ConnectIQ/Devices")
MAC_DEVICES = os.path.expanduser("~/Library/Application Support/Garmin/ConnectIQ/Devices")

REQUIRED_APP_TYPES = {"watchApp", "background"}


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
    return (
        REQUIRED_APP_TYPES.issubset(device["app_types"])
        and bool(device["ciq"])
        and version(device["ciq"]) >= MIN_API_LEVEL
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default = DEFAULT_DEVICES if os.path.isdir(DEFAULT_DEVICES) else MAC_DEVICES
    parser.add_argument("--devices", default=default, help="dossier des profils d'appareils")
    parser.add_argument("--json", action="store_true", help="une ligne JSON par appareil retenu")
    args = parser.parse_args()

    paths = sorted(glob.glob(os.path.join(args.devices, "*", "compiler.json")))
    if not paths:
        sys.exit(f"aucun profil d'appareil dans {args.devices}")
    devices = []
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            devices.append(describe(json.load(handle)))
    kept = sorted((d for d in devices if eligible(d)), key=lambda d: d["id"])

    if args.json:
        for device in kept:
            print(json.dumps(device, ensure_ascii=False, sort_keys=True))
        return 0

    floor = ".".join(str(n) for n in MIN_API_LEVEL)
    print(f"{len(kept)} appareils retenus sur {len(devices)} profils (watch app + background, CIQ ≥ {floor})\n")
    print("| Appareil | Identifiant | Groupe | CIQ | Famille | Écran | bpp | Icône | App (ko) | Fond (ko) |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for d in kept:
        print(
            f"| {d['name']} | `{d['id']}` | {d['group']} | {d['ciq']} | {d['family']} | {d['display']} "
            f"| {d['bpp']} | {d['icon']} | {d['app_kb']} | {d['background_kb']} |"
        )
    # What the filter sees, so a profile format that moved on shows up here
    # rather than as an empty table.
    seen = sorted({t for d in devices for t in d["app_types"]})
    print(f"\nTypes d'app rencontrés dans les profils : {', '.join(seen)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
