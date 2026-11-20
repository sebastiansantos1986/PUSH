# PUSH 1.16.7 / PUSH Admin 1.16.10 — pilot prerelease

Developer: Sebastian Santos · November 20, 2026

This consolidates changes since the repository’s 1.11.0 / Admin 1.3.0 snapshot. It is not a completed production upgrade certification.

## Admin and deployment

- Guided workflow creation, saved drafts, suggested settings and tailored user messages.
- Custom popup text, Markdown, icons, banners, greetings, sizing and simulation.
- Optional generation-specific macOS offers and separate required-update campaigns.
- Jamf API publishing with reviewed packages, read-back verification, pilot-only activation, human-readable policy names and a names/IDs success summary.
- Matching client and verified Mist CLI package included automatically; no manual prerequisite package selection is needed for the default workflow.
- Repeatable on-demand client repair, stable existing repair events, and preservation of newer working clients. No routine uninstall or policy-history reset.
- Current client packages exclude Admin and JamfCheckIn. The legacy JamfCheckIn source is retained separately.

## Client and authorization

- Same-generation point updates use eligible native Software Update labels; major upgrades use full installers.
- User-session popup launch acknowledgements and explicit button results.
- Existing login Keychain authorization reused when valid, with an opt-in password prompt when needed and private stdin handoff.
- Existing credential updates preserve access controls instead of repeatedly replacing them.
- Deadline parsing, independent reminders, readiness/status reporting, state transitions and reboot verification improvements.
- Compliance wallpaper, approved app-update providers, local Entra reminders and hardware readiness remain available through reviewed workflows.

## Installer corrections

- Mist writes into the managed download cache. Both pre-download and post-download discovery search that cache and Applications using OS product metadata.
- A root-private cache protects the installer. The two extracted SharedSupport uid 99 objects have narrowly scoped ownership repair; normal user-owned content is not adopted.
- Apple custom omit rules are handled for the outer InstallAssistant and nested Apple components only after the exact resource-format error. Apple signing-anchor/code checks and all architectures remain required; startosinstall remains strict.
- Unsigned code, non-Apple signers, modified executable hashes, other signature failures, unsafe paths and failed payload integrity checks remain rejected. Nested failures identify the file and status.

## Verification and limits

The client regression suite passes 562 checks, including nested omit-rule success/failure cases and managed-cache discovery. Admin/export verification is recorded separately in the verification document. Universal local packages are ad-hoc signed/unsigned installer artifacts.

The final nested-resource fix still needs the real test Mac’s upgrade/restart test. No macOS upgrade, installer download, installer execution or restart was run by the build/publishing agent. A policy being enabled is not a completed upgrade.
