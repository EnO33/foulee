#!/bin/bash
# Sourced by the scripts whose result depends on the screen and the iOS
# version (the accessibility audit, the launch time): the same simulator on a
# Mac and in CI — the newest iOS runtime and the newest iPhone it supports.
#
#   source tools/newest_iphone_simulator.sh "Foulee Audit"
#
# Sets SIMULATOR_UDID, created under that name if missing and booted, and
# SIMULATOR_NAME, « <iPhone>, iOS <version> », which the scripts record beside
# their baseline.

RUNTIME=$(xcrun simctl list runtimes available -j \
  | jq -c '[.runtimes[] | select(.platform == "iOS")] | sort_by(.version) | last')
RUNTIME_ID=$(echo "$RUNTIME" | jq -r .identifier)
DEVICE_TYPE=$(echo "$RUNTIME" | jq -c '[.supportedDeviceTypes[] | select(.productFamily == "iPhone")] | last')
DEVICE_TYPE_ID=$(echo "$DEVICE_TYPE" | jq -r .identifier)
SIMULATOR_NAME="$(echo "$DEVICE_TYPE" | jq -r .name), iOS $(echo "$RUNTIME" | jq -r .version)"
SIMULATOR_UDID=$(xcrun simctl list devices available -j \
  | jq -r --arg runtime "$RUNTIME_ID" --arg type "$DEVICE_TYPE_ID" --arg name "$1" \
    '.devices[$runtime] // [] | map(select(.name == $name and .deviceTypeIdentifier == $type)) | first | .udid // empty')
[ -n "$SIMULATOR_UDID" ] || SIMULATOR_UDID=$(xcrun simctl create "$1" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
echo "==> $1 on $SIMULATOR_NAME ($SIMULATOR_UDID)"
# Booted before the run, for the same reason as CI's iOS job (issue #404).
xcrun simctl bootstatus "$SIMULATOR_UDID" -b >/dev/null
