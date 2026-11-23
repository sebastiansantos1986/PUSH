# PUSH roadmap

Developer: Sebastian Santos · PUSH Client 1.16.7 / Admin 1.16.11

## Implemented in the pilot source

- Guided and saved workflows with setup suggestions and safe simulation.
- Configurable messages, Markdown, icons, banners, greetings and wallpaper assets.
- Required-update discovery, explicit YAML deadlines, hourly toasts and daily reminders.
- Optional live Jamf Self Service upgrades, separate from campaigns.
- Bundled client/Mist prerequisites and repeatable on-demand repair.
- Reviewed Jamf publishing, exact read-back verification, human-readable names/IDs and separate pilot activation.
- Login Keychain reuse and password prompting when needed, with private installer handoff.
- Same-generation native update routing and full-installer major upgrades.
- Installer version/path/signature checks, Apple installer resource-format handling and post-reboot completion verification.
- Approved app-update providers, Entra reminders, restart workflows, compliance wallpaper and hardware inventory.

## Before wider production rollout

- Complete the real pilot authorization/download/preparation/restart test with the 1.16.7 nested-resource correction.
- Finish production Developer ID signing/notarization and validate MDM approval identities.
- Test all supported hardware/generation combinations and upgrade failure recovery.
- Verify reminders, state preservation and coexistence with other management policies on enrolled pilot Macs.
- Audit and retire obsolete downgrade policies and legacy packages deliberately.

JamfCheckIn source is retained, but it is excluded from current deployment while its separate fixes are reviewed. Automated tests and publishing success are not fleet-readiness certification.
