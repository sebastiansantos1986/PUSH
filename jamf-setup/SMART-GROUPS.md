# PUSH — Smart Group Reference

Six Smart Computer Groups built around the `OS Update Compliance` Extension Attribute. Each group answers a specific operational question.

## Quick reference

| Group                          | Answers                                                | Use when                                                            |
|--------------------------------|--------------------------------------------------------|---------------------------------------------------------------------|
| PUSH: Compliant                | "How many Macs are on the target version?"            | Daily compliance dashboards                                         |
| PUSH: Non-Compliant - Active   | "Who's still working through the nudge cycle?"        | Pilot monitoring, deferral pattern analysis                         |
| PUSH: Past Deadline            | "Who's past their deadline and needs intervention?"   | Triage list — these Macs should be installing now or escalated      |
| PUSH: Install In Progress      | "Who's installing right now?"                         | Spot installs that may have stalled mid-flight                      |
| PUSH: Not Reporting            | "Who's missing PUSH or hasn't checked in?"            | Deployment progress, find Macs needing PUSH installed               |
| PUSH: Reboot Pending           | "Who needs to restart their Mac?"                     | Nudge users with stale uptime even though OS is current             |

## Group definitions

### PUSH: Compliant

**EA value matches:** `like "Compliant"`

**Includes Macs that are:**
- On the target macOS version, OR
- Have no target set yet (fresh install — PUSH hasn't decided non-compliance)

This is the goal state. Most Macs should be here most of the time.

**Sample EA values:**
- `Compliant | 26.4.1 | Target: 26.4.1`
- `Compliant | 26.4.1 | Target: (none)`

### PUSH: Non-Compliant - Active

**EA value matches:** `like "Non-Compliant"` AND `not like "Past-Deadline"`

**Includes Macs that:**
- Are behind the target version
- Are still within their deadline window
- Have used some or all of their deferrals but the deadline hasn't hit

This is the "soft pressure" group — these Macs are seeing nudges but the user is still in control. Worth watching to see how deferrals trend before deadline.

**Sample EA value:**
- `Non-Compliant | 15.0 → 26.4.1 | Deferrals: 3/7`

### PUSH: Past Deadline

**EA value matches:** `like "Past-Deadline"`

**Includes Macs that:**
- Are behind the target version
- Have passed their deadline date
- Should be auto-installing on next auto-check (or already are, in which case they'll move to Install In Progress)

This is the most actionable group. If a Mac sits here for more than a day or two, something's blocking auto-install — investigate.

Possible blockers:
- User in active screen share / meeting (intentional skip)
- No console user logged in (waiting for login)
- Saved password invalid
- Disk space / power preflight failing
- startosinstall keeps failing for some reason

**Sample EA value:**
- `Past-Deadline | 15.0 → 26.4.1 | Install-Pending`

### PUSH: Install In Progress

**EA value matches:** `like "Install-Started"`

**Includes Macs where:**
- `installStarted: true` and `installCompleted: false` in state.json
- Either downloading the installer or running startosinstall

For a healthy install, a Mac is in this group for 30-60 minutes (download + install + reboot). If a Mac is here longer than ~90 minutes, the install probably stalled.

**Sample EA value:**
- `Install-Started | 15.0 → 26.4.1`

### PUSH: Not Reporting

**EA value matches:** `is "Not Installed"` OR `is (blank)`

**Includes Macs that:**
- Don't have PUSH installed (`Not Installed` returned by the EA script)
- Or haven't run inventory recently and Jamf has no value

Use this to track deployment progress when rolling PUSH to new groups.

### PUSH: Reboot Pending

**EA value matches:** `like "Reboot-Pending"`

**Includes Macs that:**
- Are on the target version (so OS-compliant)
- Have a long enough uptime to trigger PUSH's reboot reminders

This catches the "running 30 days without restart" case. Different problem than OS compliance — these Macs need a restart for security reasons, not version updates.

**Note:** Reboot reminders are a separate feature controlled by `uptime.enabled` in PUSH's config. If you haven't enabled uptime monitoring fleet-wide, this group will be empty.

**Sample EA value:**
- `Reboot-Pending | Uptime: 21d`

## Operational dashboards

A useful Jamf dashboard would show counts for:
- PUSH: Compliant (target: 100% of fleet eventually)
- PUSH: Non-Compliant - Active (target: trends toward 0 as deadline approaches)
- PUSH: Past Deadline (target: 0 — anything here is an issue)
- PUSH: Install In Progress (snapshot in time — watching for stalls)
- PUSH: Not Reporting (target: 0 once deployment finishes)

Jamf Pro doesn't have a built-in "show counts as a widget" — but you can:
- Use Smart Group membership counts (visible on the group's page)
- Build a Splunk/Datadog dashboard that polls Jamf API for membership counts
- Generate a weekly report email via Jamf Self Service or a separate cron

## Adjusting criteria

If you want different filtering:

- **Want only Macs past deadline by 24h+?** Add an "Inventory General Information" criterion for Last Inventory Update.
- **Want to exclude opt-out users?** Add a criterion: "Username" not in [list of names].
- **Want to scope to specific OS versions?** Add a criterion on Operating System version.

Smart Groups are filters on top of inventory — they reflect the snapshot from each Mac's last recon, not real-time state.
