# Optional Major Upgrade Debug Preview

Developer: Sebastian Santos · Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

Current local test build: engine 1.10.0 / Admin 1.2.0 / JamfCheckIn 1.1.0 unchanged.

PUSH Admin → Major Upgrade (Debug) previews one optional-offer window through simulated download, preparation and restart-ready stages. The client also includes an isolated, never-autostarted demo app. Run `push-cli major-offer --debug` as the logged-in user without sudo after installing the matching client. Every button is simulated; no live installer or restart route is enabled. See PUSH-Major-Upgrade-Debug-Guide.txt for test steps and boundaries. Existing required-update workflows are retained separately.

## Previous release documentation

# PUSH Admin 1.1.0

Developer: Sebastian Santos · Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

The complete client builder creates one configured installer with PUSH 1.9.1, JamfCheckIn 1.1.0, reviewed YAML and staged images. Employee Macs do not receive PUSH Admin. Choose paused installation or explicitly reviewed live monitoring (first checks deferred five minutes). Profiles remain separate for MDM delivery. Setup suggestions appear in Guided Setup and Deployment and change only the draft when applied. See PUSH-Admin-1.1.0-Guide.txt for prerequisites, signing, profile scope and pilot testing.

Building runs packaging tools only; no installer, application, profile or service is executed/activated. Current local builds are ad-hoc signed, and generated installers are unsigned. Production signing/notarization is a separate deployment requirement.

# PUSH Client / Admin separation

Developer: Sebastian Santos · Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

Current delivery: PUSH Client 1.9.1 (engine + JamfCheckIn 1.1.0) and PUSH Admin 1.0.0 (IT only). Client Macs do not receive the admin console or a second menu app. PUSH Admin → Deployment exports a client/policy/assets/profile bundle. No component is launched or activated by the local-test installer. Production Developer ID signing and notarization remain required before fleet rollout.

The original Desktop projects are unchanged. Existing functionality is retained; PUSH requests use the guarded user channel. Jamf check-in/inventory administration is separate. See the delivered Client-Admin guide and exported READ-ME-FIRST for activation and profile scope.

## Previous project documentation

