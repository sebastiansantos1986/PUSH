// PopupViews.swift — All PUSH popup states

import SwiftUI
import AppKit
import IOKit.ps

// MARK: ── Soft Nudge ──────────────────────────────────────────────────────────

struct SoftNudgeView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var showingReasonSheet = false
    @State private var selectedReason     = ""
    private var cfg:    UIConfig { ctx.config }
    private var accent: Color    { cfg.accentColor }

    var body: some View {
        ZStack {
            PopupCard(width: CGFloat(cfg.ui.popupWidth)) {
                PopupHeader(config: cfg,
                            subtitle: cfg.isMajor ? "Major OS Upgrade Required"
                                                  : "Security Update Available")
                PushDivider()
                bodyContent
                PushDivider()
                actionBar
            }

            // Deferral reason sheet overlay
            if showingReasonSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showingReasonSheet = false }
                DeferralReasonSheet(config: cfg) { reason in
                    // Write reason to temp file so CLI can pick it up
                    try? reason.write(toFile: "/tmp/push-deferral-reason",
                                      atomically: true, encoding: .utf8)
                    ctx.exit(.defer_)
                } onCancel: {
                    showingReasonSheet = false
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingReasonSheet)
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            RichMessage(
                text:     cfg.isMajor ? cfg.ui.majorMessage : cfg.ui.minorMessage,
                fontSize: 13,
                color:    Color(NSColor.secondaryLabelColor)
            )
            VersionRow(config: cfg)
            StatusBar(config: cfg, deferralsLeft: ctx.deferralsLeft)
            ITContactStrip(config: cfg)
        }
        .padding(20)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if ctx.deferralsLeft > 0 {
                Button(cfg.ui.deferButtonLabel) {
                    if cfg.ui.requireDeferralReason {
                        showingReasonSheet = true
                    } else {
                        ctx.exit(.defer_)
                    }
                }
                .buttonStyle(PushSecondaryButtonStyle())
            } else {
                Text("No deferrals remaining")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
            }
            Spacer()
            Button(cfg.isMajor
                   ? cfg.ui.installMajorButtonLabel
                   : cfg.ui.installMinorButtonLabel) { ctx.exit(.install) }
                .buttonStyle(PushPrimaryButtonStyle(color: accent))
                .keyboardShortcut(.return)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: ── Hard Block ──────────────────────────────────────────────────────────

struct HardBlockView: View {
    @EnvironmentObject var ctx: UIContext
    private var cfg:        UIConfig { ctx.config }
    private var accent:     Color    { cfg.accentColor }
    private var fullscreen: Bool     { cfg.ui.hardBlockFullscreen }

    var body: some View {
        PopupCard(width: CGFloat(cfg.ui.popupWidth),
                  showTrafficLights: !fullscreen) {  // no close button in fullscreen
            PopupHeader(config: cfg,
                        subtitle: cfg.isMajor ? "Major OS Upgrade Required"
                                              : "Security Update Required",
                        urgent: true)
            PushDivider()
            bodyContent
            PushDivider()
            actionBar
        }
    }

    private var bodyContent: some View {
        VStack(spacing: 14) {
            RichMessage(
                text:     cfg.ui.deadlineMessage,
                fontSize: 13,
                color:    Color.primary.opacity(0.75)
            )
            .multilineTextAlignment(.center)
            VersionRow(config: cfg)
            UrgentBanner(text: "Immediate installation required — no deferrals available")
            ITContactStrip(config: cfg)
        }
        .padding(20)
    }

