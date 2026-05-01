// PopupViews.swift — All PUSH popup states

import SwiftUI
import AppKit
import IOKit.ps

// MARK: ── Soft Nudge ──────────────────────────────────────────────────────────

struct SoftNudgeView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var showingReasonSheet = false
    @State private var showingDatePicker  = false
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

            // Date picker sheet overlay (user picks specific time to be reminded)
            if showingDatePicker {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showingDatePicker = false }
                DatePickerSheet(config: cfg,
                                deadline: cfg.deadlineDate ?? Date().addingTimeInterval(7 * 86400)) { chosenDate in
                    // Write chosen date to temp file so CLI can pick it up
                    let iso = ISO8601DateFormatter().string(from: chosenDate)
                    try? iso.write(toFile: "/tmp/push-scheduled-until",
                                   atomically: true, encoding: .utf8)
                    ctx.exit(.scheduledDefer)
                } onCancel: {
                    showingDatePicker = false
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingReasonSheet)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingDatePicker)
    }

    // Days remaining for urgency-aware messaging
    private var daysRemaining: Int {
        guard let deadline = cfg.deadlineDate else { return 99 }
        let diff = Calendar.current.dateComponents([.day], from: Date(), to: deadline)
        return max(0, diff.day ?? 0)
    }

    // Smart message — uses config message if set, otherwise builds from days remaining
    private var nudgeMessage: String {
        let customMsg = cfg.isMajor ? cfg.ui.majorMessage : cfg.ui.minorMessage
        if !customMsg.isEmpty { return customMsg }

        let days    = daysRemaining
        let isMajor = cfg.isMajor
        let version = cfg.friendlyTargetVersion
        let time    = isMajor ? "30–45 minutes" : "15–20 minutes"
        let kind    = isMajor ? "upgrade" : "update"

        if isMajor {
            return "A major macOS upgrade to \(version) is required by IT to keep your Mac secure and supported.\n\nWhat to expect:\n- The upgrade takes approximately \(time)\n- Your files, apps, and settings will be preserved\n- Your Mac will restart automatically when ready\n\nYou have \(days) day\(days == 1 ? "" : "s") remaining before this upgrade begins automatically.\n\nPlease save your work and begin when convenient."
        } else {
            return "A required security update (\(version)) is available for your Mac and must be installed per IT policy.\n\nWhat this update includes:\n- Critical security patches\n- Bug fixes and stability improvements\n- Performance enhancements\n\nYou have \(days) day\(days == 1 ? "" : "s") remaining before this update is installed automatically.\n\nPlease install at your earliest convenience."
        }
    }

    private var bodyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            RichMessage(
                text:     nudgeMessage,
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

                // Schedule button — user picks specific date/time, no deferral cost
                Button("Schedule…") { showingDatePicker = true }
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
                        subtitle: ctx.forcedInstall
                            ? "Automatic Installation in Progress"
                            : cfg.isMajor ? "Major OS Upgrade Required"
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
            if ctx.forcedInstall {
                // ── Forced install message — config overrides smart default ─
                let forcedMsg = cfg.ui.forcedInstallMessage.isEmpty
                    ? "Your Mac is overdue for a required macOS \(cfg.isMajor ? "upgrade" : "update"). The installation is beginning automatically — no action is needed from you."
                    : cfg.ui.forcedInstallMessage

                // Default notice bullets — can be overridden via config
                let defaultNotice = [
                    "Save any open work now",
                    "This window cannot be closed",
                    "If the window disappears, the update continues in the background",
                    "Your Mac will restart automatically when ready",
                    "The process takes approximately \(cfg.isMajor ? "30–45" : "15–20") minutes"
                ]
                // If admin set custom notice, split by \n into bullets
                let noticeItems: [String] = cfg.ui.forcedInstallNotice.isEmpty
                    ? defaultNotice
                    : cfg.ui.forcedInstallNotice
                        .resolvedNewlines
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.exclamationmark.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.orange)
                        Text("Automatic Update in Progress")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }

                    Text(forcedMsg.resolvedNewlines)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)

                    // Info box
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.blue)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("What to expect")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.primary)
                            ForEach(noticeItems, id: \.self) { item in
                                Text("• \(item)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.primary.opacity(0.75))
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                }
            } else {
                // ── Normal hard block — user must click ────────────────────
                let msg = cfg.ui.deadlineMessage.isEmpty
                    ? "Your Mac is overdue for a required macOS \(cfg.isMajor ? "upgrade" : "update").\n\nYour IT deadline has passed and no more deferrals are available. Please save your open work and install now.\n\nThe \(cfg.isMajor ? "upgrade" : "update") takes approximately \(cfg.isMajor ? "30–45" : "15–20") minutes and your Mac will restart automatically."
                    : cfg.ui.deadlineMessage
                RichMessage(text: msg, fontSize: 13, color: Color.primary.opacity(0.75))
                    .multilineTextAlignment(.center)
                UrgentBanner(text: "Deadline passed — immediate installation required")
            }
            VersionRow(config: cfg)
            ITContactStrip(config: cfg)
        }
        .padding(20)
    }

    private var actionBar: some View {
        Group {
            if ctx.forcedInstall {
                // During forced install show a non-interactive indicator
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Installing automatically…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
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

    // Subtitle under title — escalates as deadline approaches
    private var toastSubtitle: String { toastSubtitleDynamic }

    // Days remaining until deadline — used for urgency tier
    private var daysRemaining: Int {
        guard let deadline = ctx.config.deadlineDate else { return 99 }
        let diff = Calendar.current.dateComponents([.day], from: Date(), to: deadline)
        return max(0, diff.day ?? 0)
    }

    // Body message — uses toast.message from config if set, otherwise builds tier-based default
    private var bodyText: String {
        // Admin custom message overrides everything
        if let custom = ctx.config.toast.message, !custom.isEmpty {
            return custom.resolvedNewlines
        }

        let name    = firstName.isEmpty ? "there" : firstName
        let days    = daysRemaining
        let isMajor = ctx.config.isMajor
        let version = ctx.config.friendlyTargetVersion
        let kind    = isMajor ? "upgrade" : "update"
        let time    = isMajor ? "30–45 minutes" : "15–20 minutes"

        // ── 🔴 Final Warning — deadline is today or tomorrow ─────────────────
        if days <= 1 {
            let urgency = days == 0
                ? "⚠️ Your macOS \(kind) will install automatically today."
                : "⚠️ Your macOS \(kind) deadline is tomorrow."
            return """
Hello \(name),

\(urgency)

Once the deadline passes, the installation will begin automatically without further notice. Please save any open work now.

⏰ Time remaining: \(days == 0 ? "Less than 24 hours" : "1 day")
🔒 Required by IT Security Policy
🔄 Your Mac will restart automatically when the update begins
"""
        }

        // ── 🟡 Urgent — 2 days left ──────────────────────────────────────────
        if days <= 2 {
            return """
Hello \(name),

Your macOS \(kind) deadline is approaching. \(version) is required by IT and must be installed within the next \(days) day\(days == 1 ? "" : "s").

After the deadline, the installation will begin automatically.

⏰ \(days) day\(days == 1 ? "" : "s") remaining
🔒 Required by IT — no further deferrals after deadline
⏱️ Installation takes approximately \(time)

Please install at your earliest convenience to avoid interruption.
"""
        }

        // ── 🟢 Normal — plenty of time ───────────────────────────────────────
        let updateLine = isMajor
            ? "\(version) is a major macOS upgrade required by IT to keep your Mac secure and supported."
            : "A required security update (\(version)) is available for your Mac."

        return """
Hello \(name),

\(updateLine)

What to expect:
• Installation takes approximately \(time)
• Your files, apps, and settings will be preserved
• Your Mac will restart automatically when ready

⏰ \(days) days remaining before automatic installation
🔒 Required by IT Security Policy

Please save your work and install when convenient.
"""
    }

    // Toast subtitle changes based on urgency
    private var toastSubtitleDynamic: String {
        let days = daysRemaining
        if days <= 1 { return "⚠️ Final Warning — Install Today" }
        if days <= 2 { return "Deadline Approaching — \(days) Day\(days == 1 ? "" : "s") Left" }
        return ctx.config.isMajor ? "Major Upgrade Required" : "Security Update Required"
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
                        let msg = ctx.config.ui.installingMessage.isEmpty
                            ? "macOS is being installed on your Mac.\n\nThis process takes approximately 30–45 minutes. Your Mac will restart automatically when the installation is complete.\n\nPlease keep your Mac powered on and plugged in."
                            : ctx.config.ui.installingMessage
                        RichMessage(text: msg, fontSize: 13,
                                    color: Color(NSColor.secondaryLabelColor))
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
                VStack(spacing: 4) {
                    Text("⚠️  Do not shut down or unplug your Mac during installation")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.orange.opacity(0.9))
                        .multilineTextAlignment(.center)
                    Text("Your Mac will restart automatically when ready")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }
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
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.green)
                Text("Your Mac is Up to Date")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                RichMessage(
                    text: ctx.config.ui.alreadyUpToDateMessage.isEmpty
                        ? "Your Mac is running the required version of macOS. No action is needed — you are fully compliant with your organization\'s IT policy."
                        : ctx.config.ui.alreadyUpToDateMessage,
                    fontSize: 13,
                    color: Color(NSColor.secondaryLabelColor)
                )
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
                VStack(spacing: 8) {
                    Text(ctx.errorMessage.resolvedNewlines)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                    Text("The update will be retried automatically on the next check. If this problem persists, please contact IT support.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
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
                         ? "Please connect your Mac to your power adapter before the update begins.\n\nThe installation requires a stable power source to prevent interruption during the process."
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

                // Explanation
                Text("Your Mac needs \(String(format: "%.1f", shortfall)) GB more free space before the update can begin. Free up space using the suggestions below — the update will resume automatically once enough storage is available.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)

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
    @State private var password    = ""
    @State private var shaking     = false
    @State private var validating  = false
    @State private var errorMsg    = ""
    private var config: UIConfig { ctx.config }

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config, subtitle: "Authentication Required")
            PushDivider()
            VStack(spacing: 16) {
                Text(config.ui.passwordPromptMessage.isEmpty
                         ? "Enter the password for \(localAccount.isEmpty ? "your account" : "\\(localAccount)") to install the update.\n\nYour password will be saved securely in your login keychain so future updates can install automatically."
                         : config.ui.passwordPromptMessage.resolvedNewlines)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submit() }
                        .disabled(validating)
                        .offset(x: shaking ? -8 : 0)
                        .animation(shaking
                            ? .easeInOut(duration: 0.05).repeatCount(6, autoreverses: true)
                            : .default, value: shaking)

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.red)
                            .transition(.opacity)
                    }
                }

                HStack(spacing: 10) {
                    if !ctx.forcedInstall {
                        Button("Cancel") { ctx.exit(.dismiss) }
                            .buttonStyle(PushSecondaryButtonStyle())
                    }
                    Button(validating ? "Verifying…" : "Continue") { submit() }
                        .buttonStyle(PushPrimaryButtonStyle(color: ctx.config.accentColor))
                        .disabled(password.isEmpty || validating)
                }
            }
            .padding(24)
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        validating = true
        errorMsg   = ""

        // Validate password against the local account using dscl
        let account = localAccount
        let pwd     = password

        DispatchQueue.global(qos: .userInitiated).async {
            let valid = validatePassword(account: account, password: pwd)
            DispatchQueue.main.async {
                validating = false
                if valid {
                    // Save to user's login keychain for future automatic installs.
                    // This is the disclosed behavior per the prompt text. Failure
                    // here is logged but doesn't block the install.
                    saveUserPasswordToLoginKeychain(account: account, password: pwd)

                    // Write to temp file and proceed
                    if (try? pwd.write(toFile: "/tmp/push-password",
                                       atomically: true, encoding: .utf8)) != nil {
                        ctx.exit(.install)
                    }
                } else {
                    // Wrong password — shake field and show error
                    password = ""
                    errorMsg = "Incorrect password. Please try again."
                    shaking  = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shaking = false }
                }
            }
        }
    }

    /// Get the account to validate against.
    /// Priority: console user (logged-in user) → localAccount from config → empty (no validation)
    private var localAccount: String {
        // Always prefer the actual logged-in console user — this is who
        // softwareupdate will authenticate as via --user flag
        let consoleUser = NSUserName()
        if !consoleUser.isEmpty && consoleUser != "root" {
            return consoleUser
        }

        // Fallback: read localAccount from config.yaml
        let configPath = ctx.configPath.isEmpty
            ? "/Library/Management/PUSH/config.yaml"
            : ctx.configPath
        guard let fileContent = try? String(contentsOfFile: configPath, encoding: .utf8) else { return "" }
        for line in fileContent.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("localAccount:") {
                return t.replacingOccurrences(of: "localAccount:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return ""
    }

    /// Validate a local account password using dscl.
    /// Returns true if correct, or true if no account configured (cannot validate).
    private func validatePassword(account: String, password: String) -> Bool {
        guard !account.isEmpty else { return true }
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments  = ["-c", "dscl /Local/Default -authonly \"\(account)\" \"\(password)\" 2>/dev/null"]
        process.launch()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}


// MARK: - Reboot Nudge (Warning Phase)
//
// Shown during warning phase (uptime ≥ warningThresholdDays, deferrals not exhausted).
// Friendly tone — gives the user a real choice between Later and Restart Now.
// Exit codes: 0 = Restart Now, 1 = Later

struct RebootNudgeView: View {
    @EnvironmentObject var ctx: UIContext
    private var cfg: UIConfig { ctx.config }
    private var accent: Color { cfg.accentColor }

    var body: some View {
        PopupCard(width: CGFloat(cfg.ui.popupWidth)) {
            PopupHeader(config: cfg, subtitle: "Restart Recommended")
            PushDivider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Your Mac has been running for **\(ctx.uptimeDays) days** without a restart.")
                    .font(.system(size: 14))

                Text("Restarting helps with performance, frees up memory, and ensures security updates are fully applied.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                if ctx.uptimeDeferralsRemaining > 0 {
                    Text("You can postpone \(ctx.uptimeDeferralsRemaining) more time\(ctx.uptimeDeferralsRemaining == 1 ? "" : "s") before a restart will be required.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(20)
            PushDivider()

            HStack(spacing: 10) {
                Button("Later") { ctx.exit(.defer_) }
                    .buttonStyle(PushSecondaryButtonStyle())
                Spacer()
                Button("Restart Now") { ctx.exit(.install) }
                    .buttonStyle(PushPrimaryButtonStyle(color: accent))
                    .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - Reboot Force (Countdown Phase)
//
// Shown when uptime ≥ forceThresholdDays OR all deferrals are exhausted.
// One button: Restart Now. Countdown timer auto-restarts at zero.
// No close button, no Esc handling — popup is persistent until restart.

struct RebootForceView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var remaining: Int = 0
    @State private var timer: Timer?
    private var cfg: UIConfig { ctx.config }
    private var accent: Color { cfg.accentColor }

    private var timeString: String {
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        PopupCard(width: CGFloat(cfg.ui.popupWidth)) {
            PopupHeader(config: cfg, subtitle: "Restart Required")
            PushDivider()
            VStack(spacing: 18) {
                Text("Your Mac has been running for **\(ctx.uptimeDays) days** without a restart.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)

                Text("To keep your system secure and stable, your Mac will restart now.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Big visible countdown
                VStack(spacing: 4) {
                    Text("Restarting in")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(timeString)
                        .font(.system(size: 38, weight: .semibold, design: .monospaced))
                        .foregroundStyle(remaining < 60 ? .red : accent)
                        .contentTransition(.numericText())
                }
                .padding(.vertical, 8)

                Text("Please save your work. Your Mac will restart automatically when the timer reaches zero.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(20)
            PushDivider()

            HStack {
                Spacer()
                Button("Restart Now") {
                    timer?.invalidate()
                    ctx.exit(.install)
                }
                .buttonStyle(PushPrimaryButtonStyle(color: accent))
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onAppear {
            remaining = max(1, ctx.uptimeTimerSeconds)
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if remaining > 0 { remaining -= 1 }
                if remaining == 0 {
                    timer?.invalidate()
                    ctx.exit(.install)
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}
