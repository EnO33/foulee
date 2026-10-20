#!/usr/bin/env python3
"""Static checks on the Connect IQ project that need no Connect IQ SDK.

CI compiles the app for every device in -w -l 3, failing on any warning
(FouleeConnectIQ/README.md, "Intégration continue"): resources, launcher icons
and their sizes are the compiler's to check. This script runs first and in
seconds, and keeps to what the compiler cannot see: the production app id, the
iPhone listening to it, the API floor of the matrix, the manifest and
devices.json declaring the same watches, translations, orphan resource folders
and key material committed by mistake.

Exit code 0 when everything checks out, 1 otherwise. Every failure is printed
in GitHub's `::error` annotation format so it lands on the PR diff.
"""

from __future__ import annotations

import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

IQ_NS = "http://www.garmin.com/xml/connectiq"

# The device matrix: one row per watch, the hardware facts read from its
# compiler.json by tools/device_catalog.py --write, which also writes the
# manifest's <iq:products>.
DEVICES_FILE = "devices.json"


def load_devices() -> dict[str, dict]:
    with open(os.path.join(ROOT, DEVICES_FILE), encoding="utf-8") as handle:
        return {row["id"]: row for row in json.load(handle)}

# The application id of the *production* store entry, the one the committed
# manifest must carry. A beta build needs a different id (a beta app is a
# separate store entry): garmin-release.yml swaps it in its own checkout only,
# reading both values below. A manifest committed with the beta id would
# silently point every later release at the beta entry — both ids are
# well-formed UUIDs, so nothing else here would notice.
# Read by garmin-release.yml too: keep it on one line, in this form.
PRODUCTION_APP_ID = "859c7300a91149fdb6ce7e4453bfe59d"

# The id reserved for the beta store entry (store/README.md § 5). Read by
# garmin-release.yml for a beta tag: keep it on one line, in this form.
BETA_APP_ID = "a0d0785c31b84e24b4a30d6bfd950502"

# Where the iPhone app declares the watch apps it listens to. The phone only
# receives messages from an app whose id it registered, and nothing at runtime
# says when the two disagree: the snapshots are simply never delivered (#465).
# The floor of the device matrix: every device runs Connect IQ 5.0.0 or later.
# It also covers what the code needs: Application.Storage written from the
# background (3.2.0, ObjectStoreAccessException before, #469), a watch-app
# glance (4.0.0) and the session's ViewLoop (3.4.0). A manifest below it would
# claim devices the app was never compiled or checked against.
MIN_API_LEVEL = (5, 0, 0)

COMPANION_CONFIG = "Foulee/Connectivity/GarminConnectIQClient.swift"
COMPANION_IDS = {
    "productionApplicationUUID": PRODUCTION_APP_ID,
    "betaApplicationUUID": BETA_APP_ID,
}

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


def check_manifest() -> list[str]:
    """Validate manifest.xml and return the declared product ids."""
    root = parse_xml("manifest.xml")
    if root is None:
        return []

    application = root.find(f"{{{IQ_NS}}}application")
    if application is None:
        fail("manifest.xml : aucun élément <iq:application>", "manifest.xml")
        return []

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
            f"« {PRODUCTION_APP_ID} ». Le manifeste committé garde l'identifiant de "
            "production : une beta passe par un tag garmin-vX.Y.Z-betaN, qui fait "
            "le remplacement dans la CI (store/README.md § 5). Si l'identifiant "
            "de production a réellement changé, mettre PRODUCTION_APP_ID à jour "
            "dans tools/validate_project.py.",
            "manifest.xml",
        )
    else:
        ok(f"identifiant d'application : {app_id}")

    for attribute in ("entry", "launcherIcon", "minApiLevel", "name", "type"):
        if not application.get(attribute):
            fail(f"manifest.xml : attribut « {attribute} » manquant", "manifest.xml")

    check_min_api_level(application.get("minApiLevel", ""))

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

    return [i for i in ids if i]


