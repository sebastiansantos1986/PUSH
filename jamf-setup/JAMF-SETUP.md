# PUSH - Automated Jamf Setup

PUSH includes a dry-run-first setup utility that creates seven Extension
Attributes and twelve Smart Computer Groups. This removes the need for every
Jamf administrator to paste scripts and build criteria one object at a time.

## Required Jamf API role

Create an API Role and Client in **Settings > System > API Roles and Clients**.
Grant only these privileges:

- Read and Create Computer Extension Attributes
- Read and Create Smart Computer Groups
- Read Computers

Add Update Computer Extension Attributes only when using
`jamf-ea-fix/update-jamf-eas.sh` to replace scripts in existing EAs.

The client secret is requested securely at runtime. It is not accepted as a
command-line argument and is not written to disk.

## Run a dry run

From the cloned PUSH repository:

```bash
cd jamf-setup
./setup-jamf.sh \
  --jamf-url https://YOUR-TENANT.jamfcloud.com \
  --client-id YOUR_API_CLIENT_ID
```

The output lists every object as `CREATE` or `SKIP`. A dry run does not change
Jamf.

## Create the objects

After reviewing the plan:

```bash
./setup-jamf.sh \
  --jamf-url https://YOUR-TENANT.jamfcloud.com \
  --client-id YOUR_API_CLIENT_ID \
  --apply
```

The script asks before each creation and verifies the object afterward. Add
`--yes` only after a successful dry run if you want unattended creation.

Existing objects are left untouched. To update the script body of existing EAs,
use the separate updater, which backs up current scripts first:

```bash
cd ../jamf-ea-fix
./update-jamf-eas.sh \
  --jamf-url https://YOUR-TENANT.jamfcloud.com \
  --client-id YOUR_API_CLIENT_ID \
  --apply
```

## Validate with a pilot Mac

1. Install PUSH on one test Mac.
2. Run `sudo jamf recon`.
3. Open that computer in Jamf and review its Extension Attributes.
4. Confirm it enters the expected Smart Groups.
5. Validate group membership before attaching policies or enforcement actions.

Typical healthy values are:

```text
PUSH — OS Update Compliance EA: Compliant
PUSH — Days Until Deadline EA: -1
PUSH — Deferral Count EA: 0
PUSH — Deferral Reasons EA: None
PUSH — Deferrals Remaining EA: 5
PUSH — Health EA: Healthy | Version 1.1.7 | Daemon loaded | Last activity 1h
PUSH — Reboot Status EA: Healthy | Uptime 3d
```

`Days Until Deadline = -1` is normal when no deadline is configured. `Deferral
Reasons = None` is normal until a user supplies a reason. `PUSH not installed`
means the compliance EA ran successfully but could not find the PUSH CLI.

See [SMART-GROUPS.md](SMART-GROUPS.md) for all generated groups and criteria.

## Troubleshooting

- **EA remains blank:** run `sudo jamf recon`, then check the Mac's latest
  inventory time.
- **PUSH says not installed:** verify
  `/Library/Management/PUSH/push-cli` exists and is executable.
- **Health says daemon not loaded:** run
  `sudo launchctl print system/com.push.autoupdate` and reinstall the daemon if
  needed.
- **Group membership seems wrong:** inspect the EA value first. Groups evaluate
  the most recently submitted inventory, not live state.
- **An existing EA script is outdated:** use `update-jamf-eas.sh`; the setup
  utility intentionally never overwrites an existing EA.
