#!/bin/bash
# Regenerate the raw App Store screenshots (issue #235).
#
# Runs the FouleeScreenshots UI test target against a booted simulator with the
# app in capture mode, then pulls the PNGs out of the result bundle into
# appstore-screenshots/raw/<set>/. Unattended: no Health data to enter by hand,
# no manual navigation, and the same numbers whatever day it is run.
#
#   tools/capture_screenshots.sh                       # iPhone 6.9"
#   tools/capture_screenshots.sh "iPhone 17 Pro" iphone-6.3
#   tools/capture_screenshots.sh 02175924-56FF-…-0216  # a UDID, when a name is
#                                                      # ambiguous
#
# The first argument is a simulator NAME or a UDID. A name shared by two
# available simulators is refused rather than resolved: the runtime a same-named
# device runs decides what the PNGs look like — verified, all ten files differ
# between iOS 26.0 and 26.5 on the same device model — so picking one silently
# would make "the same numbers whatever day it is run" quietly depend on which
# runtimes happen to be installed.
#
# Output is NOT tracked by git: appstore-screenshots/ is ignored on purpose
# (#72), and generated PNGs must stay that way.
set -euo pipefail

DEVICE="${1:-iPhone 17 Pro Max}"   # 6.9" — 1320 × 2868, the App Store size
SET_NAME="${2:-iphone-6.9}"

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
        'Note: the App Store 6.9\" slot needs a 1320 x 2868 device.\n' % wanted
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

# The status bar is part of the screenshot, so it has to be as fixed as the
# data behind it. Apple's own marketing time, full bars, charged.
echo "==> Pinning the status bar"
xcrun simctl status_bar "$UDID" override \
  --time "09:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

# A leftover install carries the previous run's granted permissions and its
# own UserDefaults. Capture mode reads neither, but a stale system alert left
# on screen (Santé, notifications) from an ordinary run of the app would sit in
# front of the first tap. Start from nothing.
echo "==> Removing any previous install"
xcrun simctl uninstall "$UDID" com.eno33.foulee >/dev/null 2>&1 || true

echo "==> Running the capture"
xcodebuild test \
  -workspace Foulee.xcworkspace \
  -scheme FouleeScreenshots \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration Debug \
  -resultBundlePath "$RESULT_BUNDLE" \
  | (xcbeautify 2>/dev/null || cat)

echo "==> Exporting the attachments"
xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$WORK_DIR/attachments" >/dev/null

mkdir -p "$OUTPUT_DIR"
python3 - "$WORK_DIR/attachments" "$OUTPUT_DIR" <<'PY'
import json, os, re, shutil, sys

source, destination = sys.argv[1], sys.argv[2]
with open(os.path.join(source, "manifest.json")) as handle:
    manifest = json.load(handle)

# The test attaches "02_home"; xcresulttool exports it as
# "02_home_0_<uuid>.png". Anything else in the bundle (automatic failure
# screenshots, activity logs, the screen recording) is not ours.
OURS = re.compile(r"^(\d\d_[a-z]+)")
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
