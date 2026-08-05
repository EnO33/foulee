#!/usr/bin/env python3
"""Static checks on the Connect IQ project that need no Connect IQ SDK.

The SDK cannot be installed on a GitHub runner without a Garmin account (see
FouleeConnectIQ/README.md, "Intégration continue"), so `monkeyc` never runs in
CI. This script is what CI *can* run: everything about the project that is
knowable from the files themselves.

It catches the mistakes that actually happen when the device matrix changes:
a product added to the manifest with no resources folder, a launcher icon at
the wrong pixel size (the resource compiler silently rescales and warns), a
drawable id that no longer matches `launcherIcon`, malformed XML.

Exit code 0 when everything checks out, 1 otherwise. Every failure is printed
in GitHub's `::error` annotation format so it lands on the PR diff.
"""

from __future__ import annotations

import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

IQ_NS = "http://www.garmin.com/xml/connectiq"

# Launcher icon size, in pixels, that each device's own profile demands. Read
# from `launcherIcon` in
# ~/Library/Application Support/Garmin/ConnectIQ/Devices/<id>/compiler.json
# with SDK 9.2.0. These are device hardware facts, not preferences: an icon of
# any other size makes the resource compiler rescale it and emit a warning.
# When adding a device, read its compiler.json and add the row here.
LAUNCHER_ICON_PX = {
    "fenix843mm": 60,
    "fr165": 54,
    "fr55": 35,
    "instinct2": 62,
    "venu2": 70,
    "venusq2": 40,
    "vivoactive5": 56,
}

# The application id of the *production* store entry. Publishing a beta build
# requires a different id (a beta app is a separate store entry), so
# store/README.md § 5 has the owner swap this value in manifest.xml, package,
# then swap it back. Committing the swapped manifest would silently point every
# later release at the beta entry — both ids are well-formed UUIDs, so nothing
# else here would notice. Pinning the expected value turns that discipline into
# a check.
PRODUCTION_APP_ID = "859c7300a91149fdb6ce7e4453bfe59d"

errors: list[str] = []
notes: list[str] = []


def fail(message: str, file: str | None = None) -> None:
    errors.append(message)
    location = f" file={file}," if file else ""
    print(f"::error{location} title=Connect IQ::{message}")


def ok(message: str) -> None:
    notes.append(message)
    print(f"  ok  {message}")


def parse_xml(relative_path: str) -> ET.Element | None:
    """Parse an XML file under the project root, reporting a readable error."""
    path = os.path.join(ROOT, relative_path)
    if not os.path.exists(path):
        fail(f"fichier manquant : {relative_path}", relative_path)
        return None
    try:
        return ET.parse(path).getroot()
    except ET.ParseError as exc:
        fail(f"XML invalide dans {relative_path} : {exc}", relative_path)
        return None


def check_manifest() -> tuple[list[str], str | None]:
    """Validate manifest.xml.

    Returns the declared product ids and the drawable id `launcherIcon` points
    at — the resource check needs the latter to look for the id the manifest
    actually names rather than a hard-coded one.
    """
    root = parse_xml("manifest.xml")
    if root is None:
        return [], None

    application = root.find(f"{{{IQ_NS}}}application")
    if application is None:
        fail("manifest.xml : aucun élément <iq:application>", "manifest.xml")
        return [], None

    app_id = application.get("id", "")
    if not re.fullmatch(r"[0-9a-f]{32}", app_id):
        fail(
            "manifest.xml : l'identifiant d'application doit être un UUID de 32 "
            f"caractères hexadécimaux en minuscules, trouvé « {app_id} »",
            "manifest.xml",
        )
    elif app_id != PRODUCTION_APP_ID:
        fail(
            f"manifest.xml : identifiant d'application « {app_id} » au lieu de "
            f"« {PRODUCTION_APP_ID} ». Cause la plus probable : un paquet beta a "
            "été fabriqué (store/README.md § 5) et l'identifiant de production "
            "n'a pas été rétabli. Si l'identifiant de production a réellement "
            "changé, mettre PRODUCTION_APP_ID à jour dans "
            "tools/validate_project.py.",
            "manifest.xml",
        )
    else:
        ok(f"identifiant d'application : {app_id}")

    for attribute in ("entry", "launcherIcon", "minApiLevel", "name", "type"):
        if not application.get(attribute):
            fail(f"manifest.xml : attribut « {attribute} » manquant", "manifest.xml")

    launcher_icon = application.get("launcherIcon", "")
    drawable_id: str | None = None
    if launcher_icon and not launcher_icon.startswith("@Drawables."):
        fail(
            f"manifest.xml : launcherIcon « {launcher_icon} » ne pointe pas vers "
            "une ressource @Drawables.",
            "manifest.xml",
        )
    elif launcher_icon:
        drawable_id = launcher_icon[len("@Drawables.") :] or None

    products = application.find(f"{{{IQ_NS}}}products")
    ids = (
        [p.get("id", "") for p in products.findall(f"{{{IQ_NS}}}product")]
        if products is not None
        else []
    )
    if not ids:
        fail("manifest.xml : aucun <iq:product> déclaré", "manifest.xml")
    if len(ids) != len(set(ids)):
        fail("manifest.xml : un même appareil est déclaré plusieurs fois", "manifest.xml")

    permissions = application.find(f"{{{IQ_NS}}}permissions")
    declared = (
        {p.get("id", "") for p in permissions.findall(f"{{{IQ_NS}}}uses-permission")}
        if permissions is not None
        else set()
    )
    # The background service reads nothing privileged, but it wakes on a
    # temporal event (Background) and pushes the snapshot to the phone
    # (Communications). Losing either silently breaks the whole app.
    for required in ("Background", "Communications"):
        if required not in declared:
            fail(
                f"manifest.xml : permission « {required} » manquante — le service "
                "d'arrière-plan ne fonctionnera pas",
                "manifest.xml",
            )
    if declared:
        ok(f"permissions déclarées : {', '.join(sorted(declared))}")

    return [i for i in ids if i], drawable_id


