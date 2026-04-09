// main.swift — push-cli entry point
// PUSH — Proactive Update Scheduling Helper

import Foundation

let cliVersion = "1.1.0"

func printHelp() {
    print("""
\u{001B}[1mpush-cli\u{001B}[0m v\(cliVersion) — PUSH Command Line Interface

\u{001B}[1mDETECTION & SCHEDULING\u{001B}[0m
  auto-check              Detect updates, manage nudge schedule
  auto-check --dry-run    Preview without writing anything
  auto-check --force      Re-run even if version already configured

\u{001B}[1mSTATUS\u{001B}[0m
  status                  Full compliance report
  check                   Exit 0=compliant, 1=needs update, 2=error

\u{001B}[1mCONFIG\u{001B}[0m
  config show             Print current config (YAML)
  config get <key>        Read one value  (e.g. update.targetVersion)
  config set <key> <val>  Write one value (e.g. update.maxDeferrals 5)
  config validate         Check config for errors

\u{001B}[1mPOPUPS\u{001B}[0m
  popup <state>                     Show a popup manually
  popup toast                       Corner toast notification
  popup softNudge                   Soft nudge popup
  popup hardBlock                   Hard block popup
  popup downloading                 Download progress popup
    --download-progress 0.42        Progress 0.0 to 1.0
  popup preflightDisk               Disk space warning
    --disk-available 8.5            Available GB
    --disk-required 25              Required GB
  popup preflightPower              AC power required popup
  popup installing                  Installing popup
  popup rebooting                   Reboot countdown
  popup compliant                   Already up to date
  popup error --error "message"     Error popup

\u{001B}[1mINSTALL\u{001B}[0m
  install                 Run full install workflow (auto-detects best method)
  download                Download macOS update without installing
  download --method native         Force softwareupdate download
  download --method mist           Force mist-cli download
  download --beta                  Include beta builds (mist only)
  install-extras          Install non-system updates (Xcode, CLT, etc.)
  install-safari          Install Safari update only
  report                  Compliance report (--json or --csv)

\u{001B}[1mAUTH\u{001B}[0m
  auth set-password         Store local admin password in System Keychain (recommended)
  auth set-password --account localadmin  Specify account
  auth show                 Show stored credentials status
  auth clear                Remove credentials from keychain

\u{001B}[1mMDM / JAMF\u{001B}[0m
  mdm push                Push MDM install for configured target version
  mdm push --minor        Push latest minor update via MDM
  mdm push --major        Push latest major upgrade via MDM
  mdm push --version 26.4 Push specific version via MDM
  mdm download            Push download-only via MDM
  mdm check               Check MDM enrollment + bootstrap token + user auth
  mdm recon               Submit Jamf inventory (jamf recon)
  mdm fix-swu             Restart softwareupdate daemons
  grace grant --days 7    Grant IT grace period extension
  grace status            Check active grace period
  grace revoke            Remove grace period
  self-update             Update push-cli to latest version
  self-update --check     Check if update is available (exit 0=current, 1=available)
  dashboard               Generate HTML compliance dashboard
  dashboard --open        Generate and open in browser
  dashboard --output <f>  Save to file

\u{001B}[1mSTATE\u{001B}[0m
  reset                   Clear all deferrals and state
  reset --deferrals-only  Clear deferral count only

\u{001B}[1mLOGGING\u{001B}[0m
  log show                Print recent log entries (last 50 lines)
  log show --lines 100    Print last N lines
  log tail                Stream live log output (Ctrl+C to stop)
  log clear               Clear the log file

\u{001B}[1mDAEMON\u{001B}[0m
  install-daemon              Install LaunchDaemon (runs auto-check on schedule)
  install-daemon --interval 2h  Custom interval: 1h, 2h, 4h, 8h, 24h
  uninstall-daemon            Remove LaunchDaemon

\u{001B}[1mDEBUG\u{001B}[0m
  debug on                Enable dry-run mode (no actual install)
  debug off               Disable dry-run mode
  debug status            Show debug state

\u{001B}[1mEXAMPLES\u{001B}[0m
  sudo push-cli auto-check
  push-cli status
  push-cli config get update.targetVersion
  sudo push-cli config set update.targetVersion 15.7.5
  sudo push-cli reset --deferrals-only
  push-cli popup toast
  sudo push-cli install-daemon --interval 2h
  sudo push-cli uninstall-daemon
""")
}

let args    = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? ""
let rest    = args.isEmpty ? [] : Array(args.dropFirst())

switch command {
case "auto-check":       AutoCheckCommand(args: rest).run()
case "status":           StatusCommand(args: rest).run()
case "check":            CheckCommand(args: rest).run()
case "config":           ConfigCommand(args: rest).run()
case "popup":            PopupCommand(args: rest).run()
case "install":          InstallWorkflow(config: (try? loadConfig()) ?? CLIConfig()).run()
case "download":         DownloadCommand(args: rest).run()
case "install-extras":   InstallExtrasCommand(args: rest).run()
case "install-safari":   InstallSafariCommand(args: rest).run()
case "auth":             AuthCommand(args: rest).run()
case "mdm":              MDMCommand(args: rest).run()
case "reset":            ResetCommand(args: rest).run()
case "report":           ReportCommand(args: rest).run()
case "grace":            GraceCommand(args: rest).run()
case "log":              LogCommand(args: rest).run()
case "install-daemon":   InstallDaemonCommand(args: rest).run()
case "uninstall-daemon": UninstallDaemonCommand(args: rest).run()
case "self-update":      SelfUpdateCommand(args: rest).run()
case "dashboard":        DashboardCommand(args: rest).run()
case "debug":            DebugCommand(args: rest).run()
case "--help", "-h", "help", "": printHelp(); exit(0)
case "--version", "-v":  print("push-cli v\(cliVersion)"); exit(0)
default:
    cliError("Unknown command '\(command)'. Run push-cli --help for usage.")
    exit(1)
}
