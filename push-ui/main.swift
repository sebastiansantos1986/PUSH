// main.swift — push-ui entry point
// Transparent window enables frosted glass (.regularMaterial) throughout.

import SwiftUI
import AppKit

// MARK: - Argument parsing

let args = CommandLine.arguments

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
let configPath    = argVal("--config")   ?? "/Library/Management/PUSH/config.yaml"
let deferralStr   = argVal("--deferrals") ?? "0"
let deferralCount = Int(deferralStr) ?? 0

let state  = UIState.from(stateStr)
let config = FileManager.default.fileExists(atPath: configPath)
    ? UIConfig.load(from: configPath)
    : UIConfig()

let context = UIContext(config: config, state: state,
                        deferralCount: deferralCount, configPath: configPath)

if let p = argVal("--download-progress") { context.downloadProgress = Double(p) ?? 0 }
if let s = argVal("--download-subtitle") { context.downloadSubtitle = s }
if let a = argVal("--disk-available")    { context.diskAvailableGB  = Double(a) ?? 8.5 }
if let r = argVal("--disk-required")     { context.diskRequiredGB   = Double(r) ?? 25.0 }
if let e = argVal("--error")             { context.errorMessage     = e }
if args.contains("--quick-restart")      { context.quickRestart     = true }

// MARK: - App

struct PushUIApp: App {
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

PushUIApp.main()

// MARK: - Root view

struct RootView: View {
    @EnvironmentObject var ctx: UIContext

    var body: some View {
        Group {
            switch ctx.state {
            case .toast:          ToastView()
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
            }
        }

    }
}


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

        if state == .toast {
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

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Foundation.exit(PushExitCode.dismiss.rawValue)
            }
            return event
        }
    }
}
