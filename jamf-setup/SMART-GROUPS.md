# PUSH - Jamf Smart Groups

`setup-jamf.sh` creates the PUSH Extension Attributes and Smart Computer Groups
below. The script is dry-run-only unless `--apply` is supplied, skips objects
that already exist, and asks before every creation unless `--yes` is used.

## Extension Attributes

| Extension Attribute | Type | Purpose |
|---|---|---|
| PUSH — OS Update Compliance EA | String | Compliant, update required, deadline, install, or missing state |
| PUSH — Days Until Deadline EA | Integer | Days to the configured deadline; `-1` when no deadline is configured |
| PUSH — Deferral Count EA | Integer | Update deferrals already used |
| PUSH — Deferral Reasons EA | String | User-selected reasons, or `None` |
| PUSH — Deferrals Remaining EA | Integer | Remaining deferrals based on the Mac's active configuration |
| PUSH — Health EA | String | Installed version, LaunchDaemon state, and last auto-check activity |
| PUSH — Reboot Status EA | String | Healthy, warning, or force state from the uptime policy |

No EA reports a password, API secret, recovery key, or other credential.

## Smart Groups

| Smart Group | Key criteria | Operational use |
|---|---|---|
| PUSH: Compliant | Compliance is `Compliant` | Fleet compliance dashboard |
| PUSH: Non-Compliant - Active | Compliance contains `Non-Compliant` | Macs working through the update cycle |
| PUSH: Past Deadline | Compliance contains `Past Deadline` | Immediate update investigation |
| PUSH: Install In Progress | Compliance contains `Install Started` | Watch installs and identify stalls |
| PUSH: Not Installed | Compliance says `PUSH not installed` or Health says `Not Installed` | Deployment coverage |
| PUSH: Not Configured | Compliance is `Not configured` | Macs without an update target |
| PUSH: Deadline Due or Past | Non-compliant and days remaining is below 1 | Deadline enforcement queue |
| PUSH: Deferrals Used | Deferral count is above 0 | Adoption and deferral analysis |
| PUSH: Deferrals Exhausted | Non-compliant and remaining deferrals is 0 | Users requiring enforcement |
| PUSH: Health Attention | Health contains `Attention` | Missing daemon, config, or stale auto-check |
| PUSH: Reboot Warning | Reboot status contains `Warning` | Friendly restart-reminder population |
| PUSH: Reboot Force | Reboot status contains `Force` | Forced restart population |

## Inventory timing

Extension Attributes run during Jamf inventory. Smart Group membership therefore
reflects the latest inventory submission, not a live query of the Mac. After
setup, run this on a pilot Mac:

```bash
sudo jamf recon
```

Review the Mac's inventory record before using a new group for policy scope.
Start with reports or exclusions, validate membership, and only then attach an
enforcement policy.

## Custom groups using the EAs

The seven EAs are intentionally reusable. Examples administrators can add in
Jamf without another script:

- Repeated deferrers: `PUSH — Deferral Count EA` more than `2`
- Meeting-related deferrals: `PUSH — Deferral Reasons EA` like `Meeting`
- Stale automation: `PUSH — Health EA` like `Auto-check stale`
- Specific PUSH release: `PUSH — Health EA` like `Version 1.1.0`

Do not build a group using only `Days Until Deadline = -1`; that value means no
deadline is configured. Combine deadline criteria with a non-compliant state.
