// WallpaperCommand.swift — `push-cli wallpaper` subcommand.
//
// Manual wallpaper application for testing and IT diagnostics.
//
// Usage:
//   push-cli wallpaper apply compliant      — force compliant wallpaper
//   push-cli wallpaper apply non-compliant  — force non-compliant wallpaper
//   push-cli wallpaper apply auto           — pick based on current vs target
//   push-cli wallpaper status               — show last-applied state
//   push-cli wallpaper install-desktoppr    — manually trigger desktoppr install

import Foundation

struct WallpaperCommand {
    let args: [String]

    func run() {
        guard let sub = args.first else { printHelp(); return }

        guard let config = try? loadConfig() else {
            cliError("Failed to load config")
            exit(1)
        }

        switch sub {
        case "apply":
            guard args.count >= 2 else {
                cliError("Usage: push-cli wallpaper apply [compliant|non-compliant|auto]")
                exit(1)
            }
            let target = args[1].lowercased()
            let mgr = WallpaperManager(config: config)

            switch target {
            case "compliant":
                if mgr.applyForce(.compliant) {
                    cliSuccess("Applied compliant wallpaper")
                } else {
                    cliError("Failed to apply compliant wallpaper (check log for details)")
                    exit(1)
                }
            case "non-compliant", "noncompliant":
                if mgr.applyForce(.nonCompliant) {
                    cliSuccess("Applied non-compliant wallpaper")
                } else {
                    cliError("Failed to apply non-compliant wallpaper (check log for details)")
                    exit(1)
                }
            case "auto":
                let desired = WallpaperManager.currentDesiredState(config: config)
                cliPrint("Auto: current state is \(desired.rawValue)")
                if mgr.applyForce(desired) {
                    cliSuccess("Applied \(desired.rawValue) wallpaper")
                } else {
                    cliError("Failed to apply \(desired.rawValue) wallpaper (check log for details)")
                    exit(1)
                }
            default:
                cliError("Unknown target '\(target)'. Use compliant | non-compliant | auto")
                exit(1)
            }

        case "status":
            let state = loadState()
            print("")
            print("🖼  Compliance Wallpaper")
            print("──────────────────────────────────────────────────")
            print("  Enabled:                 \(config.compliance.wallpaperEnabled ? "Yes" : "No")")
            print("  Last applied state:      \(state.lastAppliedWallpaperState.isEmpty ? "(never)" : state.lastAppliedWallpaperState)")
            print("  Compliant image:         \(config.compliance.compliantWallpaper)")
            print("    Exists:                \(FileManager.default.fileExists(atPath: config.compliance.compliantWallpaper) ? "✅" : "❌")")
            print("  Non-compliant image:     \(config.compliance.nonCompliantWallpaper)")
            print("    Exists:                \(FileManager.default.fileExists(atPath: config.compliance.nonCompliantWallpaper) ? "✅" : "❌")")
            print("  desktoppr binary:        \(config.compliance.desktopprPath)")
            print("    Installed:             \(FileManager.default.isExecutableFile(atPath: config.compliance.desktopprPath) ? "✅" : "❌")")
            print("  desktoppr installer:     \(config.compliance.desktopprPkgPath)")
            print("    Bundled:               \(FileManager.default.fileExists(atPath: config.compliance.desktopprPkgPath) ? "✅" : "❌")")
            print("  Background color:        #\(config.compliance.wallpaperBackgroundColor)")
            print("  Scale mode:              \(config.compliance.wallpaperScale)")

        case "install-desktoppr":
            let mgr = WallpaperManager(config: config)
            if mgr.installDesktopprIfNeeded() {
                cliSuccess("desktoppr is installed and ready")
            } else {
                cliError("Failed to install desktoppr (check log for details)")
                exit(1)
            }

        case "enable":
            // Convenience verb that flips wallpaperEnabled to true.
            // Same effect as: push-cli config set compliance.wallpaperEnabled true
            ConfigCommand(args: ["set", "compliance.wallpaperEnabled", "true"]).run()

        case "disable":
            // Convenience verb that flips wallpaperEnabled to false. The
            // currently-displayed wallpaper stays — disable just means future
            // auto-checks won't apply transitions. To revert to system default
            // wallpaper the user changes it manually.
            ConfigCommand(args: ["set", "compliance.wallpaperEnabled", "false"]).run()

        case "--help", "-h", "help":
            printHelp()

        default:
            cliError("Unknown subcommand '\(sub)'")
            printHelp()
            exit(1)
        }
    }

    private func printHelp() {
        print("""
        Usage: push-cli wallpaper <subcommand> [args]

        Subcommands:
          enable                Turn on compliance wallpaper switching
          disable               Turn off compliance wallpaper switching
          apply <state>         Apply wallpaper for state (compliant|non-compliant|auto)
          status                Show wallpaper config and last-applied state
          install-desktoppr     Lazy-install desktoppr from bundled pkg
          help                  Show this message

        Auto state is determined by comparing current macOS to update.targetVersion.
        """)
    }
}
