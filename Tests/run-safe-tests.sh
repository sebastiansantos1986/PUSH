#!/bin/bash
# Developer: Sebastian Santos
# Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/push-safe-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
sources=()
for source in push-cli/*.swift; do
    [[ "$source" == push-cli/main.swift ]] || sources+=("$source")
done
xcrun swiftc -swift-version 5 -module-cache-path "$test_dir/modules" \
    Shared/SecureSupport.swift "${sources[@]}" Tests/main.swift -o "$test_dir/tests"
"$test_dir/tests"