def png_dimensions(relative_path: str) -> tuple[int | None, int | None]:
    """Width and height from a PNG's IHDR chunk, which is always first."""
    path = os.path.join(ROOT, relative_path)
    try:
        with open(path, "rb") as handle:
            header = handle.read(24)
    except OSError as exc:
        fail(f"lecture impossible de {relative_path} : {exc}", relative_path)
        return None, None
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        fail(f"{relative_path} : PNG illisible (en-tête IHDR absent)", relative_path)
        return None, None
    return (
        int.from_bytes(header[16:20], "big"),
        int.from_bytes(header[20:24], "big"),
    )


def svg_dimensions(relative_path: str) -> tuple[int | None, int | None]:
    root = parse_xml(relative_path)
    if root is None:
        return None, None

    def to_pixels(raw: str | None) -> int | None:
        if raw is None:
            return None
        match = re.fullmatch(r"\s*(\d+)(?:\.0+)?(?:px)?\s*", raw)
        return int(match.group(1)) if match else None

    width, height = to_pixels(root.get("width")), to_pixels(root.get("height"))
    if width is not None and height is not None:
        return width, height

    # An SVG may carry its size in the viewBox alone ("minX minY width height"),
    # which is just as valid a 70pt icon as width="70" height="70".
    box = (root.get("viewBox") or "").replace(",", " ").split()
    if len(box) == 4:
        try:
            return int(float(box[2])), int(float(box[3]))
        except ValueError:
            pass
    return width, height


def icon_dimensions(relative_path: str) -> tuple[int | None, int | None]:
    """Pixel size of a launcher icon, whichever format it is stored in."""
    extension = os.path.splitext(relative_path)[1].lower()
    if extension == ".png":
        return png_dimensions(relative_path)
    if extension == ".svg":
        return svg_dimensions(relative_path)
    named = extension or "sans extension"
    fail(
        f"{relative_path} : format d'icône non reconnu « {named} » — attendu .svg ou .png",
        relative_path,
    )
    return None, None


def check_device_resources(device: str, drawable_id: str) -> None:
    folder = f"resources-{device}"
    drawables_path = f"{folder}/drawables/drawables.xml"
    root = parse_xml(drawables_path)
    if root is None:
        return

    bitmaps = {b.get("id"): b.get("filename") for b in root.findall("bitmap")}
    if drawable_id not in bitmaps:
        fail(
            f"{drawables_path} : aucun bitmap d'id « {drawable_id} » — le "
            "launcherIcon du manifeste ne se résoudra pas",
            drawables_path,
        )
        return

    filename = bitmaps[drawable_id] or ""
    icon_path = f"{folder}/drawables/{filename}"
    if not os.path.exists(os.path.join(ROOT, icon_path)):
        fail(f"{drawables_path} : le fichier « {filename} » n'existe pas", drawables_path)
        return

    expected = LAUNCHER_ICON_PX.get(device)
    if expected is None:
        fail(
            f"appareil « {device} » absent de LAUNCHER_ICON_PX dans "
            "tools/validate_project.py — relever launcherIcon dans le "
            "compiler.json de l'appareil et ajouter la ligne",
        )
        return

    width, height = icon_dimensions(icon_path)
    if width is None or height is None:
        return
    if width != expected or height != expected:
        fail(
            f"{icon_path} : l'icône fait {width}×{height}, l'appareil « {device} » "
            f"attend {expected}×{expected} — le compilateur redimensionnerait et "
            "avertirait",
            icon_path,
        )
    else:
        ok(f"{device} : icône {expected}×{expected}")


def check_strings() -> None:
    root = parse_xml("resources/strings/strings.xml")
    if root is None:
        return
    ids = {s.get("id") for s in root.findall("string")}
    if "AppName" not in ids:
        fail(
            "resources/strings/strings.xml : chaîne « AppName » manquante",
            "resources/strings/strings.xml",
        )
    else:
        ok(f"chaînes définies : {', '.join(sorted(i for i in ids if i))}")


