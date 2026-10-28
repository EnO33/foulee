#!/bin/bash
# Xcode's accessibility audit on the iPhone app's main screens (issue #602).
#
#   tools/accessibility_audit.sh            # fails on a finding the baseline lacks
#   tools/accessibility_audit.sh --record   # rewrites the baseline from this run
#
# Runs the FouleeAccessibilityAudit scheme, which attaches every finding of
# every screen to its result bundle, known or not. Each run writes them all to
# build/accessibility/AccessibilityAuditBaseline.json — what the baseline would
# be after this run; CI keeps it as an artifact. `--record` copies it over
# FouleeAccessibilityAudit/AccessibilityAuditBaseline.json: run it after fixing
# a finding, so the fix cannot quietly come undone, and read the diff before
# committing — a line added there is a regression accepted.
#
# The audit depends on the screen and the iOS version: a smaller iPhone clips
# other texts. The simulator is therefore created here, the same way on a Mac
# and in CI — the newest iOS runtime and the newest iPhone it supports, under
# the name « Foulee Audit » — and the baseline records which one it was. Record
# on the same pair as CI, or take the file from the CI artifact.
#
# Even on the same pair, a few contrast findings differ between a Mac and CI:
# the slower runner is audited at another moment of the screen's drawing, and
# the same text is then reported by name rather than as an unnamed element. The
# baseline is the union of both (issue #602); after a `--record` on a Mac, add
# what the next CI run's artifact reports on top, rather than replacing it.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
RECORD=0
[ "${1:-}" = "--record" ] && RECORD=1
OUT=build/accessibility
BASELINE=FouleeAccessibilityAudit/AccessibilityAuditBaseline.json
# Where CI's report-test-failure action looks for result bundles.
RESULT_BUNDLE=build/results/accessibility.xcresult
# Its own build folder, outside the checkout, as tools/check_build.sh does: a
# clone under ~/Documents is protected by macOS privacy controls, and a folder
# shared with other builds can link stale objects from another branch.
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/FouleeAudit"
rm -rf "$OUT" "$RESULT_BUNDLE" && mkdir -p "$OUT" build/results

RUNTIME=$(xcrun simctl list runtimes available -j \
  | jq -c '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version) | last')
RUNTIME_ID=$(echo "$RUNTIME" | jq -r .identifier)
DEVICE_TYPE=$(echo "$RUNTIME" | jq -c '[.supportedDeviceTypes[] | select(.productFamily == "iPhone")] | last')
DEVICE_TYPE_ID=$(echo "$DEVICE_TYPE" | jq -r .identifier)
DEVICE_ON="$(echo "$DEVICE_TYPE" | jq -r .name), iOS $(echo "$RUNTIME" | jq -r .version)"
UDID=$(xcrun simctl list devices available -j \
  | jq -r --arg runtime "$RUNTIME_ID" --arg type "$DEVICE_TYPE_ID" \
    '.devices[$runtime] // [] | map(select(.name == "Foulee Audit" and .deviceTypeIdentifier == $type)) | first | .udid // empty')
[ -n "$UDID" ] || UDID=$(xcrun simctl create "Foulee Audit" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
echo "==> Auditing on $DEVICE_ON ($UDID)"
# Booted before the run, for the same reason as CI's iOS job (issue #404).
xcrun simctl bootstatus "$UDID" -b >/dev/null

# The test status is kept for the end: the findings are exported either way.
# No diagnostics collection (issue #420): the iOS 27 simulator never answers.
set +e
xcodebuild test \
  -workspace Foulee.xcworkspace \
  -scheme FouleeAccessibilityAudit \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -collect-test-diagnostics never \
  | (xcbeautify 2>/dev/null || cat)
STATUS=${PIPESTATUS[0]}
set -e

xcrun xcresulttool export attachments \
  --path "$RESULT_BUNDLE" \
  --output-path "$OUT/attachments" >/dev/null

python3 - "$OUT/attachments" "$OUT/AccessibilityAuditBaseline.json" "$DEVICE_ON" "$BASELINE" <<'PY'
import json, os, sys

source, destination, device, baseline = sys.argv[1:5]
with open(os.path.join(source, "manifest.json")) as handle:
    manifest = json.load(handle)

# Not a screen: the simulator the findings were recorded on.
RECORDED_ON = "_recordedOn"
screens = {RECORDED_ON: [device]}


def walk(node):
    if isinstance(node, list):
        for item in node:
            walk(item)
        return
    if not isinstance(node, dict):
        return
    exported = node.get("exportedFileName")
    name = node.get("suggestedHumanReadableName") or node.get("name") or ""
    if exported and name.startswith("a11y-"):
        with open(os.path.join(source, exported)) as handle:
            screens.update(json.load(handle))
    for value in node.values():
        walk(value)


walk(manifest)
if len(screens) == 1:
    sys.exit("No audit report found in the result bundle")
with open(destination, "w") as handle:
    json.dump(screens, handle, ensure_ascii=False, indent=2, sort_keys=True)
    handle.write("\n")
print(f"{sum(map(len, screens.values())) - 1} findings on {len(screens) - 1} screens → {destination}")

with open(baseline) as handle:
    recorded = json.load(handle).get(RECORDED_ON, ["nothing yet"])[0]
if recorded != device:
    print(f"warning: the baseline was recorded on {recorded}, this run is on {device}")
PY

if [ "$RECORD" = 1 ]; then
  cp "$OUT/AccessibilityAuditBaseline.json" "$BASELINE"
  echo "==> Baseline rewritten: $BASELINE"
  exit 0
fi
exit "$STATUS"