    private var actionBar: some View {
        PrimaryActionButton(
            label:  cfg.isMajor ? cfg.ui.installMajorButtonLabel
                                 : cfg.ui.installMinorButtonLabel,
            icon:   "arrow.down.circle.fill",
            color:  accent
        ) { ctx.exit(.install) }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: ── Toast ───────────────────────────────────────────────────────────────

struct ToastView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var visible:      Bool   = false
    @State private var hovering:     Bool   = false
    @State private var secondsLeft:  Int    = 60

    private var toast:  UIConfig.ToastCfg { ctx.config.toast }
    private var accent: Color             { ctx.config.accentColor }
    private let tick = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var slideOffset: CGSize {
        switch toast.position {
        case "topLeft", "bottomLeft": return CGSize(width: -50, height: 0)
        default:                      return CGSize(width:  50, height: 0)
        }
    }

    // Get first name of logged-in user for personalized greeting
    private var firstName: String {
        let fullName = NSFullUserName()
        return fullName.components(separatedBy: " ").first ?? fullName
    }

    // Title: "macOS Tahoe 26.4 Available"
    private var toastTitle: String {
        "\(ctx.config.friendlyTargetVersion) Available"
    }

    // Subtitle under title
    private var toastSubtitle: String {
        ctx.config.isMajor ? "Major Upgrade for Your Mac" : "Recommended Update for Your Mac"
    }

    // Body message — uses toast.message from config if set, otherwise builds default
    private var bodyText: String {
        // If admin has set a custom toast message in config, use it
        if let custom = ctx.config.toast.message, !custom.isEmpty {
            return custom.resolvedNewlines
        }
        // Default personalized message
        let name = firstName.isEmpty ? "" : "Hello \(firstName)! "
        let greeting = name + "We have great news.\n\n"
        let update = ctx.config.isMajor
            ? "\(ctx.config.friendlyTargetVersion) is now available for your Mac. This major upgrade includes:"
            : "A new security update is available for your Mac. This update includes:"
        let bullets = "\n\n• Enhanced security and privacy features\n• Improved performance and stability\n• Critical security patches and updates"
        let footer = "\n\nThe installation will take approximately 30–45 minutes and your Mac will restart automatically. All your files and settings will be preserved.\n\nWould you like to install now or schedule for later?"
        return greeting + update + bullets + footer
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ─────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 12) {
                AppIconView(config: ctx.config, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(toastTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(toastSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if toast.showCloseButton {
                    Button { ctx.exit(.dismiss) } label: {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 24, height: 24)
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            PushDivider()

            // ── Body — no lineLimit so full message always shows ───────────
            Text(bodyText)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            PushDivider()

            // ── Action bar ─────────────────────────────────────────────────
            HStack(spacing: 10) {
                // Countdown timer bottom left
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundStyle(secondsLeft < 15 ? Color.red : Color.orange)
                    Text("\(secondsLeft)s")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(secondsLeft < 15 ? Color.red : Color.orange)
                }
                .opacity(hovering ? 0.5 : 1.0)

                Spacer()

                if ctx.deferralsLeft > 0 && toast.showDeferButton {
                    Button { ctx.exit(.defer_) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .font(.system(size: 11))
                            Text(toast.deferButtonLabel)
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(PushToastSecondaryStyle())
                }

                Button {
                    // Write action file so the CLI knows user clicked Install from toast
                    try? "install".write(toFile: "/tmp/push-toast-action",
                                         atomically: true, encoding: .utf8)
                    ctx.exit(.install)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13))
                        Text(toast.installButtonLabel)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(PushToastPrimaryStyle(color: accent))
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: CGFloat(toast.width))
        .background(
            RoundedRectangle(cornerRadius: CGFloat(toast.cornerRadius))
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(toast.cornerRadius))
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 20, x: 0, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(toast.cornerRadius)))
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : slideOffset.width)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { visible = true }
            if !toast.soundName.isEmpty { NSSound(named: toast.soundName)?.play() }
        }
        .onReceive(tick) { _ in
            guard !hovering else { return }
            if secondsLeft > 0 { secondsLeft -= 1 }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: ── Download Progress ───────────────────────────────────────────────────

struct DownloadView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var liveProgress: Double = 0
    @State private var liveSubtitle: String = "Preparing download…"
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private var accent: Color { ctx.config.accentColor }

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config, subtitle: "Download in Progress")
            PushDivider()
            VStack(spacing: 18) {
                VStack(spacing: 5) {
                    Text("Downloading \(ctx.config.friendlyTargetVersion)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(liveSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent)
                                .frame(width: geo.size.width * liveProgress)
                                .animation(.linear(duration: 1.5), value: liveProgress)
                        }
                    }
                    .frame(height: 6)
                    HStack {
                        Text("\(Int(liveProgress * 100))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent)
                        Spacer()
                        Text(ctx.config.friendlyTargetVersion)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                }

                Text("Please keep your Mac plugged in · Do not shut down or close the lid")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .onAppear {
            liveProgress = ctx.downloadProgress
            liveSubtitle = ctx.downloadSubtitle
        }
        .onReceive(timer) { _ in
            if let raw = try? String(contentsOfFile: "/tmp/push-download-progress",
                                     encoding: .utf8) {
                let parts = raw.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if let first = parts.first, let p = Double(first) {
                    liveProgress = min(1.0, p)
                }
                if parts.count > 1 && !parts[1].isEmpty { liveSubtitle = parts[1] }
            }
        }
    }
}

// MARK: ── Installing ──────────────────────────────────────────────────────────

struct InstallingView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var dotCount    = 1
    @State private var progress    = 0.0      // 0.0–1.0
    @State private var subtitle    = ""
    @State private var pulseOffset = 0.0      // animated waiting bar position
    private let ticker = Timer.publish(every: 0.7,  on: .main, in: .common).autoconnect()
    private let poller = Timer.publish(every: 1.5,  on: .main, in: .common).autoconnect()
    private let pulser = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    // Both native (quick-restart) and startosinstall paths write to this file
    private let progressFile = "/tmp/push-install-progress"

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config, subtitle: "Installation in Progress")
            PushDivider()
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Installing\(String(repeating: ".", count: dotCount))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    if ctx.quickRestart || !subtitle.isEmpty {
                        Text(subtitle.isEmpty ? "Preparing installation…" : subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                            .multilineTextAlignment(.center)
                            .animation(.easeInOut, value: subtitle)
                    } else {
                        RichMessage(text: ctx.config.ui.installingMessage,
                                    fontSize: 13, color: Color(NSColor.secondaryLabelColor))
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07))
                        if progress > 0.009 {
                            RoundedRectangle(cornerRadius: 3).fill(Color.green)
                                .frame(width: geo.size.width * progress)
                                .animation(.linear(duration: 1.5), value: progress)
                        } else {
                            let pulseWidth = geo.size.width * 0.25
                            let maxOffset  = geo.size.width - pulseWidth
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green.opacity(0.6))
                                .frame(width: pulseWidth)
                                .offset(x: pulseOffset * maxOffset)
                        }
                    }
                }
                .frame(height: 6)
                Text("Do not shut down your Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }
            .padding(24)
        }
        .onReceive(ticker) { _ in dotCount = dotCount % 3 + 1 }
        .onReceive(poller) { _ in
            // Poll progress for both native restart and startosinstall paths
            pollProgress()
        }
        .onReceive(pulser) { _ in
            guard progress <= 0.009 else { return }
            // Animate pulse bar back and forth while waiting for real data
            pulseOffset += 0.015
            if pulseOffset > 1.0 { pulseOffset = 0.0 }
        }
    }

    private func pollProgress() {
        guard let raw = try? String(contentsOfFile: progressFile, encoding: .utf8) else { return }
        let parts = raw.components(separatedBy: "\n")
        if let pct = Double(parts[0].trimmingCharacters(in: .whitespaces)) {
            progress = min(1.0, max(0.0, pct))
        }
        if parts.count > 1 {
            subtitle = parts[1].trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: ── Rebooting ───────────────────────────────────────────────────────────

struct RebootingView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var secondsLeft = 60
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var accent: Color { ctx.config.accentColor }

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config, subtitle: "Restart Required")
            PushDivider()
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("\(secondsLeft)")
                        .font(.system(size: 52, weight: .thin, design: .monospaced))
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                    Text("seconds until automatic restart")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }

                Text("Your Mac will restart to complete the update.\nSave any open work now.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                CountdownDrainBar(progress: Double(secondsLeft) / 60.0, color: accent)
                    .padding(.horizontal, 4)

                PrimaryActionButton(label: "Restart Now",
                                    icon: "restart.circle.fill",
                                    color: accent) { ctx.exit(.install) }
            }
            .padding(24)
        }
        .onReceive(timer) { _ in
            if secondsLeft > 0 { secondsLeft -= 1 }
            else { ctx.exit(.install) }
        }
    }
}

