#!/bin/bash
# Developer: Sebastian Santos
# Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
set -euo pipefail
cd "$(dirname "$0")/.."
engine_config="${1:-Tests/EngineConfigReference.swift}"
[[ -f "$engine_config" ]] || { echo 'Pass the path to the repaired PUSH push-cli/CLIConfig.swift as the first argument.' >&2; exit 2; }
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/push-admin-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
sources=()
for source in Sources/*.swift; do
    [[ "$source" == Sources/AdminApp.swift || "$source" == Sources/SetupAdvisorCard.swift || "$source" == Sources/DeploymentExportPage.swift || "$source" == Sources/SmartSetup.swift || "$source" == Sources/AppsPage.swift || "$source" == Sources/RecoverySettingsPage.swift || "$source" == Sources/WallpaperPage.swift || "$source" == Sources/NotificationHistoryPage.swift || "$source" == Sources/SetupWizardPage.swift || "$source" == Sources/ReadinessPage.swift || "$source" == Sources/EntraPage.swift ]] || sources+=("$source")
done
compiler_flags=()
if [[ "${PUSH_MACRO_SANDBOX_WORKAROUND:-0}" == 1 ]]; then compiler_flags=(-Xfrontend -disable-sandbox); fi
xcrun swiftc -swift-version 5 -module-cache-path "$test_dir/modules" "${compiler_flags[@]}" \
    -framework AppKit -framework SwiftUI -framework IOKit \
    "${sources[@]}" "$engine_config" Tests/main.swift -o "$test_dir/tests"
"$test_dir/tests" "$PWD/Tests/Fixtures/red-pixel.png"
