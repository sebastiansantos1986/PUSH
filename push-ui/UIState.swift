// UIState.swift — Popup states, exit codes, and shared runtime context for PUSH

import Foundation
import SwiftUI

// MARK: - Popup states

enum UIState: String {
    case toast          = "toast"
    case softNudge      = "softNudge"
    case hardBlock      = "hardBlock"
    case preflightPower = "preflightPower"
    case preflightDisk  = "preflightDisk"
    case passwordPrompt = "passwordPrompt"
    case downloading    = "downloading"
    case installing     = "installing"
    case rebooting      = "rebooting"
    case compliant      = "compliant"
    case error          = "error"
    case rebootNudge    = "rebootNudge"     // Warning phase — Later + Restart Now
    case rebootForce    = "rebootForce"     // Force phase — countdown + Restart Now only

    static func from(_ string: String) -> UIState {
        UIState(rawValue: string) ?? .softNudge
    }

    var windowTitle: String {
        switch self {
        case .toast:          return "Software Update"
        case .softNudge:      return "Software Update Required"
        case .hardBlock:      return "Immediate Update Required"
        case .preflightPower: return "Power Required"
        case .preflightDisk:  return "Disk Space Required"
        case .passwordPrompt: return "Authentication Required"
        case .downloading:    return "Downloading Update"
        case .installing:     return "Installing Update"
        case .rebooting:      return "Restart Required"
        case .compliant:      return "Up to Date"
        case .error:          return "Update Error"
        case .rebootNudge:    return "Restart Recommended"
        case .rebootForce:    return "Restart Required"
        }
    }
}

// MARK: - Exit codes

enum PushExitCode: Int32 {
    case install         = 0   // User clicked Install / power detected / restart confirmed
    case defer_          = 1   // User clicked Remind Me Later (uses 1 deferral)
    case dismiss         = 2   // User dismissed (X / ESC / Skip)
    case scheduledDefer  = 3   // User picked a specific future date/time (no deferral cost)
    case powerTimeout    = 4   // Power preflight timed out — no charger connected
    case error           = 99
}

// MARK: - Shared runtime context

class UIContext: ObservableObject {
    let config:        UIConfig
    let state:         UIState
    let deferralCount: Int
    let configPath:    String

    @Published var downloadProgress: Double = 0
    @Published var downloadSubtitle: String = "Preparing download…"

    var diskAvailableGB: Double = 8.5
    var diskRequiredGB:  Double = 25.0
    var errorMessage:    String = "An unexpected error occurred."
    // true = native pending update via softwareupdate (reboots in seconds)
    // false = full startosinstall (takes 45–60 min)
    var quickRestart:    Bool   = false
    var forcedInstall:   Bool   = false  // true = deadline forced, block quit shortcuts

    // Uptime monitoring popup parameters
    var uptimeDays:                Int = 0
    var uptimeDeferralsRemaining:  Int = 0
    var uptimeTimerSeconds:        Int = 600   // 10 min default countdown

    init(config: UIConfig, state: UIState,
         deferralCount: Int = 0, configPath: String = "") {
        self.config        = config
        self.state         = state
        self.deferralCount = deferralCount
        self.configPath    = configPath
    }

    var deferralsLeft: Int {
        max(0, config.update.maxDeferrals - deferralCount)
    }

    func exit(_ code: PushExitCode) {
        Foundation.exit(code.rawValue)
    }
}