// MARK: ── Compliant ───────────────────────────────────────────────────────────

struct CompliantView: View {
    @EnvironmentObject var ctx: UIContext

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config, subtitle: "Up to Date")
            PushDivider()
            VStack(spacing: 14) {
                Text("Your Mac is up to date")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                RichMessage(text: ctx.config.ui.alreadyUpToDateMessage,
                            fontSize: 13, color: Color(NSColor.secondaryLabelColor))
                VersionRow(config: ctx.config)
                Button("Done") { ctx.exit(.dismiss) }
                    .buttonStyle(PushSecondaryButtonStyle())
            }
            .padding(24)
        }
    }
}

// MARK: ── Error ───────────────────────────────────────────────────────────────

struct ErrorView: View {
    @EnvironmentObject var ctx: UIContext

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config, subtitle: "Something Went Wrong", urgent: true)
            PushDivider()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.red)
                Text(ctx.errorMessage.resolvedNewlines)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                ITContactStrip(config: ctx.config)
                Button("Dismiss") { ctx.exit(.dismiss) }
                    .buttonStyle(PushSecondaryButtonStyle())
            }
            .padding(24)
        }
    }
}

// MARK: ── Power Preflight ─────────────────────────────────────────────────────
// Checks power every 2s. Times out after powerCheckTimeoutMinutes.
// Exit 0 = power connected. Exit 4 = timed out. Exit 2 = user skipped.

