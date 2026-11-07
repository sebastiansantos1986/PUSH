# PUSH Admin 1.1.0

Developer: Sebastian Santos · Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

The complete client builder creates one configured installer with PUSH 1.9.1, JamfCheckIn 1.1.0, reviewed YAML and staged images. Employee Macs do not receive PUSH Admin. Choose paused installation or explicitly reviewed live monitoring (first checks deferred five minutes). Profiles remain separate for MDM delivery. Setup suggestions appear in Guided Setup and Deployment and change only the draft when applied. See PUSH-Admin-1.1.0-Guide.txt for prerequisites, signing, profile scope and pilot testing.

Building runs packaging tools only; no installer, application, profile or service is executed/activated. Current local builds are ad-hoc signed, and generated installers are unsigned. Production signing/notarization is a separate deployment requirement.

# PUSH Client / Admin separation

Developer: Sebastian Santos · Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

Current delivery: PUSH Client 1.9.1 (engine + JamfCheckIn 1.1.0) and PUSH Admin 1.0.0 (IT only). Client Macs do not receive the admin console or a second menu app. PUSH Admin → Deployment exports a client/policy/assets/profile bundle. No component is launched or activated by the local-test installer. Production Developer ID signing and notarization remain required before fleet rollout.

The original Desktop projects are unchanged. Existing functionality is retained; PUSH requests use the guarded user channel. Jamf check-in/inventory administration is separate. See the delivered Client-Admin guide and exported READ-ME-FIRST for activation and profile scope.

## Previous project documentation