def check_min_api_level(raw: str) -> None:
    if not raw:
        return  # already reported as a missing attribute
    try:
        declared = tuple(int(part) for part in raw.split("."))
    except ValueError:
        fail(f"manifest.xml : minApiLevel « {raw} » illisible", "manifest.xml")
        return
    required = ".".join(str(part) for part in MIN_API_LEVEL)
    if declared < MIN_API_LEVEL:
        fail(
            f"manifest.xml : minApiLevel « {raw} » sous {required}, le plancher "
            "de la matrice d'appareils",
            "manifest.xml",
        )
    else:
        ok(f"minApiLevel {raw} (≥ {required})")


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
    check_translations(ids)


def check_translations(default_ids: set[str | None]) -> None:
    """Every language folder defines exactly the default strings.

    A string missing from resources-fre silently falls back to the English
    default on a French watch; an extra one is dead. Neither makes monkeyc
    complain.
    """
    for entry in sorted(os.listdir(ROOT)):
        suffix = entry[len("resources-") :]
        if not entry.startswith("resources-") or not re.fullmatch(r"[a-z]{3}", suffix):
            continue
        relative = f"{entry}/strings/strings.xml"
        root = parse_xml(relative)
        if root is None:
            continue
        ids = {s.get("id") for s in root.findall("string")}
        missing, extra = default_ids - ids, ids - default_ids
        if missing or extra:
            fail(
                f"{relative} : chaînes manquantes {sorted(i for i in missing if i)}, "
                f"en trop {sorted(i for i in extra if i)} par rapport à resources/",
                relative,
            )
        else:
            ok(f"{entry} : {len(ids)} chaînes traduites")


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


def check_companion_ids() -> None:
    """The iPhone app must listen to the ids the watch app is packaged with."""
    path = os.path.join(os.path.dirname(ROOT), COMPANION_CONFIG)
    try:
        with open(path, encoding="utf-8") as handle:
            content = handle.read()
    except OSError as exc:
        fail(f"lecture impossible de {COMPANION_CONFIG} : {exc}")
        return

    for name, expected in COMPANION_IDS.items():
        match = re.search(rf'\b{name}\s*=\s*UUID\(uuidString:\s*"([^"]*)"\)', content)
        if match is None:
            fail(f"{COMPANION_CONFIG} : « {name} » introuvable")
            continue
        declared = match.group(1).replace("-", "").lower()
        if declared != expected:
            fail(
                f"{COMPANION_CONFIG} : {name} vaut « {match.group(1)} », l'app "
                f"montre est empaquetée sous « {expected} » — l'iPhone ne "
                "recevrait rien d'elle",
            )
        else:
            ok(f"iPhone à l'écoute de {name} ({expected})")


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


def check_matrix(devices: list[str], matrix: dict[str, dict]) -> None:
    """The manifest declares exactly the watches of devices.json: both are
    written together by tools/device_catalog.py --write."""
    declared, listed = set(devices), set(matrix)
    for device in sorted(declared - listed):
        fail(f"manifest.xml : « {device} » absent de {DEVICES_FILE}", "manifest.xml")
    for device in sorted(listed - declared):
        fail(f"{DEVICES_FILE} : « {device} » absent des <iq:products> du manifeste", DEVICES_FILE)
    if declared == listed:
        ok(f"manifest.xml et {DEVICES_FILE} : les mêmes {len(listed)} appareils")


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

    devices = check_manifest()
    matrix = load_devices()
    check_matrix(devices, matrix)
    check_jungle()
    check_sources()
    check_strings()
    check_companion_ids()
    check_no_key_material()
    check_orphan_resources(devices)

    print()
    if errors:
        print(f"ÉCHEC : {len(errors)} problème(s)")
        for message in errors:
            print(f"  - {message}")
        return 1
    print(f"OK : {len(notes)} points vérifiés, {len(devices)} appareils")
    return 0


if __name__ == "__main__":
    sys.exit(main())
