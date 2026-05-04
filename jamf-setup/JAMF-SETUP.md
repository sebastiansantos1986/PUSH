# PUSH — Jamf Setup

This document describes how to set up the PUSH-related Extension Attribute and Smart Computer Groups in Jamf Pro. The recommended path is the automation script (`setup-jamf.sh`); these manual instructions are a fallback if the script fails or you prefer clicking.

## What this creates

- 1 Extension Attribute that runs `push-os-compliance.sh` on each Mac to report compliance
- 6 Smart Computer Groups that filter Macs based on the EA's value

## Prerequisites

- Jamf Pro admin access
- An API client with the following privileges (only needed if running the automation script):
  - Read + Create Computer Extension Attributes
  - Read + Create Smart Computer Groups
  - Read Computers

## Automated path (preferred)

```bash
# Dry-run first (no changes made)
./setup-jamf.sh --jamf-url https://yourtenant.jamfcloud.com --client-id YOUR_ID

# Actually create things, with per-object confirmation
./setup-jamf.sh --jamf-url https://yourtenant.jamfcloud.com --client-id YOUR_ID --apply
```

The script reads your existing Jamf state, prints what it would create, and asks per-object before each create. It will skip anything that already exists with the matching name.

## Manual path

### 1. Create the Extension Attribute

In Jamf Pro web UI:

1. Go to **Settings** → **Computer Management** → **Extension Attributes**
2. Click **New**
3. Configure:
   - **Display Name:** `OS Update Compliance`
   - **Description:** `PUSH compliance state`
   - **Data Type:** `String`
   - **Inventory Display:** `Operating System`
   - **Input Type:** `Script`
4. In the script editor, paste the contents of `push-os-compliance.sh`
5. Click **Save**

### 2. Create Smart Computer Groups

For each group below, in Jamf Pro:

1. Go to **Computers** → **Smart Computer Groups**
2. Click **New**
3. Set the **Name** as listed below
4. Switch to the **Criteria** tab
5. Add criteria as listed below
6. **Save**

#### PUSH: Compliant

| And/Or | Criteria              | Operator      | Value       |
|--------|-----------------------|---------------|-------------|
| —      | OS Update Compliance  | like          | Compliant   |

#### PUSH: Non-Compliant - Active

| And/Or | Criteria              | Operator      | Value           |
|--------|-----------------------|---------------|-----------------|
| —      | OS Update Compliance  | like          | Non-Compliant   |
| And    | OS Update Compliance  | not like      | Past-Deadline   |

#### PUSH: Past Deadline

| And/Or | Criteria              | Operator      | Value           |
|--------|-----------------------|---------------|-----------------|
| —      | OS Update Compliance  | like          | Past-Deadline   |

#### PUSH: Install In Progress

| And/Or | Criteria              | Operator      | Value             |
|--------|-----------------------|---------------|-------------------|
| —      | OS Update Compliance  | like          | Install-Started   |

#### PUSH: Not Reporting

| And/Or | Criteria              | Operator      | Value          |
|--------|-----------------------|---------------|----------------|
| —      | OS Update Compliance  | is            | Not Installed  |
| Or     | OS Update Compliance  | is            | (blank)        |

#### PUSH: Reboot Pending

| And/Or | Criteria              | Operator      | Value           |
|--------|-----------------------|---------------|-----------------|
| —      | OS Update Compliance  | like          | Reboot-Pending  |

## After setup

### Test the EA

On any Mac with PUSH installed:

```bash
sudo jamf recon
```

Wait ~30 seconds for inventory to sync. In Jamf web UI, go to that Mac's record → Extension Attributes tab → look for `OS Update Compliance`. It should show a value like `Compliant | 26.4.1 | Target: 26.4.1`.

### Verify Smart Groups

In Jamf web UI, click into each Smart Group and check the membership. After the first inventory cycle, every PUSH-equipped Mac should appear in exactly one of:
- Compliant
- Non-Compliant - Active
- Past Deadline
- Install In Progress

(A Mac with reboot pending while otherwise compliant would also show in Reboot Pending.)

### Disable PUSH's API-based EA reporting (optional)

PUSH's auto-check writes to the EA via API by default. If you want a single source of truth (the script-type EA), disable PUSH's API reporting:

On each Mac:
```bash
sudo /Library/Management/PUSH/push-cli config set jamf.reportEAAfterCheck false
```

Or push this via Jamf script to all enrolled Macs.

## Troubleshooting

### EA value shows blank in Jamf

- Confirm the EA script is actually saved in Jamf (Settings → Computer Management → Extension Attributes → click into it → check the script content)
- Confirm the Mac has PUSH installed: `[ -x /Library/Management/PUSH/push-cli ]`
- Run the script manually on a Mac to see what it returns: `sudo bash /path/to/push-os-compliance.sh`
- Check that Mac's last inventory time in Jamf — if it's stale, run `sudo jamf recon`

### Smart Group membership looks wrong

- Smart Groups update on inventory; force a recon: `sudo jamf recon`
- Check the EA's actual value first — Smart Group is just a filter on top
- If a Mac isn't in any group, EA may be returning something unexpected; run the script manually on that Mac

### Script returns "Not Installed" but PUSH IS installed

- The script checks `/Library/Management/PUSH/push-cli` exists and is executable
- Verify: `ls -la /Library/Management/PUSH/push-cli`
- If it's not executable, fix: `sudo chmod +x /Library/Management/PUSH/push-cli`
