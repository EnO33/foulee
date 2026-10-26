#!/usr/bin/env python3
"""Check the App Store listing in fastlane/metadata before it is published.

App Store Connect rejects a field over its limit only once `deliver` is
halfway through an upload (issue #581). This catches it on the pull request:
every field present and within its limit, keywords without spaces or words the
name and subtitle already index, URLs on https.

Usage: tools/check_store_metadata.py [metadata_dir]   (default fastlane/metadata)
"""

import re
import sys
from pathlib import Path

# App Store Connect's limits, in characters. Keywords are counted in UTF-8
# bytes: an accented letter takes two, and staying under 100 bytes keeps the
# field valid whichever way the form counts.
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "promotional_text": 170,
    "description": 4000,
    "release_notes": 4000,
}
KEYWORDS_BYTES = 100
URLS = ("support_url", "privacy_url", "marketing_url")
REQUIRED = (*LIMITS, "keywords", *URLS)


def words(text: str) -> set[str]:
    return {w.casefold() for w in re.findall(r"\w+", text)}


def check_locale(locale: Path) -> list[str]:
    fields = {}
    errors = []
    for field in REQUIRED:
        path = locale / f"{field}.txt"
        value = path.read_text(encoding="utf-8").strip() if path.exists() else ""
        if not value:
            errors.append(f"{path}: missing or empty")
        fields[field] = value

    for field, limit in LIMITS.items():
        if len(fields[field]) > limit:
            errors.append(f"{locale.name}/{field}.txt: {len(fields[field])} characters, limit {limit}")

    keywords = fields["keywords"]
    if len(keywords.encode("utf-8")) > KEYWORDS_BYTES:
        errors.append(f"{locale.name}/keywords.txt: {len(keywords.encode('utf-8'))} bytes, limit {KEYWORDS_BYTES}")
    if ", " in keywords or "\n" in keywords:
        errors.append(f"{locale.name}/keywords.txt: one line, commas without spaces (spaces count against the limit)")
    # The name and subtitle are indexed already: repeating their words wastes room.
    indexed = words(fields["name"]) | words(fields["subtitle"])
    repeated = sorted(words(keywords) & indexed)
    if repeated:
        errors.append(f"{locale.name}/keywords.txt: already in the name or subtitle: {', '.join(repeated)}")

    for field in URLS:
        if fields[field] and not fields[field].startswith("https://"):
            errors.append(f"{locale.name}/{field}.txt: not an https URL")
    return errors


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "fastlane/metadata")
    locales = sorted(p for p in root.iterdir() if p.is_dir() and p.name not in {"review_information", "trade_representative_contact_information"})
    if not locales:
        print(f"{root}: no locale folder", file=sys.stderr)
        return 1
    errors = [e for locale in locales for e in check_locale(locale)]
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print(f"Store metadata OK: {', '.join(p.name for p in locales)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
