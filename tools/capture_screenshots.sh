#!/bin/bash
# Regenerate the raw App Store screenshots (issues #235, #239).
#
# Runs a UI test target against a booted simulator with the app in capture mode,
# then pulls the PNGs out of the result bundle into
# appstore-screenshots/raw/<set>/. Unattended: no Health data to enter by hand,
# no manual navigation, and the same numbers whatever day it is run.
#
#   tools/capture_screenshots.sh                        # iPhone 6.9"
#   tools/capture_screenshots.sh "iPhone 17 Pro" iphone-6.3
#   tools/capture_screenshots.sh 02175924-56FF-…-0216   # a UDID, when a name is
#                                                       # ambiguous
#   tools/capture_screenshots.sh --watch                # Apple Watch 46 mm
#   tools/capture_screenshots.sh --watch "Apple Watch Ultra 3 (49mm)"
#
# The first argument is a simulator NAME or a UDID. A name shared by two
# available simulators is refused rather than resolved: the runtime a same-named
# device runs decides what the PNGs look like — verified, all ten files differ
# between iOS 26.0 and 26.5 on the same device model — so picking one silently
# would make "the same numbers whatever day it is run" quietly depend on which
# runtimes happen to be installed.
#
# `--watch` runs the wrist half: another platform, another scheme, another
# output folder, and no status-bar pinning (watchOS refuses it — see below).
# Everything downstream, from the result bundle to the export, is the same.
#
# Output is NOT tracked by git: appstore-screenshots/ is ignored on purpose
# (#72), and generated PNGs must stay that way.
set -euo pipefail

PLATFORM="iOS"
if [ "${1:-}" = "--watch" ]; then
  PLATFORM="watchOS"
  shift
fi

if [ "$PLATFORM" = "watchOS" ]; then
  DEVICE="${1:-Apple Watch Series 11 (46mm)}"   # 416 × 496, the App Store size
  SET_NAME="${2:-watch}"
  SCHEME="FouleeWatchScreenshots"
  SIMULATOR_PLATFORM="watchOS Simulator"
  BUNDLE_ID="com.eno33.foulee.watchkitapp"
  # The test attaches "watch-01-today"; xcresulttool exports it as
  # "watch-01-today_0_<uuid>.png".
  NAME_PATTERN='^(watch-\d\d-[a-z]+)'
else
  DEVICE="${1:-iPhone 17 Pro Max}"   # 6.9" — 1320 × 2868, the App Store size
  SET_NAME="${2:-iphone-6.9}"
  SCHEME="FouleeScreenshots"
  SIMULATOR_PLATFORM="iOS Simulator"
  BUNDLE_ID="com.eno33.foulee"
  # The test attaches "02_home"; xcresulttool exports it as
  # "02_home_0_<uuid>.png". Anything else in the bundle (automatic failure
  # screenshots, activity logs, the screen recording) is not ours.
  NAME_PATTERN='^(\d\d_[a-z]+)'
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/appstore-screenshots/raw/$SET_NAME"
WORK_DIR="$(mktemp -d)"
RESULT_BUNDLE="$WORK_DIR/screenshots.xcresult"
trap 'rm -rf "$WORK_DIR"' EXIT

cd "$REPO_ROOT"

if [ ! -d "Foulee.xcworkspace" ]; then
  echo "==> Generating the workspace (tuist)"
  tuist install
  tuist generate --no-open
fi

echo "==> Resolving simulator: $DEVICE"
if ! UDID="$(xcrun simctl list devices available -j \
  | python3 -c "
import json, sys
wanted = sys.argv[1]
devices = json.load(sys.stdin)['devices']
matches = [
    (runtime, device)
    for runtime, listed in devices.items()
    for device in listed
    if device['name'] == wanted or device['udid'].lower() == wanted.lower()
]
if not matches:
    sys.stderr.write(
        'No available simulator named (or with UDID) %r.\n'
        'Create one in Xcode, or pass another name.\n'
        'Note: the App Store 6.9\" slot needs a 1320 x 2868 device,\n'
        'and the Apple Watch slot a 416 x 496 one.\n' % wanted
    )
    sys.exit(1)
if len(matches) > 1:
    sys.stderr.write('%d available simulators are named %r:\n' % (len(matches), wanted))
    for runtime, device in matches:
        sys.stderr.write(
            '  %s  (%s)\n' % (device['udid'], runtime.rsplit('.', 1)[-1])
        )
    sys.stderr.write(
        'They render differently. Re-run with the UDID you mean.\n'
    )
    sys.exit(1)
print(matches[0][1]['udid'])
" "$DEVICE")"; then
  exit 1
fi

echo "==> Booting $UDID"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

if [ "$PLATFORM" = "watchOS" ]; then
  # No status bar to pin: watchOS answers `status_bar override` with "Status
  # bar overrides not supported on this platform", and the time it draws over
  # every app is the host's. That single overlay is the one part of a watch
  # capture this script cannot make reproducible — see docs/RELEASE.md § 9.1.
  echo "==> No status-bar pinning on watchOS (unsupported by simctl)"
else
  # The status bar is part of the screenshot, so it has to be as fixed as the
  # data behind it. Apple's own marketing time, full bars, charged.
  echo "==> Pinning the status bar"
  xcrun simctl status_bar "$UDID" override \
    --time "09:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100
fi

# A leftover install carries the previous run's granted permissions and its
# own UserDefaults. Capture mode reads neither, but a stale system alert left
# on screen (Santé, notifications) from an ordinary run of the app would sit in
# front of the first tap. Start from nothing.
#
# On the watch it does one thing more: it clears the app-group container, so
# `WatchSyncStore` finds no payload and « Démarrer » starts a session outright
# instead of asking which activity — the one screen of the watch capture that
# would otherwise depend on what the developer's own phone had synced.
echo "==> Removing any previous install"
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "==> Running the capture"
xcodebuild test \
  -workspace Foulee.xcworkspace \
  -scheme "$SCHEME" \
  -destination "platform=$SIMULATOR_PLATFORM,id=$UDID" \
  -configuration Debug \
  -resultBundlePath "$RESULT_BUNDLE" \
  | (xcbeautify 2>/dev/null || cat)

echo "==> Exporting the attachments"
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$WORK_DIR/attachments" >/dev/null

mkdir -p "$OUTPUT_DIR"
python3 - "$WORK_DIR/attachments" "$OUTPUT_DIR" "$NAME_PATTERN" <<'PY'
import json, os, re, shutil, sys

source, destination, pattern = sys.argv[1], sys.argv[2], sys.argv[3]
with open(os.path.join(source, "manifest.json")) as handle:
    manifest = json.load(handle)

OURS = re.compile(pattern)
copied = []


def walk(node):
    if isinstance(node, list):
        for item in node:
            walk(item)
        return
    if not isinstance(node, dict):
        return
    exported = node.get("exportedFileName")
    name = node.get("suggestedHumanReadableName") or node.get("name") or ""
    match = OURS.match(name)
    if exported and match:
        shutil.copyfile(
            os.path.join(source, exported),
            os.path.join(destination, match.group(1) + ".png"),
        )
        copied.append(match.group(1))
    for value in node.values():
        walk(value)


walk(manifest)
if not copied:
    sys.exit("No screenshots found in the result bundle")
for name in sorted(set(copied)):
    print("   " + name + ".png")
PY

echo "==> Done — $OUTPUT_DIR"
