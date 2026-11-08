// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: main.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

// main.swift — push-ui entry point
// Transparent window enables frosted glass (.regularMaterial) throughout.

import SwiftUI
import AppKit

// MARK: - Argument parsing

let args = CommandLine.arguments
if Bundle.main.bundleIdentifier=="com.push.notice" {
    guard args.count==3,args[1]=="--notice-payload" else {Foundation.exit(99)}
    MainActor.assumeIsolated {StandaloneNoticePresenter.run(args[2])}
}
// A dedicated app identity always enters simulation before any live handler.
if Bundle.main.bundleIdentifier=="com.push.major-demo" {MainActor.assumeIsolated {MajorUpgradeDemoPresenter.run(Array(args.dropFirst()))}}
handleWallpaperRequest(args)
if Bundle.main.bundleIdentifier=="com.push.status" {PushStatusApp.main();Foundation.exit(0)}
handleCredentialRequest(args)

func argVal(_ flag: String) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

if args.contains("--help") || args.contains("-h") {
    print("""
push-ui — PUSH Popup UI Engine

USAGE
  push-ui --state <state> [options]

STATES
  toast             Corner notification
  softNudge         Soft nudge — user must click
  hardBlock         Hard block — deadline passed or deferrals exhausted
  preflightPower    Waiting for AC power (exits 0=power found, 4=timeout, 2=skip)
  preflightDisk     Insufficient disk space
  passwordPrompt    Apple Silicon auth prompt
  downloading       Download progress
  installing        Installation in progress
  rebooting         60-second restart countdown
  compliant         Already up to date
  error             Error popup

OPTIONS
  --config <path>           Config file path (default: /Library/Management/PUSH/config.yaml)
  --deferrals <n>           Current deferral count
  --download-progress <n>   Progress 0.0–1.0
  --download-subtitle <s>   Progress subtitle
  --disk-available <n>      Available disk GB
  --disk-required <n>       Required disk GB
  --error <message>         Error message text

EXIT CODES
  0   Install / power detected / restart
  1   Remind Me Later / defer
  2   Dismissed / skipped
  4   Power preflight timed out
  99  Error
""")
    Foundation.exit(0)
}

// Parse arguments
let stateStr      = argVal("--state")    ?? "softNudge"
if stateStr == "passwordPrompt" && !allowsUserPasswordPrompts {
    print("User password prompts are disabled. IT must provide managed authorization.")
    Foundation.exit(2)
}
let configPath    = argVal("--config")   ?? "/Library/Management/PUSH/config.yaml"
let deferralStr   = argVal("--deferrals") ?? "0"
let deferralCount = Int(deferralStr) ?? 0

let state  = UIState.from(stateStr)
var config = FileManager.default.fileExists(atPath: configPath)
    ? UIConfig.load(from: configPath)
    : UIConfig()

if let style = argVal("--background-style"), ["solid", "frosted"].contains(style) { config.ui.popupBackgroundStyle = style }
if let raw = argVal("--background-opacity"), let percent = Int(raw) { config.ui.popupOpacityPercent = min(100, max(55, percent)) }

if args.contains("--deadline-notice") || args.contains("--preparation-notice") {
    config.toast.autoDismissSeconds=30
    config.toast.showCloseButton=true
}
if state == .entraRegistration { config.ui.popupWidth = min(900,max(420,config.ui.popupWidth)) }

let context = UIContext(config: config, state: state,
                        deferralCount: deferralCount, configPath: configPath)

if args.contains("--deadline-notice") {context.informationalToastMessage="The macOS update deadline has passed. PUSH will now attempt the configured update workflow. Please save your work. Dismissing this notice does not postpone enforcement."}
if args.contains("--preparation-notice") {context.informationalToastMessage="PUSH is downloading your required macOS update in the background. Installation has not started. You will see the next update step after preparation finishes."}
if let p = argVal("--download-progress") { context.downloadProgress = Double(p) ?? 0 }
if let s = argVal("--download-subtitle") { context.downloadSubtitle = s }
if let a = argVal("--disk-available")    { context.diskAvailableGB  = Double(a) ?? 8.5 }
if let r = argVal("--disk-required")     { context.diskRequiredGB   = Double(r) ?? 25.0 }
if let e = argVal("--error")             { context.errorMessage     = e }
context.isManualTest = args.contains("--manual-test")
if state == .updateRecovery {
    if let payload=argVal("--recovery-payload"),let notice=RecoveryNotice.decode(payload){context.recoveryNotice=notice}
    else if context.isManualTest {context.recoveryNotice=RecoveryNotice.preview()}
    else {Foundation.exit(PushExitCode.error.rawValue)}
}
if state == .entraRegistration {
    if let payload = argVal("--entra-payload"), let notice = EntraNotice.decode(payload) { context.entraNotice = notice }
    else if context.isManualTest { context.entraNotice = EntraNotice.preview(stage:Int(argVal("--entra-stage") ?? "1") ?? 1) }
    else { Foundation.exit(PushExitCode.error.rawValue) }
}
if state == .appUpdates {
    if let payload = argVal("--apps-payload"), let notices = AppUpdateNotice.decodePayload(payload) { context.appUpdates = notices }
    else if !context.isManualTest { Foundation.exit(PushExitCode.error.rawValue) }
}

