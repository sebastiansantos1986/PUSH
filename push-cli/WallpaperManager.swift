// WallpaperManager.swift — Sets the desktop wallpaper based on compliance state.
//
// Provides passive visual signaling — a compliant Mac shows one wallpaper, a
// non-compliant Mac shows another. No popup, no nag — just a desktop change
// the user notices when they look at their screen.
//
// Wallpaper apply only fires on STATE TRANSITIONS, not on every auto-check.
// state.json tracks the last-applied state ("compliant" / "non-compliant" / "")
// and the manager is a no-op when current state equals last-applied state.
// This means the user keeps any custom wallpaper they set in between transitions.
//
// Uses desktoppr (https://github.com/scriptingosx/desktoppr) under the hood.
// If desktoppr isn't installed, attempts a lazy install from the bundled .pkg
// at config.compliance.desktopprPkgPath.

import Foundation

enum WallpaperState: String {
    case compliant     = "compliant"
    case nonCompliant  = "non-compliant"
}

struct WallpaperManager {
    let config: CLIConfig

    /// Apply the wallpaper for the given state, but only if it differs from
    /// what was last applied. Idempotent — safe to call on every auto-check.
    /// Returns true if a change was made, false if no-op.
    @discardableResult
    func applyIfStateChanged(_ desired: WallpaperState) -> Bool {
        guard config.compliance.wallpaperEnabled else { return false }

        let state = loadState()
        if state.lastAppliedWallpaperState == desired.rawValue {
            return false
        }

        cliLog("[Wallpaper] State transition detected: \(state.lastAppliedWallpaperState.isEmpty ? "<unset>" : state.lastAppliedWallpaperState) → \(desired.rawValue)")
        let success = applyForce(desired)
        if success {
            var s = loadState()
            s.lastAppliedWallpaperState = desired.rawValue
            try? saveState(s)
        }
        return success
    }

    /// Apply the wallpaper for the given state unconditionally. Used by the
    /// CLI subcommand and the install-completion hook where we want to force
    /// the wallpaper regardless of last-applied state.
    @discardableResult
    func applyForce(_ desired: WallpaperState) -> Bool {
        guard config.compliance.wallpaperEnabled else {
            cliLog("[Wallpaper] Skipped — wallpaperEnabled is false")
            return false
        }

        let imagePath: String
        switch desired {
        case .compliant:    imagePath = config.compliance.compliantWallpaper
        case .nonCompliant: imagePath = config.compliance.nonCompliantWallpaper
        }

        guard FileManager.default.fileExists(atPath: imagePath) else {
            cliLog("[Wallpaper] ERROR: Wallpaper image not found: \(imagePath)")
            return false
        }

        // Need a console user — desktoppr can only set wallpaper for an
        // active GUI session. No user logged in = silent no-op (will retry
        // when user logs in and auto-check runs again).
        guard let user = consoleUser() else {
            cliLog("[Wallpaper] No console user — skipping (will retry next run)")
            return false
        }

        // Lazy-install desktoppr if missing
        if !FileManager.default.isExecutableFile(atPath: config.compliance.desktopprPath) {
            cliLog("[Wallpaper] desktoppr not found at \(config.compliance.desktopprPath) — attempting lazy install")
            if !installDesktopprIfNeeded() {
                cliLog("[Wallpaper] ERROR: desktoppr install failed — cannot apply wallpaper")
                return false
            }
        }

        cliLog("[Wallpaper] Setting \(desired.rawValue) wallpaper for \(user.name): \(imagePath)")

        let dp = config.compliance.desktopprPath
        // Three sequential calls — image, scale, color. Each launchctl asuser
        // exec is independent so no need for chained sleeps.
        let cmd1 = "launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \"\(dp)\" \"\(imagePath)\""
        let cmd2 = "launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \"\(dp)\" scale \(config.compliance.wallpaperScale)"
        let cmd3 = "launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \"\(dp)\" color \(config.compliance.wallpaperBackgroundColor)"

        let (_, st1) = shell(cmd1)
        let (_, st2) = shell(cmd2)
        let (_, st3) = shell(cmd3)

        if st1 == 0 && st2 == 0 && st3 == 0 {
            cliLog("[Wallpaper] Successfully applied \(desired.rawValue) wallpaper")
            return true
        } else {
            cliLog("[Wallpaper] WARNING: One or more desktoppr calls failed (image=\(st1), scale=\(st2), color=\(st3))")
            // Partial success is still useful — the image likely landed even if
            // scale or color tweaks failed. Don't treat partial as full failure.
            return st1 == 0
        }
    }

    /// Lazy-install desktoppr from the bundled pkg. Returns true if desktoppr
    /// is installed and executable after this call.
    @discardableResult
    func installDesktopprIfNeeded() -> Bool {
        if FileManager.default.isExecutableFile(atPath: config.compliance.desktopprPath) {
            return true
        }
        let pkg = config.compliance.desktopprPkgPath
        guard FileManager.default.fileExists(atPath: pkg) else {
            cliLog("[Wallpaper] desktoppr pkg not bundled at \(pkg) — cannot lazy-install")
            return false
        }
        cliLog("[Wallpaper] Installing desktoppr from \(pkg)")
        let (out, st) = shell("/usr/sbin/installer -pkg \"\(pkg)\" -target / 2>&1")
        if st == 0 && FileManager.default.isExecutableFile(atPath: config.compliance.desktopprPath) {
            cliLog("[Wallpaper] desktoppr installed successfully")
            return true
        } else {
            cliLog("[Wallpaper] desktoppr install failed (exit \(st)): \(out.prefix(500))")
            return false
        }
    }

    /// Convenience helper — reads current macOS version, compares to target,
    /// returns the appropriate WallpaperState. "auto" mode for CLI command.
    static func currentDesiredState(config: CLIConfig) -> WallpaperState {
        let current = currentMacOSVersion()
        let target  = config.update.targetVersion
        if target.isEmpty || versionGTE(current, target) {
            return .compliant
        }
        return .nonCompliant
    }
}
