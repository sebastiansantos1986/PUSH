# PUSH Client 1.16.7 / Admin 1.16.11 — pilot prerelease

Developer: Sebastian Santos · November 22, 2026

Admin 1.16.11 fixes the exported Self Service prerequisite version gate. Earlier exports displayed a requirement for Client 1.16.7 but retained a numeric floor of 1.16.3. A healthy 1.16.6 installation could therefore skip the already-uploaded 1.16.7 prerequisite package and run the old client.

The script now derives its numeric comparison, messages and repair decisions from one required-client version. Client 1.16.7 itself is unchanged. Scripts already stored in Jamf require updating; installing Admin alone does not modify them. Rebuild/review/publish the existing workflow to update its script while retaining its scope and prerequisite event.

The current Admin/export suite passes 707 checks. New tests execute the generated script using temporary fake CLI/Jamf tools: 1.16.3, 1.16.5 and 1.16.6 request repair; a no-op prerequisite that leaves an old binary cannot request an upgrade; current/newer healthy versions skip reinstallation. No real Jamf policy, user credential, macOS installer or restart is invoked by these tests.

The previous Client 1.16.7 nested-resource correction remains unchanged. Its complete upgrade/restart pilot test is still pending. Packages remain local/pilot artifacts with ad-hoc code signatures and unsigned installers.

See [the consolidated earlier release notes](RELEASE-NOTES-1.16.7-ADMIN-1.16.10.md) for the other workflow, publishing and installer changes.