struct PowerWaitView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var secondsLeft:  Int    = 0
    @State private var totalSeconds: Int    = 300
    @State private var statusText:   String = "Waiting for power connection…"
    @State private var powerFound:   Bool   = false

    private let tick = Timer.publish(every: 1,   on: .main, in: .common).autoconnect()
    private let poll = Timer.publish(every: 2,   on: .main, in: .common).autoconnect()

    private var progress: Double {
        totalSeconds > 0 ? Double(secondsLeft) / Double(totalSeconds) : 0
    }

    private var timerDisplay: String {
        let m = secondsLeft / 60
        let s = secondsLeft % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config,
                        subtitle: powerFound ? "AC power connected" : "Waiting for AC power…")
            PushDivider()
            VStack(spacing: 20) {
                Image(systemName: powerFound ? "bolt.circle.fill" : "bolt.fill")
                    .font(.system(size: 32))
                    .foregroundColor(powerFound ? Color.green : Color.orange)
                    .animation(.easeInOut(duration: 0.3), value: powerFound)

                Text((powerFound
                     ? "Power detected — continuing installation…"
                     : ctx.config.ui.preflightPowerMessage.isEmpty
                         ? "Please connect your Mac to power before installing the update."
                         : ctx.config.ui.preflightPowerMessage).resolvedNewlines)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                // Progress bars
                VStack(spacing: 8) {
                    HStack {
                        Text(statusText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(timerDisplay)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(secondsLeft < 60 ? Color.red : Color.orange)
                    }

                    // Indeterminate shimmer (active search)
                    IndeterminateBar(color: powerFound ? Color.green : Color.orange)

                    // Countdown drain
                    CountdownDrainBar(
                        progress: progress,
                        color: secondsLeft < 60 ? Color.red.opacity(0.5)
                                                : Color.orange.opacity(0.35)
                    )
                }

                // Steps
                VStack(spacing: 8) {
                    tipRow(icon: "powerplug.fill",
                           title: "Connect your charger",
                           detail: "Plug in your MagSafe or USB-C power adapter")
                    tipRow(icon: "bolt.fill",
                           title: "Keep it connected",
                           detail: "Installation begins automatically once power is detected")
                }
            }
            .padding(20)

            PushDivider()
            HStack {
                Spacer()
                Button("Skip for now") { ctx.exit(.dismiss) }
                    .buttonStyle(PushSecondaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            totalSeconds = ctx.config.preflight.powerCheckTimeoutMinutes * 60
            secondsLeft  = totalSeconds
            checkPower()
        }
        .onReceive(tick) { _ in
            guard !powerFound else { return }
            if secondsLeft > 0 {
                secondsLeft -= 1
            } else {
                ctx.exit(.powerTimeout)
            }
        }
        .onReceive(poll) { _ in
            guard !powerFound else { return }
            checkPower()
        }
    }

    private func tipRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
        .cornerRadius(10)
    }

    private func checkPower() {
        guard isOnACPower() else { return }
        powerFound   = true
        statusText   = "Power detected — continuing…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            ctx.exit(.install)
        }
    }

    private func isOnACPower() -> Bool {
        let snapshot  = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sourceList = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sourceList {
            if let info  = IOPSGetPowerSourceDescription(snapshot, source)?
                               .takeUnretainedValue() as? [String: Any],
               let state = info[kIOPSPowerSourceStateKey] as? String {
                return state == kIOPSACPowerValue
            }
        }
        return false
    }
}

