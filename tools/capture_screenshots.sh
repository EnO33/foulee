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
#   tools/capture_screenshots.sh --watch "Apple Watch SE 3 (40mm)" probe-40mm
#   tools/capture_screenshots.sh --dark "" review-dark   # visual review only
#   tools/capture_screenshots.sh --text-size accessibility-large "" review-a11y
#   tools/capture_screenshots.sh --watch --text-size accessibility-extra-extra-extra-large "" review-a11y
#   tools/capture_screenshots.sh --language en          # the English set
#   tools/capture_screenshots.sh --watch --language en
#   tools/capture_screenshots.sh --language en --pseudo "" review-pseudo
#
# The first argument is a simulator NAME or a UDID. A name shared by two
# available simulators is refused rather than resolved: the runtime a same-named
# device runs decides what the PNGs look like — verified, all ten files differ
# between iOS 26.0 and 26.5 on the same device model — so picking one silently
# would make "the same numbers whatever day it is run" quietly depend on which
# runtimes happen to be installed.
#
# The SECOND argument is the output set, and it is only optional when the device
# is the one the default set is sized for. Run another device without naming a
# set and the script refuses instead of writing: the default folders feed
# `compose_appstore_screenshots.swift`, which accepts exactly one resolution per
# family, so an off-size run into `watch/` would overwrite a good set with grabs
# the composer then rejects one by one. Verified: `Apple Watch Ultra 3 (49mm)`
# grabs 422 × 514, and three of those in `watch/` compose 0 boards. A set name
# other than the default is never checked — it is a probe (a smaller wrist, a
# second runtime), it is not composed, and it cannot clobber the real one.
#
# `--watch` runs the wrist half: another platform, another scheme, another
# output folder, and no status-bar pinning (watchOS refuses it — see below).
# Everything downstream, from the result bundle to the export, is the same.
#
# `--dark` seeds the dark theme and `--text-size <simctl size>` sets the
# simulator's text size for the run (issue #408): both exist for the visual
# review of a new SDK, never for the store boards, so they require a set name
# other than the default one. An empty device argument ("") keeps the default
# device.
#
# `--language en` runs the app in US English (issue #592) and writes under
# appstore-screenshots/en-US/raw/<set>/ instead, where
# `compose_appstore_screenshots.swift --locale en-US` reads it: the same set
# names, the same size guard, a tree of its own so neither language can
# overwrite the other. French is the default and keeps raw/<set>/.
#
# `--pseudo` adds Xcode's double-length pseudo-language (issue #594): every
# localized string written twice, to see what a longer translation truncates.
# A review like `--dark`, so it needs a set name too. Combine it with
# `--language` to review either language.
#
# Output is NOT tracked by git: appstore-screenshots/ is ignored on purpose
# (#72), and generated PNGs must stay that way.
set -euo pipefail

PLATFORM="iOS"
DARK=""
TEXT_SIZE=""
LANGUAGE="fr"
PSEUDO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --watch) PLATFORM="watchOS"; shift ;;
    --dark) DARK="1"; shift ;;
    --text-size) TEXT_SIZE="${2:?--text-size needs a simctl content size}"; shift 2 ;;
    --language) LANGUAGE="${2:?--language needs fr or en}"; shift 2 ;;
    --pseudo) PSEUDO="1"; shift ;;
    *) break ;;
  esac
done

if [ "$PLATFORM" = "watchOS" ]; then
  DEVICE="${1:-}"
  DEVICE="${DEVICE:-Apple Watch Series 11 (46mm)}"   # 416 × 496, the App Store size
  DEFAULT_SET="watch"
  DEFAULT_SET_SIZE="416x496"
  SCHEME="FouleeWatchScreenshots"
  SIMULATOR_PLATFORM="watchOS Simulator"
  BUNDLE_ID="com.eno33.foulee.watchkitapp"
  # The test attaches "watch-01-today"; xcresulttool exports it as
  # "watch-01-today_0_<uuid>.png".
  NAME_PATTERN='^(watch-\d\d-[a-z]+)'
else
  DEVICE="${1:-}"
  DEVICE="${DEVICE:-iPhone 17 Pro Max}"   # 6.9" — 1320 × 2868, the App Store size
  DEFAULT_SET="iphone-6.9"
  DEFAULT_SET_SIZE="1320x2868"
  SCHEME="FouleeScreenshots"
  SIMULATOR_PLATFORM="iOS Simulator"
  BUNDLE_ID="com.eno33.foulee"
  # The test attaches "02_home"; xcresulttool exports it as
  # "02_home_0_<uuid>.png". Anything else in the bundle (automatic failure
  # screenshots, activity logs, the screen recording) is not ours.
  NAME_PATTERN='^(\d\d_[a-z]+)'
