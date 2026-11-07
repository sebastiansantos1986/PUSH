Toast response and design update — November 5, 2026
Developer: Sebastian Santos
Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

PUSH engine 1.2.3 and PUSH Admin 0.1.4
- Manual popup toast now waits for the actual UI process result rather than
  hard-coding success at launch. Later reports User chose Later; close reports
  User dismissed. Launch failures/timeouts are not labeled as user choices.
- The toast no longer writes a shared /tmp/push-toast-action signal, and
  scheduled checks no longer poll it. A manual popup test cannot request a
  later upgrade through that file. Manual popup never runs InstallWorkflow.
- The scheduled toast controller waits for its own UI result and requests an
  install only on exit 0. Later/close/timeout never consume a toast deferral.
- Scheduled toast handling is now synchronous for that daemon invocation,
  bounded by the existing 15-minute UI wait, rather than fire-and-forget.
- Compact opaque card, short default message, clear version heading, separate
  deadline badge, larger full-width actions, and stronger secondary contrast.
  Light custom accent colors use a dark primary-button label for readability.
- Removed the fake always-present 60-second timer. A countdown only appears
  when toast.autoDismissSeconds is greater than zero, pauses on hover, and
  returns a distinct toast-timeout code (5). Zero/unset stays open until action
  or the controller's maximum wait. The preview timeout is simulated once.
- Custom toast messages and button labels remain configurable. Both apps use
  the same new ToastView layout; custom images and symbols remain supported.

Verification: all Release engine targets and the universal companion compile.
17 isolated response-mapping assertions passed without a UI or app launch.
The combined installer was expanded; versions, signatures, architecture slices,
engine scripts, app-only companion payload, and preservation of config/state
were inspected. No installer, PUSH app, popup, daemon, upgrade, or restart was
launched. Actual click capture, auto-dismiss timing, and visual appearance need
the user's live verification.

Historical documentation follows:

PUSH Admin 0.1.3 — direct popup-preview images
Developer: Sebastian Santos
Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

Quit PUSH Admin, install PUSH-Admin-0.1.3.pkg, and reopen the companion.
In Popup Studio, click the icon INSIDE the displayed popup, or use Choose preview
image…. Select a PNG, JPEG, or TIFF. The chosen image is passed directly into
that popup's icon view in memory. No Save, Export, Apply, or engine update is
needed merely to see it in the preview. Existing draft images are restored.

The Customize popup icon section still offers Default, Custom image, and System
symbol. Export/Apply are separate deployment actions. Actual deployed popups
still need the engine's branding support from 1.2.2 or later.

This update also disables JSON-style slash escaping when emitting YAML string
values. PUSH's minimal YAML reader otherwise treats escaped slashes literally,
which prevents image paths and URLs from resolving. An isolated Foundation-only
check executed against the real PUSH config parser passed both logo-path and
URL round trips. No companion app, UI, Mist query, installer, or admin action
was launched. Live appearance remains for the user to verify.

Earlier branding documentation follows:

PUSH Admin 0.1.2 — custom popup icons
Developer: Sebastian Santos
Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

RECOMMENDED UPDATE
Quit PUSH Admin and install PUSH-Branding-Update-0.1.2.pkg. This updates the
companion to 0.1.2 and engine to 1.2.2 in one installer. The engine update fixes
logo precedence: custom image, then selected system symbol, then bundled icon.
Its existing backup and paused-schedule behavior is retained. No draft, selected
logo, or YAML is applied automatically. The standalone companion installer is
also provided, but an older engine will not honor custom branding consistently.

USING THE ICON PICKER
- Popup Studio > Customize popup icon, or Configuration > Organization & appearance.
- Choose Default PUSH icon, Custom image, or System symbol.
- Custom image supports PNG, JPEG, and TIFF. A square transparent logo is best.
- The selected file is normalized to a bounded PNG (maximum dimension 512 pixels)
  without modifying the original. Aspect ratio and transparency are preserved.
- Image input is limited to 20 MB, 16,384 pixels per side, and a 1 MB normalized
  PNG. Invalid or oversized input is rejected.
- The Studio refreshes immediately for changes to the icon or draft settings.
- Your selected normalized image is saved inside your private draft data, with
  a private preview file under your account's PUSH Admin Application Support folder.
- Default clears image/symbol settings. System symbol lets you select a built-in
  icon without deploying an external image file.

DEPLOYING A CUSTOM IMAGE
Export YAML also saves popup-logo.png beside it (with confirmation before
replacing a different image). The generated YAML refers to:
  /Library/Management/PUSH/assets/popup-logo.png
Distribute the PNG to that path along with the YAML on managed Macs. An imported
external logo path is only a reference until you choose an image in the picker.

Apply Configuration explicitly stages and installs the normalized image at that
fixed path, backs up an existing image and YAML, and writes root-owned readable
files. It never writes a logo to an arbitrary path as administrator. Advanced
manual edits to logoPath clear the picker attachment and are treated as existing,
externally managed image references. Apply requests normal IT-admin authorization;
selecting an icon and previewing it do not require admin or user-login passwords.
Import installed config first if you want to retain the current live policy while
changing only branding, then choose the icon and review before Apply.

VERIFICATION
Both updated apps compiled for arm64/x86_64. The combined installer was expanded;
its two versions, payload, exact engine scripts, app signatures, architecture
slices, and default icon resource were inspected. Offline regression tests compile,
including image decoding, invalid input, draft migration, and engine field mapping.
No app, image test executable, installer, admin action, Mist query, upgrade, or
restart was executed. Live image selection/appearance still needs your review.

