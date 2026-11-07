// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct WallpaperCommand {
    let args:[String]
    func run() {
        guard let config=try? loadConfig() else {cliError("Cannot read wallpaper policy.");return}
        switch args.first ?? "status" {
        case "status":
            cliInfo("Compliance wallpaper:",config.compliance.wallpaperEnabled ? "Enabled":"Disabled")
            cliInfo("Configured macOS target:",config.update.targetVersion.isEmpty ? "Not selected":config.update.targetVersion)
            cliInfo("Non-compliant image:",config.compliance.nonCompliantWallpaper)
            cliInfo("Compliant action:",config.compliance.compliantWallpaper.isEmpty ? "Restore captured personal image when still managed":config.compliance.compliantWallpaper)
            cliInfo("Dry run:",String(config.debug.dryRun))
            cliPrint("Saved policy only. Use Wallpaper in PUSH Admin to preview or stage images.")
        case "reconcile":
            guard getuid()==0 else {cliError("Use sudo for live wallpaper reconciliation.");return}
            guard !args.contains("--dry-run"),!config.debug.dryRun else {cliPrint("Dry run: would reconcile wallpaper only. Desktop and OS unchanged.");return}
            WallpaperEnforcement(config:config).run(running:currentMacOSVersion())
            cliPrint("Wallpaper-only reconciliation finished. No macOS update workflow was requested; review Delivery History for the result.")
        default:cliError("Usage: push-cli wallpaper status|reconcile [--dry-run]. Reconcile can change the desktop, but never installs macOS.")
        }
    }
}
