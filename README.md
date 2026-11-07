# PUSH — Proactive Update Scheduling Helper

**Developer: Sebastian Santos** · [MIT license](LICENSE)

PUSH helps Mac administrators discover macOS updates, remind users, manage approved app updates, and guide Jamf device registration. The native **PUSH Admin** companion provides configuration editing, popup previews, and an installed-readiness dashboard.

**Current test release: PUSH engine 1.6.0 · PUSH Admin 0.5.0 · macOS 14 or later · Apple Silicon and Intel.**

[Download the Readiness test release](https://github.com/sebastiansantos1986/PUSH/releases/tag/v1.6.0-readiness) · [Installation guide](docs/READINESS-GUIDE.txt) · [Verification results](docs/READINESS-VERIFICATION.json)

## Install and review

1. Quit PUSH Admin and allow any active PUSH command to finish.
2. Download and install **PUSH-Readiness-0.5.0.pkg** from the release above. It contains both the engine and companion.
3. Open **Applications → PUSH Admin → Readiness**.
4. Click **Refresh** to review the installed policy, saved results, and background service status.

This is an **unsigned local test installer**, containing ad-hoc signed universal binaries. It is not a notarized fleet deployment release. Existing settings, state and Keychain credentials are preserved. The previous engine, state and monitor definitions are backed up under `/Library/Management/PUSH-backups`.

**Both monitors remain paused after installation.** Installing does not launch either app, download macOS, update applications, register the Mac, or restart it. Review the installed live policy before explicitly enabling monitoring: a preserved policy may allow automatic installation after a deadline or updates of closed apps.

The repository's [config.yaml](config.yaml) is a minimal safe-start example. Fresh installations disable automation and start in dry-run mode. Existing installations retain their own configuration.

## What's included

| Component | Purpose |
| --- | --- |
| `push-cli` | Discovery, update policy, scheduling, installation safeguards, status and reporting |
| `push-ui` | Native user-facing update, restart, app-update and registration prompts |
| `PUSH-Admin` | Native configuration editor, catalog, Popup Studio and readiness dashboard |
| `Packaging` | Local-test engine installer and preservation scripts |
| `Tests` and `PUSH-Admin/Tests` | Offline regression and fixture tests |

### Readiness & Next Action

The new default Admin page shows installed settings separately from the unsaved configuration draft:

- **Monitoring:** loaded, running, paused, missing, unknown, unfinished or overdue. A schedule file alone does not prove the service is loaded.
- **macOS:** saved target, effective deadline, installation/reboot state and earliest toast eligibility.
- **Apps:** approved apps, saved pending updates, provider-file presence and saved blockers.
- **Entra:** current-user local registration evidence and the next relevant setup action. Cloud compliance is explicitly **not assessed**.

Readiness **Refresh is passive**: it reads local files and the two known launchd services. It does not run update checks, access Keychain, display prompts or change monitoring. Copy check command only copies text for an administrator to run separately. Manual observations never substitute for scheduled heartbeat history. New scheduled observations require the updated engine and explicit monitor activation.

Saved results describe the last check, not a fresh vendor, enrollment or cloud assessment. Eligibility is the earliest permitted time; working hours, meetings, user availability and other active actions can delay delivery.

### Configuration and discovery

- Configure once with PUSH Admin; review and apply changes explicitly.
- Optional release tracking discovers eligible macOS releases. An explicit YAML `update.deadline` takes precedence over a generated deadline.
- Hourly toast reminders and a separate full-prompt schedule follow the configured policy and eligibility rules.
- Supported missing YAML fields can be added with `config set`, with a previous-configuration backup.
- End-user password prompts and password-capture fallback are disabled. Unattended authorization requires managed credentials or supported MDM authorization; missing authorization waits for IT.

PUSH Admin retains its existing Mist catalog listing at startup. It lists stable compatible installers without downloading them. This catalog operation is separate from the passive Readiness Refresh.

### Approved third-party app updates

App management is opt-in and currently supports **Google Chrome, Firefox release and Visual Studio Code**. Administrators approve app IDs explicitly. Open apps are left running, and actual updates require an administrator-managed Installomator provider with engine-side trust checks. Checks, notifications and installation requests are separate actions.

See [app-update behavior](PUSH-Admin/APP-UPDATES.txt).

### Entra registration reminders

The opt-in registration module guides users through a configured Jamf Self Service policy. It checks current-user local Jamf registration evidence, uses four reminder stages and daily prompt limits, and records Later, close and timeout separately. Register Now opens the configured policy; it never counts as successful registration by itself.

Production reminders are inactive on unenrolled Macs. Missing prerequisites or unverifiable evidence produce an IT setup result instead of repeated registration prompts. A separate five-minute monitor can be enabled explicitly. Local evidence does not establish cloud compliance.

See [registration behavior](PUSH-Admin/ENTRA-REGISTRATION.txt).

### Popup Studio

Preview popup states, custom branding and icons, appearance, and button actions in the companion. Previews simulate actions; they do not install updates or perform registration.

## Build from source

Use a Mac with Xcode and its command-line tools installed. The current engine project is the **top-level `PUSH.xcodeproj`**. Older nested project copies are retained only for repository history.

From the repository root:

```bash
mkdir -p artifacts
xcodebuild -project PUSH.xcodeproj -scheme PUSH-All \
  -configuration Release -derivedDataPath build/Engine \
  CODE_SIGNING_ALLOWED=NO 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build

bash Packaging/build-local-package.sh \
  "$PWD/build/Engine/Build/Products/Release" \
  "$PWD/artifacts/PUSH-1.6.0-Local-Test.pkg"

bash PUSH-Admin/Packaging/build.sh "$PWD/artifacts"

bash PUSH-Admin/Packaging/build-branding-update.sh \
  "$PWD/artifacts/PUSH-1.6.0-Local-Test.pkg" \
  "$PWD/artifacts/PUSH-Admin-0.5.0.pkg" \
  "$PWD/artifacts/PUSH-Readiness-0.5.0.pkg"
```

These scripts build packages; they do not install them or launch PUSH. The source build requires no Developer ID signing identity for these local-test artifacts. Distribution signing and notarization are separate deployment work.

## Offline verification

```bash
bash Tests/run-safe-tests.sh
bash PUSH-Admin/Tests/run-safe-tests.sh
```

For this release, **242 engine checks and 182 companion checks passed**. The Release engine and universal companion builds completed; package contents, versions, architecture slices, ad-hoc signatures, preservation scripts and attribution were inspected. No package was installed and no app, live update, registration, upgrade or restart was run as part of that verification. Visual behavior remains for the administrator's live testing.

Checksums for the published assets are in the release's `PUSH-Readiness-0.5.0.sha256` and [this copy](docs/PUSH-Readiness-0.5.0.sha256). Older `SHA256SUMS.txt`, repair notes and test-result files describe their historical snapshots.

## Existing integrations and history

The `PUSH-deployment-fixed`, `jamf-setup`, and `jamf-ea-fix` folders are preserved from the earlier repository. Their deployment flow has not been validated against this test release. Use the current packaging scripts above for the Readiness local-test build.

The earlier repository guide is preserved in [docs/legacy/README-1.1.7.md](docs/legacy/README-1.1.7.md), and the repaired engine's historical guide in [docs/legacy/README-repaired-history.md](docs/legacy/README-repaired-history.md). Historical examples may describe older behavior; this page and the current release guide govern the Readiness build.

## Attribution

Copyright © 2026 Sebastian Santos. Distributed under the [MIT license](LICENSE).

Attribution ID: `PUSH-DEV-SEBASTIAN-SANTOS`.