if args.contains("--quick-restart")      { context.quickRestart     = true }
if args.contains("--forced")              { context.forcedInstall    = true }

// Uptime check args (used by rebootNudge / rebootForce states)
if let u = argVal("--uptime-days")          { context.uptimeDays         = Int(u) ?? 0 }
if let r = argVal("--deferrals-remaining")  { context.uptimeDeferralsRemaining = Int(r) ?? 0 }
if let t = argVal("--timer-seconds")        { context.uptimeTimerSeconds = Int(t) ?? 600 }

// MARK: - App

struct PushUIApp: App {
    @NSApplicationDelegateAdaptor(PushAppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(context)
                .background(WindowConfigurator(context: context))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

if state == .entraRegistration {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let presenter = EntraWindowPresenter()
    application.delegate = presenter
    withExtendedLifetime(presenter) { application.run() }
    Foundation.exit(PushExitCode.dismiss.rawValue)
} else {
    PushUIApp.main()
}

// MARK: - Root view

struct RootView: View {
    @EnvironmentObject var ctx: UIContext

    var body: some View {
        Group {
            switch ctx.state {
            case .updateRecovery: UpdateRecoveryView()
            case .toast:          ToastView()
            case .appUpdates:     AppUpdatesToast()
            case .entraRegistration: EntraRegistrationView()
            case .softNudge:      SoftNudgeView()
            case .hardBlock:      HardBlockView()
            case .preflightPower: PowerWaitView()
            case .preflightDisk:  DiskSpaceView()
            case .passwordPrompt: PasswordView()
            case .downloading:    DownloadView()
            case .installing:     InstallingView()
            case .rebooting:      RebootingView()
            case .compliant:      CompliantView()
            case .error:          ErrorView()
            case .rebootNudge:    RebootNudgeView()
            case .rebootForce:    RebootForceView()
            }
        }

    }
}


// MARK: - App Delegate — blocks termination during forced install

class PushAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let isForcedInstall = context.forcedInstall
            || context.state == .downloading
            || context.state == .installing
            || context.state == .hardBlock
            || context.state == .passwordPrompt
            || context.state == .preflightDisk
            || context.state == .preflightPower
            || context.state == .rebooting
            || context.state == .rebootForce
        if isForcedInstall && !context.isManualTest {
            NSLog("[PUSH-UI] Termination blocked — forced install in progress")
            return .terminateCancel
        }
        Foundation.exit(PushExitCode.dismiss.rawValue)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

private let appDelegate = PushAppDelegate()

// MARK: - Fullscreen frost overlay
// Covers every display at screenSaverWindow level with a blurred NSVisualEffectView.
// No Screen Recording permission needed — NSVisualEffectView samples the compositor
// directly, the same way Mission Control and Exposé blur the desktop.
// User cannot interact with any app behind it.

class FrostOverlayManager {
    static var windows: [NSWindow] = []

    static func show() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let w = NSWindow(
                contentRect: screen.frame,
                styleMask:   [.borderless, .fullSizeContentView],
                backing:     .buffered,
                defer:       false,
                screen:      screen
            )
            w.level                   = NSWindow.Level(rawValue:
                                            Int(CGWindowLevelForKey(.screenSaverWindow)))
            w.collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                         .stationary, .ignoresCycle]
            w.backgroundColor         = .clear
            w.isOpaque                = false
            w.ignoresMouseEvents      = false
            w.canHide                 = false
            w.hidesOnDeactivate       = false
            w.isReleasedWhenClosed    = false

            let vfx                   = NSVisualEffectView(frame: screen.frame)
            vfx.blendingMode          = .behindWindow
            vfx.state                 = .active
            vfx.material              = .fullScreenUI  // full-screen blur, same as Mission Control
            vfx.appearance            = nil  // follows system
            vfx.autoresizingMask      = [.width, .height]
            w.contentView             = vfx

            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    static func hide() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }
}

// MARK: - NSVisualEffectView background (frosted glass + proper event handling)
// Using NSVisualEffectView instead of window.backgroundColor = .clear fixes
// the click-through problem: transparent windows drop mouse events in empty
// areas, but NSVisualEffectView fills the space and receives events normally.

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state        = .active
        v.material     = .hudWindow
        v.appearance   = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Window configurator