GENERAL COMPANION DOCUMENTATION

PUSH Admin 0.1.2 — first native companion build
Developer: Sebastian Santos
Copyright (c) 2026 Sebastian Santos
Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

INSTALL AND OPEN
1. Install PUSH-Admin-0.1.2.pkg.
2. Open Applications > PUSH Admin yourself.
3. The app checks the macOS catalog through your installed mist-cli.
   It looks in /usr/local/bin/mist and /opt/homebrew/bin/mist.
   If Mist is missing, the app links to its official releases. It does not
   install a dependency, download an OS, or request admin access at startup.

The package installs only /Applications/PUSH Admin.app. It has no installer
scripts, does not replace PUSH 1.2.1, and does not change its config or schedule.
Both the app and package are local test artifacts, not a signed/notarized fleet
release. The app has an ad-hoc signature; the package is unsigned. If blocked,
use macOS's normal Open Anyway control after verifying the package's origin.
Do not disable Gatekeeper.

FIRST WALKTHROUGH
- Overview: review the installed engine version, catalog result, and setup path.
- macOS Releases: inspect stable compatible releases; Use in draft fills the
  version, name, and major/minor selection. This does not set the live target.
- Configuration: use the guided sections to set branding, update policy,
  detection, hours, restart reminders, preflight checks, messages, toast settings,
  Jamf/LAPS account identifiers, and testing/logging policy. A calendar picker
  formats explicit deadlines. Drafts are saved automatically for your account.
- Popup Studio: choose a popup and click its buttons. These are PUSH's actual
  SwiftUI view layouts with simulated actions. No CLI command or daemon signal
  is sent. No installer or reboot can be started from a preview. Password entry
  is not offered. The preview uses your current draft's appearance and messages.
- Deployment: export config.yaml for your management workflow, or explicitly
  apply to this Mac after review. Applying asks the administrator for macOS
  authorization, backs up the live YAML, and replaces it atomically. Future
  scheduled checks may react to the new policy. The companion does not launch
  an update check when applying settings.

IMPORTING EXISTING SETTINGS
Use Import YAML or Import installed config. An imported file is a draft; its
original is not modified. Known plaintext password/API-secret fields and their
continuation lines are omitted from the draft and from exports. The app does
not read or change the Keychain. Provision secrets through your IT process.
Unknown fields and unrelated comments are retained. Missing known settings use
conservative displayed defaults and are emitted explicitly, so review the full
policy before applying. PUSH's top-level laps: block is used in generated YAML.

The editor targets PUSH's section-and-scalar YAML. This is not a general YAML
editor. Anchors, tags, tabs, flow-style root documents, and duplicate top-level
sections are rejected. Known multiline messages can be imported and edited.
PUSH 1.2.1 has a minimal YAML reader; escaped quote/backslash edge cases and
advanced YAML should be checked in a popup before production deployment.

CATALOG BEHAVIOR
At process launch and when Refresh is selected, the only Mist command is:
  mist list installer --compatible --export <private-temporary-path>/catalog.json
It uses the documented interface and JSON fields from the upstream project:
https://github.com/ninxsoft/mist-cli
https://github.com/ninxsoft/mist-cli/blob/main/Mist/Model/Installer.swift

Versions are sorted numerically, duplicate builds are consolidated, and betas
are excluded. Results are cached with their check time. Offline/missing-Mist/
timeout failures are displayed; cached data is labeled. Compatibility applies
to the Mac running this app, not automatically every Mac in a mixed fleet.
The catalog result does not prove management enrollment, authorization, that
an update is staged, or that a selected version can be installed unattended.
An existing legacy Mist release may need updating for future macOS catalogs.

LOCAL ADMIN ACTIONS
Apply Configuration requests admin authorization only after a review dialog.
Backups are in /Library/Management/PUSH/config-backups (root access required).
Enable hourly checks requires an installed PUSH 1.2.1+ engine and checks the
INSTALLED configuration for debug.dryRun: true before activating its daemon.
The first scheduled check runs immediately in dry-run mode. Pause Schedule
stops/removes the daemon. Production automation activation remains a separate
IT deployment step in this first version. No user login passwords are collected.

WHAT WAS VERIFIED
- Universal arm64/x86_64 macOS 14+ compilation.
- Package payload, identity, versions, install path, lack of installer scripts,
  and ad-hoc app signature.
- Offline regression suite compiles against the actual PUSH 1.2.1 config parser.
- Static review of the isolated preview path for writes, process execution,
  daemon signals, Keychain access, and actual exit/reboot paths.

The app, Mist query, regression test executable, administrative actions, and
installer were NOT run in this session, per your preference to run them yourself.
Live layout, Mist/network behavior, and admin apply/scheduling need your review.
This is a first local test build, not production qualification.

SOURCE AND BUILD
Open Package.swift in Xcode to inspect the SwiftUI source. Packaging/build.sh
builds a universal .app and a separate component installer; pass an absolute
output directory. No external Swift packages are required. This environment
needed PUSH_MACRO_SANDBOX_WORKAROUND=1 for Apple's macro compiler to run inside
its existing outer sandbox; that compiler flag is optional and is not an app
runtime permission or entitlement.

RUN THE OFFLINE CHECKS YOURSELF
  bash Tests/run-safe-tests.sh
The suite uses fixtures only; it does not start the app, query Mist, access
Keychain, apply config, enable a daemon, install macOS, or restart anything.
Tests/EngineConfigReference.swift is an unchanged copy of the 1.2.1 engine's
configuration parser, retained so the source archive is self-contained.