// MARK: ── Disk Space Preflight ────────────────────────────────────────────────

struct DiskSpaceView: View {
    @EnvironmentObject var ctx: UIContext
    private var accent: Color { ctx.config.accentColor }

    private var neededGB:  Double { ctx.diskRequiredGB }
    private var availGB:   Double { ctx.diskAvailableGB }
    private var shortfall: Double { max(0, neededGB - availGB) }
    private var gaugeProgress: Double { min(1.0, availGB / neededGB) }

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config,
                        subtitle: String(format: "%.1f GB more needed", shortfall),
                        urgent: true)
            PushDivider()
            VStack(spacing: 14) {
                // Storage gauge
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available storage")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .kerning(0.5)
                        .textCase(.uppercase)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.07))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: geo.size.width * gaugeProgress)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text(String(format: "%.1f GB available", availGB))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.red)
                        Spacer()
                        Text(String(format: "%.0f GB needed", neededGB))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
                .cornerRadius(10)

                // Tips
                VStack(spacing: 0) {
                    tipRow(symbol: "trash.fill",        color: Color.red,
                           text: "Empty the Trash")
                    PushDivider()
                    tipRow(symbol: "square.grid.2x2",   color: Color.orange,
                           text: "Remove unused apps")
                    PushDivider()
                    tipRow(symbol: "folder.fill",        color: Color.blue,
                           text: "Clear your Downloads folder")
                    PushDivider()
                    tipRow(symbol: "icloud.fill",        color: Color.teal,
                           text: "Move files to iCloud Drive")
                }
                .background(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
                .cornerRadius(10)

                ITContactStrip(config: ctx.config)
            }
            .padding(20)

            PushDivider()

            // Footer buttons
            HStack(spacing: 10) {
                Button("Contact IT") { ctx.exit(.dismiss) }
                    .buttonStyle(PushSecondaryButtonStyle())
                Spacer()
                Button(action: openStorageSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Open Storage Settings")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(PushPrimaryButtonStyle(color: accent))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func tipRow(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private func openStorageSettings() {
        if !ctx.config.preflight.diskSpaceLearnMoreURL.isEmpty,
           let url = URL(string: ctx.config.preflight.diskSpaceLearnMoreURL) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: ── Password Prompt ─────────────────────────────────────────────────────

struct PasswordView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var password = ""
    @State private var shaking  = false
    private var config: UIConfig { ctx.config }

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config, subtitle: "Authentication Required")
            PushDivider()
            VStack(spacing: 16) {
                Text(config.ui.passwordPromptMessage.isEmpty
                         ? "Your Mac requires your password to install the update."
                         : config.ui.passwordPromptMessage.resolvedNewlines)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.center)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                    .offset(x: shaking ? -8 : 0)
                    .animation(shaking
                        ? .easeInOut(duration: 0.05).repeatCount(6, autoreverses: true)
                        : .default, value: shaking)
                HStack(spacing: 10) {
                    Button("Cancel") { ctx.exit(.dismiss) }
                        .buttonStyle(PushSecondaryButtonStyle())
                    Button("Continue") { submit() }
                        .buttonStyle(PushPrimaryButtonStyle(color: ctx.config.accentColor))
                        .disabled(password.isEmpty)
                }
            }
            .padding(24)
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        if (try? password.write(toFile: "/tmp/push-password",
                                atomically: true, encoding: .utf8)) != nil {
            ctx.exit(.install)
        } else {
            password = ""; shaking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shaking = false }
        }
    }
}
