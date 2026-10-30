#!/bin/bash
# A walk through the iPhone app on the iPhone Duo's inner screen (issue #665).
#
#   tools/smoke_test.sh
#
# Runs the FouleeSmoke scheme on an iPhone Duo simulator, created by
# tools/newest_iphone_simulator.sh under the name « Foulee Duo », the same way
# on a Mac and in CI: main screens and their way back, then an outing started
# and ended. The simulator stays unfolded — neither simctl nor XCTest can fold
# it — so the outer screen is checked by hand.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
# Where CI's report-test-failure action looks for result bundles.
RESULT_BUNDLE=build/results/smoke.xcresult
# Its own build folder, outside the checkout, as tools/accessibility_audit.sh
# does.
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/FouleeSmoke"
rm -rf "$RESULT_BUNDLE" && mkdir -p build/results

source tools/newest_iphone_simulator.sh "Foulee Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo

# No diagnostics collection (issue #420): the iOS 27 simulator never answers.
xcodebuild test \
  -workspace Foulee.xcworkspace \
  -scheme FouleeSmoke \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -collect-test-diagnostics never \
  | (xcbeautify 2>/dev/null || cat)
