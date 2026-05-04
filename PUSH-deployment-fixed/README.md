# PUSH Deployment Guide

## Files in this package

```
PUSH-deployment/
├── build-pkg.sh                  Build script — creates PUSH-1.0.0.pkg
├── push-jamf-postinstall.sh      Jamf policy script — runs after pkg installs
├── push-uninstall.sh             Full removal script
└── pkg-build/
    ├── scripts/
    │   ├── preinstall            Runs before pkg payload drops
    │   └── postinstall           Runs after pkg payload drops
    └── payload/
        └── Library/
            ├── LaunchDaemons/
            │   └── com.push.autoupdate.plist
            └── Management/PUSH/
                └── config.yaml   Default config (post-install script customizes it)
```

---

## Step 1 — Build the pkg

Build both Xcode targets first (`push-cli` and `push-ui`), then:

```bash
cd PUSH-deployment
bash build-pkg.sh
```

For a signed pkg (required for notarization and some MDM profiles):
```bash
bash build-pkg.sh --sign "Developer ID Installer: Your Name (TEAMID)"
```

This outputs `PUSH-1.0.0.pkg`.

---

## Step 2 — Customize the post-install script

Open `push-jamf-postinstall.sh` and fill in your org values at the top:

```bash
ORG_NAME="Forcepoint"
IT_EMAIL="it@forcepoint.com"
IT_PHONE="1-512-214-0341"
ACCENT_COLOR="#0066CC"
ENFORCE_MAJOR_VERSION="26"
WEBHOOK_URL="https://forcepointcml.webhook.office.com/..."
HARD_BLOCK_FULLSCREEN="false"
```

---

## Step 3 — Upload to Jamf Pro

1. **Upload the pkg:**
   Jamf Pro → Settings → Packages → New → Upload `PUSH-1.0.0.pkg`

2. **Upload the post-install script:**
   Jamf Pro → Settings → Scripts → New → paste `push-jamf-postinstall.sh`
   - Priority: **After**

3. **Upload the uninstall script:**
   Jamf Pro → Settings → Scripts → New → paste `push-uninstall.sh`
   - Priority: **After**

---

## Step 4 — Create the deployment policy

Jamf Pro → Computers → Policies → New:

| Field         | Value                              |
|---------------|------------------------------------|
| Name          | PUSH — Deploy Update Enforcement   |
| Trigger       | Recurring Check-in                 |
| Frequency     | Once per computer                  |
| Packages      | PUSH-1.0.0.pkg                    |
| Scripts       | push-jamf-postinstall.sh (After)   |
| Scope         | All Computers (or your smart group)|

---

## Step 5 — Create the uninstall policy (for rollback)

Jamf Pro → Computers → Policies → New:

| Field         | Value                              |
|---------------|------------------------------------|
| Name          | PUSH — Remove Update Enforcement   |
| Trigger       | Manual / Self Service              |
| Frequency     | Once per computer                  |
| Scripts       | push-uninstall.sh (After)          |
| Scope         | IT staff / test group              |

---

## Step 6 — Add Extension Attributes

See `PUSH-jamf-EAs/README.md` for the 4 EA scripts and smart group recommendations.

---

## Verifying deployment

After the policy runs on a machine:

```bash
# Check it's installed
push-cli --version

# Check status
push-cli status

# Check LaunchDaemon is loaded
sudo launchctl list | grep com.push

# Check config was applied
push-cli config get ui.orgName
push-cli config get auto.enforceMinimumMajorVersion
```

---

## Updating PUSH

1. Build new binaries in Xcode
2. Run `bash build-pkg.sh` to create new pkg
3. Update version in `build-pkg.sh` (`VERSION="1.0.1"`)
4. Upload new pkg to Jamf
5. Change policy frequency to "Once per computer per version"

Or use self-update:
```bash
sudo push-cli self-update
```
