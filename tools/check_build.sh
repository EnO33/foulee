#!/bin/bash
# Compile everything CI compiles, on this Mac, and print only what fails
# (issue #425).
#
#   tools/check_build.sh
#
# Four passes, logged into build/check (gitignored):
#
#   1. SwiftLint, strict, when it is installed.
#   2. FouleeKit's tests on macOS — no simulator, a few seconds.
#   3. The iPhone app, its extensions, the embedded watch app and FouleeTests
#      (`build-for-testing`, iOS Simulator).
#   4. The watch app and FouleeWatchTests (`build-for-testing`, watchOS
#      Simulator).
#
# Builds for this Mac's architecture only: a generic simulator destination
# would otherwise compile every architecture. The simulator tests themselves
# are left to CI; this is the minute-long loop before a push.
#
# The build itself goes to ~/Library/Developer/Xcode/DerivedData/FouleeCheck,
# outside the checkout: a clone under ~/Documents is protected by macOS
# privacy controls, and the test runner xcodebuild starts may not read it — the
# kit's test bundle then fails to load, reported as « executable not found ».
#
# Exits non-zero when any pass fails. Full logs: build/check/<pass>.log.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
out=build/check
dd="$HOME/Library/Developer/Xcode/DerivedData/FouleeCheck"
mkdir -p "$out"
arch=$(uname -m)
failed=()

echo "▶ Xcode: $(xcodebuild -version | head -1)"
tuist install >/dev/null && tuist generate --no-open >/dev/null || {
    echo "✖ tuist generate failed — run it by hand to see why"
    exit 1
}

# Prints the errors of one pass, without the noise around them.
report() {
    grep -E "error:|\*\* (BUILD|TEST|TEST BUILD) FAILED|Test .* failed|✘" "$1" \
        | sed "s#$PWD/##" | sort -u
}

pass() {
    local name="$1"
    shift
    echo "▶ $name"
    if "$@" >"$out/$name.log" 2>&1; then
        echo "  ✔ ok"
    else
        report "$out/$name.log"
        failed+=("$name")
    fi
}

if command -v swiftlint >/dev/null; then
    pass lint swiftlint lint --strict --quiet
else
    echo "▶ lint — skipped, swiftlint not installed"
fi

pass kit xcodebuild test \
    -workspace Foulee.xcworkspace -scheme FouleeKit \
    -destination "platform=macOS,arch=$arch" \
    -derivedDataPath "$dd"

pass ios xcodebuild build-for-testing \
    -workspace Foulee.xcworkspace -scheme Foulee \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$dd" ARCHS="$arch" ONLY_ACTIVE_ARCH=NO

pass watchos xcodebuild build-for-testing \
    -workspace Foulee.xcworkspace -scheme FouleeWatch \
    -destination 'generic/platform=watchOS Simulator' \
    -derivedDataPath "$dd" ARCHS="$arch" ONLY_ACTIVE_ARCH=NO

if [ ${#failed[@]} -gt 0 ]; then
    echo "✖ failed: ${failed[*]} (logs in $out/)"
    exit 1
fi
echo "✔ all passes"
