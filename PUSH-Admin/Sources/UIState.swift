// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: UIState.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

// UIState.swift — Popup states, exit codes, and shared runtime context for PUSH

import Foundation
import SwiftUI

// MARK: - Popup states

enum UIState: String {
    case updateRecovery = "updateRecovery"
    case toast          = "toast"
    case appUpdates     = "appUpdates"
    case entraRegistration = "entraRegistration"
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
        case .updateRecovery: return "Update needs attention"
        case .toast:          return "Software Update"
        case .appUpdates:     return "Application Updates"
        case .entraRegistration: return "Microsoft Entra Registration"
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
    case automaticRetry  = 7   // Countdown result; never a user Install choice
    case install         = 0   // User clicked Install / power detected / restart confirmed
    case defer_          = 1   // User clicked Remind Me Later (uses 1 deferral)
    case dismiss         = 2   // User dismissed (X / ESC / Skip)
    case scheduledDefer  = 3   // User picked a specific future date/time (no deferral cost)
    case powerTimeout    = 4   // Power preflight timed out — no charger connected
    case toastTimeout    = 5   // Toast closed after its configured timeout
    case contactSupport  = 6
    case error           = 99
}

// MARK: - Shared runtime context

class UIContext: ObservableObject {
    var informationalToastMessage: String?
    var recoveryNotice=RecoveryNotice.preview()
    let isPreview = true
    let isManualTest = true
    var onPreviewAction: ((String, String, Int32?, Bool) -> Void)?
    let config:        UIConfig
    let state:         UIState
    let deferralCount: Int
    let configPath:    String

    @Published var downloadProgress: Double = 0
    @Published var downloadSubtitle: String = "Preparing download…"

    var entraNotice = EntraNotice.preview()
    var appUpdates: [AppUpdateNotice] = AppUpdateNotice.examples
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

    @Published var demoAction = "Choose a button to see its simulated result."
    func noteAction(_ title: String) {
        demoAction = "SIMULATED: " + title
        onPreviewAction?(state.rawValue, title, nil, false)
    }
    func exit(_ code: PushExitCode, automatic: Bool = false) {
        switch code {
        case .automaticRetry: demoAction="SIMULATED: Recovery countdown reached. No update request was sent."
        case .install: demoAction = state == .entraRegistration ? "SIMULATED: Register Now selected. Self Service was not opened." : state == .appUpdates ? "SIMULATED: Update Closed Apps selected. No apps were updated." : "SIMULATED: Install / restart accepted. No action was sent to PUSH."
        case .defer_: demoAction = "SIMULATED: Reminder deferred. No settings were saved."
        case .contactSupport: demoAction = "SIMULATED: Support contact opened. No email was sent."
        case .toastTimeout: demoAction = "SIMULATED: Toast auto-dismissed. No installation was requested."
        case .scheduledDefer: demoAction = "SIMULATED: Reminder scheduled. No settings were saved."
        default: demoAction = "SIMULATED: Dismissed / completed (code \(code.rawValue))."
        }
        let title = previewButtonTitle(state:state.rawValue, code:code.rawValue)
        onPreviewAction?(state.rawValue, title, code.rawValue, automatic)
    }
}