def check_jungle() -> None:
    path = os.path.join(ROOT, "monkey.jungle")
    if not os.path.exists(path):
        fail("monkey.jungle manquant", "monkey.jungle")
        return
    with open(path, encoding="utf-8") as handle:
        content = handle.read()
    match = re.search(r"^\s*project\.manifest\s*=\s*(\S+)\s*$", content, re.MULTILINE)
    if match is None:
        fail("monkey.jungle : aucune ligne « project.manifest = … »", "monkey.jungle")
    elif not os.path.exists(os.path.join(ROOT, match.group(1))):
        fail(
            f"monkey.jungle : project.manifest pointe vers « {match.group(1)} », "
            "qui n'existe pas",
            "monkey.jungle",
        )
    else:
        ok(f"monkey.jungle → {match.group(1)}")


def check_sources() -> None:
    source_dir = os.path.join(ROOT, "source")
    if not os.path.isdir(source_dir):
        fail("dossier source/ manquant")
        return
    modules = sorted(f for f in os.listdir(source_dir) if f.endswith(".mc"))
    if not modules:
        fail("source/ ne contient aucun fichier .mc")
    else:
        ok(f"{len(modules)} modules Monkey C")


# Anything that can carry a private key or a signing identity. The Connect IQ
# developer key is a .der, but the repository also holds Apple signing material,
# and an all-clear that only knew about .der would be read as covering both.
KEY_EXTENSIONS = (".der", ".pem", ".p12", ".key", ".p8", ".pfx", ".jks", ".keystore")


def check_no_key_material() -> None:
    """A developer key in the tree would be a publishing-identity leak.

    Scans the whole repository, not just this project: CI checks out everything,
    and an all-clear scoped to FouleeConnectIQ/ would read as repository-wide.
    """
    scan_root = os.path.dirname(ROOT)
    leaked = []
    for directory, dirs, files in os.walk(scan_root):
        # Prune by path component — a substring test on ".git" also skips
        # .github/, which is exactly where a leaked key would be worst.
        dirs[:] = [d for d in dirs if d not in (".git", "node_modules", ".build")]
        for name in files:
            if name.lower().endswith(KEY_EXTENSIONS):
                leaked.append(os.path.relpath(os.path.join(directory, name), scan_root))
    if leaked:
        fail(
            "matériel de clé présent dans le dépôt : "
            + ", ".join(sorted(leaked))
            + " — la clé développeur ne doit jamais quitter $HOME/.garmin",
        )
    else:
        ok("aucun matériel de clé dans le dépôt")


# `resources-<suffix>` is not only a device folder: the SDK's own default.jungle
# resolves the same prefix for language codes (`resources-fre`, and this app
# declares <iq:language>fre</iq:language>) and for screen qualifiers
# (`resources-round-416x416`). Flagging those as orphans would turn CI red on a
# perfectly ordinary localization commit, so the orphan check only speaks up for
# a suffix that looks like a device id.
SDK_QUALIFIER = re.compile(
    r"""^(
        [a-z]{3}                                  # language code, e.g. fre
        | (round|semi-round|semi-octagon|rectangle)(-\d+x\d+)?
        | \d+x\d+
    )$""",
    re.VERBOSE,
)


def check_orphan_resources(devices: list[str]) -> None:
    declared = set(devices)
    for entry in sorted(os.listdir(ROOT)):
        if not entry.startswith("resources-"):
            continue
        if not os.path.isdir(os.path.join(ROOT, entry)):
            continue
        suffix = entry[len("resources-") :]
        if suffix in declared or SDK_QUALIFIER.fullmatch(suffix):
            continue
        fail(
            f"{entry}/ ne correspond à aucun <iq:product> du manifeste — "
            "à supprimer, ou l'appareil à réintégrer",
        )


def main() -> int:
    print(f"Validation du projet Connect IQ ({ROOT})")

    devices, drawable_id = check_manifest()
    check_jungle()
    check_sources()
    check_strings()
    if drawable_id is None:
        fail(
            "manifest.xml : launcherIcon illisible — impossible de vérifier les "
            "icônes des appareils",
            "manifest.xml",
        )
    else:
        for device in devices:
            check_device_resources(device, drawable_id)
    check_no_key_material()
    check_orphan_resources(devices)

    print()
    if errors:
        print(f"ÉCHEC : {len(errors)} problème(s)")
        for message in errors:
            print(f"  - {message}")
        return 1
    # `notes` counts the checks that report something, one per device for the
    # icons — deliberately not advertised as a fixed number of checks, since it
    # tracks the size of the device matrix.
    print(f"OK : {len(notes)} points vérifiés, {len(devices)} appareils")
    return 0


if __name__ == "__main__":
    sys.exit(main())
