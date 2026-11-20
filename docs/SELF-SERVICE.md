# Jamf Self Service workflows

Developer: Sebastian Santos · PUSH Client 1.16.7 / Admin 1.16.10

## User experience

A user selects the reviewed offer in Self Service. The offer first verifies the CLI, popup UI and required Mist prerequisite. If they are missing, older or damaged, it invokes the workflow’s repeatable repair event and checks them again. Healthy newer clients are kept. Existing configuration, runtime state, images, monitoring and Keychain storage are preserved by the dedicated repair package.

When needed and enabled, PUSH requests the logged-in user’s Mac password and saves it in that user’s login Keychain. Valid saved authorization is reused. Passwords are not written into YAML, scripts, packages, logs or Jamf API payloads. Installer handoff uses private stdin; cancellation or validation failure prevents submission.

PUSH checks hardware eligibility, available disk space, power, authorization and installer trust. It shows download progress, preparation progress and restart information. A staged installation is not reported as a completed upgrade; completion is verified after reboot.

## Publish from Admin

1. Configure generation-specific offers, presentation and authorization in **Jamf Self Service**.
2. Open **Publish to Jamf** and choose optional offers, a required-update campaign, or both.
3. Connect your Jamf server using a client-credentials API connection. The optional saved secret stays in the administrator’s login Keychain. Tokens stay in memory.
4. Select an existing approved pilot group or create a new empty static pilot group. PUSH never chooses All Computers automatically. Existing group membership, including future membership, determines scope.
5. Build and review the exact packages, scripts, groups, events and policy behavior.
6. Publish. Uploads, hashes, policies, scope, frequency and enabled state are read back for verification. Policies remain disabled until the separate activation step.
7. Review the success summary’s human-readable names and Jamf IDs. Enable the reviewed pilot explicitly.

The Admin tool includes the matching client and a checksum-verified Mist CLI 2.3 package. Advanced package overrides remain available. An optional offer’s client repair is **Ongoing**, custom-event only, without a check-in trigger. Existing project-owned repair events are reused across package updates. New workflows use a stable project-specific event.

The offer policy is Self Service only and ongoing. Its packages install isolated offer profiles and its After script invokes PUSH. It does not replace a required-update campaign’s YAML, deadline or deferrals. Combined deployments keep campaign installation and optional repair distinct.

## Jamf API privileges

The bundled publisher targets Jamf Pro 11.5+ with a cloud distribution point. Grant the role needed for the selected operation:

- Create, Read and Update Policies
- Create, Read and Update Scripts
- Create, Read and Update Packages
- Create and Read Categories
- Read Smart Computer Groups
- Read Static Computer Groups
- Read Cloud Distribution Point
- Create Static Computer Groups only when creating a new empty pilot group
- Update Static Computer Groups or Update Smart Computer Groups only when renaming that group

API roles and clients must be enabled and associated correctly. Reconnect after changing privileges. A 401 alone does not distinguish expired authorization from insufficient access.

## Installer selection and validation

Same-generation point updates use eligible native Apple Software Update labels. Major upgrades use a full application installer and `startosinstall`. The target is resolved within the reviewed offer’s macOS generation, subject to endpoint eligibility.

Mist is called with `download installer <version> application --output-directory /Library/Management/PUSH/downloads --compatible --force --no-ansi`. PUSH searches its managed cache and `/Applications` both before and after download. It verifies product metadata rather than guessing an OS version from a filename or app bundle version. A manually downloaded installer in `/Users/Shared/Mist` is not automatically trusted or imported by this release.

Installers staged from `/Applications` are moved into the protected managed cache before execution. Extracted `_unknown` uid 99 ownership may be repaired only on the exact SharedSupport directory and disk image; end-user-owned payloads, escaping links and unexpected types remain rejected. Root-owned group/other writable cache entries are restricted without changing payload bytes or executable bits.

The validator requires Apple-anchored executable signatures across architectures. The exact Apple custom omit-rule error may use code-only validation for the outer InstallAssistant and its nested components; other signature errors remain failures. The actual `startosinstall` executable retains strict validation. Nested Mach-O files are checked individually, and the SharedSupport disk image must pass integrity verification. Rejections log the exact executable and status. No Gatekeeper setting is disabled and Apple executables are not re-signed.

## Failure handling

A partial publish retains a receipt and leaves affected policies requested disabled. Inspect the actual server state and receipt before using **Review / resume prepared kit**. An interrupted write is not automatically replayed. An HTTP 500 upload response can leave an ambiguous package record; do not create duplicate packages to guess around it.

If prerequisite verification fails, inspect the installed CLI version, UI identity, Mist version, root-protected paths and installer receipt. A success message for a package install does not prove its payload is the required version. Remove obsolete downgrade policies from the pilot’s deployment plan; do not delete unrelated policies or reset history indiscriminately.

The 1.16.7 nested-resource change is automated-test verified. Its complete download/preparation/restart journey still needs a real pilot test. See [verification](VERIFICATION-1.16.7.md).
