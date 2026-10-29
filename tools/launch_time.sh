#!/bin/bash
# The iPhone app's cold launch time against its budget (issue #613).
#
#   tools/launch_time.sh            # fails when the launch is clearly slower
#   tools/launch_time.sh --record   # rewrites the budget from this run
#
# Runs the FouleeLaunchTime scheme, which launches the app seven times in
# capture mode and measures each launch until its home is on screen. The
# fastest of those launches is compared with
# FouleeLaunchTime/LaunchTimeBudget.json: more than `tolerancePercent` above
# the recorded one fails. The fastest rather than the median: a busy CI runner
# only ever adds time, up to twice as much on one launch out of seven, while a
# real regression — a heavy query or a synchronous load moved onto the launch
# path — slows every launch.
#
# Capture mode exists only in Debug, so this is a Debug launch: slower than
# what a user sees, and only meaningful compared with itself.
#
# Each run writes what the budget would be after it to
# build/launch/LaunchTimeBudget.json; CI keeps it as an artifact. The time
# depends on the machine: record on CI's simulator — take the artifact — rather
# than on a Mac, and read the diff before committing, since a higher time is
# a slowdown accepted.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
RECORD=0
[ "${1:-}" = "--record" ] && RECORD=1
OUT=build/launch
BUDGET=FouleeLaunchTime/LaunchTimeBudget.json
# Where CI's report-test-failure action looks for result bundles.
RESULT_BUNDLE=build/results/launch.xcresult
# Its own build folder, outside the checkout, as tools/accessibility_audit.sh
# does.
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/FouleeLaunch"
rm -rf "$OUT" "$RESULT_BUNDLE" && mkdir -p "$OUT" build/results

source tools/newest_iphone_simulator.sh "Foulee Launch"

# No diagnostics collection (issue #420): the iOS 27 simulator never answers.
xcodebuild test \
  -workspace Foulee.xcworkspace \
  -scheme FouleeLaunchTime \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -collect-test-diagnostics never \
  | (xcbeautify 2>/dev/null || cat)

xcrun xcresulttool get test-results metrics --path "$RESULT_BUNDLE" > "$OUT/metrics.json"

python3 - "$OUT/metrics.json" "$OUT/LaunchTimeBudget.json" "$SIMULATOR_NAME" "$BUDGET" "$RECORD" <<'PY'
import json, sys

metrics, destination, device, budget_path, record = sys.argv[1:6]
with open(metrics) as handle:
    tests = json.load(handle)
measurements = [
    value
    for test in tests
    for run in test["testRuns"]
    for metric in run["metrics"]
    if metric["identifier"].startswith("com.apple.dt.XCTMetric_Clock")
    for value in metric["measurements"]
]
if not measurements:
    sys.exit(f"No launch measurement found in the result bundle:\n{json.dumps(tests, indent=2)}")
fastest = round(min(measurements), 3)

with open(budget_path) as handle:
    budget = json.load(handle)
with open(destination, "w") as handle:
    json.dump(budget | {"fastestSeconds": fastest, "recordedOn": device}, handle, indent=2, sort_keys=True)
    handle.write("\n")

limit = budget["fastestSeconds"] * (1 + budget["tolerancePercent"] / 100)
print(f"Launch: fastest {fastest:.3f} s over {len(measurements)} launches, "
      f"budget {budget['fastestSeconds']:.3f} s + {budget['tolerancePercent']} % = {limit:.3f} s")
if budget["recordedOn"] != device:
    print(f"warning: the budget was recorded on {budget['recordedOn']}, this run is on {device}")
if record == "0" and fastest > limit:
    sys.exit(f"error: the launch takes {fastest:.3f} s, over its budget of {limit:.3f} s")
PY

if [ "$RECORD" = 1 ]; then
  cp "$OUT/LaunchTimeBudget.json" "$BUDGET"
  echo "==> Budget rewritten: $BUDGET"
fi