fi
SET_NAME="${2:-$DEFAULT_SET}"

if { [ -n "$DARK" ] || [ -n "$TEXT_SIZE" ] || [ -n "$PSEUDO" ]; } && [ "$SET_NAME" = "$DEFAULT_SET" ]; then
  echo "--dark, --text-size and --pseudo are for reviews: name the set (e.g. review-dark)." >&2
  exit 1
fi
if [ -n "$DARK" ] && [ "$PLATFORM" = "watchOS" ]; then
  echo "--dark has no effect on the watch, which is always dark." >&2
  exit 1
fi

case "$LANGUAGE" in
  fr) RAW_ROOT="appstore-screenshots/raw" ;;
  en) RAW_ROOT="appstore-screenshots/en-US/raw" ;;
  *) echo "--language takes fr or en, not « $LANGUAGE »." >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/$RAW_ROOT/$SET_NAME"
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

# Guard the default set against a device it isn't sized for, before the run
# writes anything. `$OUTPUT_DIR` may already hold the set that is about to be
# uploaded, and this script's own export overwrites file by file — so a wrong
# device pointed at the default folder destroys a good capture and leaves
# behind grabs the composer refuses. One throwaway grab is enough to know.
if [ "$SET_NAME" = "$DEFAULT_SET" ]; then
  PROBE="$WORK_DIR/probe.png"
  xcrun simctl io "$UDID" screenshot "$PROBE" >/dev/null 2>&1
  PROBE_SIZE="$(sips -g pixelWidth -g pixelHeight "$PROBE" \
    | awk '/pixelWidth/ { w = $2 } /pixelHeight/ { h = $2 } END { print w "x" h }')"
  if [ "$PROBE_SIZE" != "$DEFAULT_SET_SIZE" ]; then
    if [ "$PLATFORM" = "watchOS" ]; then WATCH_FLAG="--watch "; else WATCH_FLAG=""; fi
    cat >&2 <<EOF
Refusing to write $RAW_ROOT/$DEFAULT_SET/.

  "$DEVICE" grabs $PROBE_SIZE, and that set is $DEFAULT_SET_SIZE — the only size
  compose_appstore_screenshots.swift accepts for it. Running it here would
  overwrite the set with grabs the composer then rejects one by one.

Name the run's own set if it is a probe (a smaller wrist, a second runtime):

  tools/capture_screenshots.sh $WATCH_FLAG"$DEVICE" my-probe

or pass a device that grabs $DEFAULT_SET_SIZE.
EOF
    exit 1
  fi
fi

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
if [ -n "$TEXT_SIZE" ] && [ "$PLATFORM" = "watchOS" ]; then
  # simctl cannot set the watch's text size — verified on watchOS 27:
  # "Runtime does not support dynamic text". The UI test hands it to the app
  # as a launch argument instead (issue #600).
  echo "==> Text size: $TEXT_SIZE (launch argument)"
elif [ -n "$TEXT_SIZE" ]; then
  echo "==> Text size: $TEXT_SIZE"
  xcrun simctl ui "$UDID" content_size "$TEXT_SIZE"
  # Back to the default afterwards: the simulator outlives the run, and the
  # next capture on it must not inherit a review's text size.
  trap 'xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1 || true; rm -rf "$WORK_DIR"' EXIT
fi

echo "==> Removing any previous install"
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# No diagnostics collection at the end (issue #420): the iOS 27 simulator
# never answers xcodebuild's request, which then waits out a 600 s timeout
# after a two-minute capture. The PNGs are attachments, not diagnostics.
echo "==> Running the capture"
TEST_RUNNER_FOULEE_CAPTURE_DARK="$DARK" \
TEST_RUNNER_FOULEE_CAPTURE_PSEUDO="$PSEUDO" \
TEST_RUNNER_FOULEE_CAPTURE_TEXT_SIZE="$TEXT_SIZE" \
TEST_RUNNER_FOULEE_CAPTURE_LANGUAGE="$LANGUAGE" xcodebuild test \
  -workspace Foulee.xcworkspace \
  -scheme "$SCHEME" \
  -destination "platform=$SIMULATOR_PLATFORM,id=$UDID" \
  -configuration Debug \
  -resultBundlePath "$RESULT_BUNDLE" \
  -collect-test-diagnostics never \
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
