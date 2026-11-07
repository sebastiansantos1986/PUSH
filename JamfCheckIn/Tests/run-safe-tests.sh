#!/bin/bash
# Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
set -euo pipefail
cd "$(dirname "$0")/.."
stage="$(mktemp -d "${TMPDIR:-/tmp}/jamf-safe-tests.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$stage/modules" -framework SwiftUI -framework AppKit JamfCheckIn/PUSHConfig.swift JamfCheckIn/RecoveryPolicy.swift JamfCheckIn/UserRequestChannel.swift JamfCheckIn/PUSHStatusModel.swift Tests/main.swift -o "$stage/tests"
"$stage/tests"
