# Verification — PUSH 1.16.7 / Admin 1.16.11

Developer: Sebastian Santos · November 22, 2026

| Check | Result |
| --- | --- |
| Client safe regression suite | 562 passed |
| Admin/export suite with the built client | 707 passed |
| Sebastian Santos attribution | 161 Swift files, no failures |
| Client/UI and Admin Release builds | arm64 and x86_64 |
| Code signatures and embedded client bytes | Verified locally |
| Package expansion and version metadata | Verified locally |
| Shell syntax and macOS Bash optional flags | Passed |
| Source whitespace checks | Passed |

The source copied into this repository was tested independently of the original Desktop checkouts. Tests include target-version discovery from Mist’s managed cache, fallback to Applications, nested Apple custom-resource decisions, rejection of non-Apple/unsigned/modified executable results, strict startosinstall behavior, credential save orchestration with in-memory backends, and fake-server publishing/scope/read-back failures.

The client suite compares real Security.framework validation with system codesign on a local Apple tool. The installer resource-format cases use injected signature results and harmless Mach-O fixtures. They do not establish that a real installer completes an upgrade.

**The complete upgrade/preparation/restart journey with the latest nested-resource fix remains pending on the test Mac.** No real macOS download, installer execution or restart was performed by the agent. There is no production/fleet certification claim.

Packages use ad-hoc code signatures and unsigned installer packages. Production signing/notarization and applicable MDM approvals remain separate. SHA-256 digests are in the repository root and the accompanying JSON file.

Version gate correction: tests execute old-patch repair and no-op repair failures without real Jamf/installer commands. Existing live Jamf scripts require updating separately.