private struct WindowConfigurator: NSViewRepresentable {
    let context: UIContext

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.alphaValue = 0
            configure(window)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private func configure(_ window: NSWindow) {
        let cfg   = self.context.config
        let state = self.context.state

        // Respect system appearance — light or dark mode
        // backgroundColor is set per-mode via the view's background
        window.appearance      = nil   // follows system
        window.backgroundColor = .clear
        window.isOpaque        = false
        window.hasShadow       = true
        window.level           = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if state == .toast || state == .appUpdates {
            window.styleMask       = [.borderless, .fullSizeContentView]
            window.appearance      = nil
            window.backgroundColor = .clear
            window.isOpaque        = false

            if let screen = NSScreen.main {
                let margin  = CGFloat(cfg.toast.screenMargin)
                let w       = CGFloat(cfg.toast.width)
                let visible = screen.visibleFrame

                // Let SwiftUI size the height by fitting to content, then reposition.
                // After initial layout, window.frame.height reflects actual content height.
                // We position bottom-anchored toasts from minY, top-anchored from maxY.
                window.setContentSize(CGSize(width: w, height: 1))

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let h = window.frame.height
                    let origin: CGPoint = {
                        switch cfg.toast.position {
                        case "topLeft":    return CGPoint(x: visible.minX + margin,
                                                          y: visible.maxY - h - margin)
                        case "topRight":   return CGPoint(x: visible.maxX - w - margin,
                                                          y: visible.maxY - h - margin)
                        case "bottomLeft": return CGPoint(x: visible.minX + margin,
                                                          y: visible.minY + margin)
                        default:           return CGPoint(x: visible.maxX - w - margin,
                                                          y: visible.minY + margin)
                        }
                    }()
                    window.setFrameOrigin(origin)
                }
            }
        } else {
            window.styleMask                   = [.borderless, .fullSizeContentView]
            window.isMovableByWindowBackground = true
            window.title = state.windowTitle

            // Fullscreen frost mode for hardBlock
            if state == .hardBlock && self.context.config.ui.hardBlockFullscreen {
                // Show blurred overlay covering all displays
                FrostOverlayManager.show()
                // Place popup above the overlay — screenSaverWindow + 1
                window.level = NSWindow.Level(rawValue:
                    Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
                // Lock it to all spaces, prevent hiding
                window.collectionBehavior  = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                              .stationary, .ignoresCycle]
                window.canHide             = false
                window.hidesOnDeactivate   = false
            }

            window.center()
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        }

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25) {
            if let path = argVal("--ready-file"), window.isVisible, window.alphaValue > 0 {
                try? "ready\n".write(toFile:path,atomically:true,encoding:.utf8)
            }
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isForcedInstall = context.forcedInstall
                || context.state == .downloading
                || context.state == .installing
                || context.state == .hardBlock
                || context.state == .passwordPrompt
                || context.state == .preflightDisk
                || context.state == .preflightPower
                || context.state == .rebooting
            || context.state == .rebootForce

            // During forced install — block all quit/hide/close shortcuts
            if isForcedInstall && !context.isManualTest && event.modifierFlags.contains(.command) {
                switch event.keyCode {
                case 12: // Q — quit
                    NSLog("[PUSH-UI] Cmd+Q blocked during forced install")
                    return nil
                case 13: // W — close window
                    NSLog("[PUSH-UI] Cmd+W blocked during forced install")
                    return nil
                case 4:  // H — hide
                    NSLog("[PUSH-UI] Cmd+H blocked during forced install")
                    return nil
                case 34: // M — minimize
                    NSLog("[PUSH-UI] Cmd+M blocked during forced install")
                    return nil
                default:
                    break
                }
            }

            // Escape only exits when NOT in a forced/active install state
            if event.keyCode == 53 && (!isForcedInstall || context.isManualTest) {
                Foundation.exit(PushExitCode.dismiss.rawValue)
            }
            return event
        }

        // Also override applicationShouldTerminate to block Cmd+Q at app level
        NSApp.disableRelaunchOnLogin()
    }
}


// Native agent-window presentation avoids relying on WindowGroup auto-opening an LSUIElement app.
private final class EntraPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
private final class EntraWindowPresenter: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSWindow?
    private var keyMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingView(rootView:EntraRegistrationView().environmentObject(context))
        let width = CGFloat(context.config.ui.popupWidth)
        let window = EntraPanel(contentRect:NSRect(x:0,y:0,width:width,height:640),styleMask:[.borderless,.fullSizeContentView],backing:.buffered,defer:false)
        panel = window
        window.delegate = self
        window.title = UIState.entraRegistration.windowTitle
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.isOpaque = false; window.backgroundColor = .clear
        window.hasShadow = true; window.alphaValue = 1
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        if size.height.isFinite && size.height > 1 {
            window.setContentSize(NSSize(width:width,height:size.height))
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps:true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { event in
            if event.keyCode == 53 || (event.modifierFlags.contains(.command) && [12,13].contains(event.keyCode)) {
                Foundation.exit(PushExitCode.dismiss.rawValue)
            }
            return event
        }
        DispatchQueue.main.async {
            window.contentView?.layoutSubtreeIfNeeded()
            window.alphaValue = 1
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            if let path = argVal("--ready-file"), window.isVisible {
                try? "ready\n".write(toFile:path,atomically:true,encoding:.utf8)
            }
        }
    }
    func windowWillClose(_ notification: Notification) { Foundation.exit(PushExitCode.dismiss.rawValue) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Foundation.exit(PushExitCode.dismiss.rawValue)
    }
}
