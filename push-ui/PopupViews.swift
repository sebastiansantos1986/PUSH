// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: PopupViews.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

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
    @State private var schedulerError = ""
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
            .disabled(showingDatePicker || showingReasonSheet)

            // Deferral reason sheet overlay
            if showingReasonSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showingReasonSheet = false }
                DeferralReasonSheet(config: cfg) { reason in
                    // Write reason to temp file so CLI can pick it up
                    try? reason.write(toFile: "/tmp/push-deferral-reason",
                                      atomically: true, encoding: .utf8)
                    showingReasonSheet = false
                    ctx.exit(.defer_)
                } onCancel: {
                    ctx.noteAction("Cancel deferral reason")
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
                                deadline: reminderTestDeadline(configured: cfg.deadlineDate, manualTest: ctx.isManualTest)) { chosenDate in
                    // Write chosen date to temp file so CLI can pick it up
                    let iso = ISO8601DateFormatter().string(from: chosenDate)
                    do {
                        try iso.write(toFile: "/tmp/push-scheduled-until", atomically: true, encoding: .utf8)
                    } catch {
                        schedulerError = "The reminder could not be saved. Please try again or contact IT."
                        return
                    }
                    showingDatePicker = false
                    ctx.exit(.scheduledDefer)
                } onCancel: {
                    ctx.noteAction("Cancel schedule")
                    showingDatePicker = false
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .alert("Reminder not saved", isPresented: Binding(get: { !schedulerError.isEmpty }, set: { if !$0 { schedulerError = "" } })) {
            Button("OK") { schedulerError = "" }
        } message: { Text(schedulerError) }
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
                        ctx.noteAction("Open deferral reasons")
                        showingReasonSheet = true
                    } else {
                        ctx.exit(.defer_)
                    }
                }
                .buttonStyle(PushSecondaryButtonStyle())

                // Schedule button — user picks specific date/time, no deferral cost
                Button("Schedule…") { ctx.noteAction("Open scheduler"); showingDatePicker = true }
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
    @State private var visible = false
    @State private var hovering = false
    @State private var secondsLeft = 0
    @State private var autoClosed = false
    private var toast: UIConfig.ToastCfg { ctx.config.toast }
    private var accent: Color { ctx.config.accentColor }
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var message: String {
        if let information=ctx.informationalToastMessage {return information}
        if let custom = toast.message, !custom.isEmpty { return custom.resolvedNewlines }
        return ctx.config.isMajor
            ? "A macOS upgrade is ready. Save your work and choose when to begin."
            : "A macOS security update is ready. Save your work before installing."
    }
    private var deadlineLabel: String? {
        guard let date = ctx.config.deadlineDate else { return nil }
        if date < Date() { return "Deadline passed" }
        if Calendar.current.isDateInToday(date) { return "Due today" }
        return "Due " + date.formatted(date: .abbreviated, time: .omitted)
    }
    private var slideOffset: CGFloat {
        ["topLeft", "bottomLeft"].contains(toast.position) ? -18 : 18
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                AppIconView(config: ctx.config, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ctx.informationalToastMessage == nil ? "Software Update":"Update status")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(ctx.config.friendlyTargetVersion)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if toast.showCloseButton {
                    Button { ctx.exit(.dismiss) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss this reminder")
                    .accessibilityLabel("Dismiss this reminder")
                }
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Label("Restart required", systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let deadlineLabel {
                    Text(deadlineLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ctx.config.deadlineDate.map { $0 < Date() } == true ? Color.orange : accent)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(accent.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 1)
            HStack(spacing:10) {
                if ctx.informationalToastMessage != nil {
                    Button("Got it") {ctx.exit(.dismiss)}.buttonStyle(PushToastPrimaryStyle(color:accent))
                } else {
                if toast.showDeferButton {
                    Button { ctx.exit(.defer_) } label: {
                        Text(toast.deferButtonLabel.isEmpty ? "Later" : toast.deferButtonLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PushToastSecondaryStyle())
                    .accessibilityHint("Close this reminder without requesting installation")
                }
                Button { ctx.exit(.install) } label: {
                    Text(toast.installButtonLabel.isEmpty ? "Install Now" : toast.installButtonLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PushToastPrimaryStyle(color: accent))
                }
            }
            if (toast.autoDismissSeconds ?? 0) > 0 {
                Text(hovering ? "Reminder stays open while you hover" : "Closes in \(secondsLeft) seconds")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: CGFloat(min(700, max(300, toast.width))))
        .background(PopupSurface())
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(max(8, toast.cornerRadius))))
        .overlay(RoundedRectangle(cornerRadius: CGFloat(max(8, toast.cornerRadius))).stroke(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 8)
        .opacity(visible ? 1 : 0)
        .offset(x: visible ? 0 : slideOffset)
        .onAppear {
            autoClosed = false
            secondsLeft = max(0, toast.autoDismissSeconds ?? 0)
            withAnimation(.easeOut(duration: 0.2)) { visible = true }
            if !toast.soundName.isEmpty { NSSound(named: toast.soundName)?.play() }
        }
        .onReceive(tick) { _ in
            guard !autoClosed, !hovering, (toast.autoDismissSeconds ?? 0) > 0 else { return }
            if secondsLeft > 0 { secondsLeft -= 1 }
            if secondsLeft == 0 { autoClosed = true; ctx.exit(.toastTimeout, automatic: true) }
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
            if let raw = try? String(contentsOfFile: "/private/var/run/com.push/download-progress",
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
    private let progressFile = "/private/var/run/com.push/install-progress"

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
            else { ctx.exit(.install, automatic: true) }
        }
    }
}

// MARK: ── Compliant ───────────────────────────────────────────────────────────

struct CompliantView: View {
    @EnvironmentObject var ctx: UIContext

    var body: some View {
        PopupCard(width: CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config: ctx.config, subtitle: "Up to Date",
                        title: ctx.config.ui.appName == "Software Update Required" ? "Software Update" : ctx.config.ui.appName)
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
                ctx.exit(.powerTimeout, automatic: true)
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
        guard !ctx.isManualTest else { return }
        guard isOnACPower() else { return }
        powerFound   = true
        statusText   = "Power detected — continuing…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            ctx.exit(.install, automatic: true)
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
    @State private var actionError = ""
    @State private var showActionError = false
    private var supportURL: URL? { supportContactURL(email:ctx.config.ui.itContactEmail, website:ctx.config.ui.helpURL) }
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
                Button(supportURL == nil ? "Close" : "Contact IT") { openSupport() }
                    .buttonStyle(PushSecondaryButtonStyle())
                Spacer()
                Button(action: openStorageSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 13, weight: .semibold))
                        Text(ctx.config.preflight.diskSpaceLearnMoreURL.isEmpty ? "Open Storage Settings" : "Storage Help")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(PushPrimaryButtonStyle(color: accent))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .alert("Could not open the requested destination", isPresented:$showActionError) {
            Button("OK", role:.cancel) { ctx.noteAction("Acknowledge action error") }
        } message: { Text(actionError) }
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

    private func openSupport() {
        guard let url = supportURL else { ctx.exit(.dismiss); return }
        if NSWorkspace.shared.open(url) { ctx.exit(.contactSupport) }
        else { actionError = "No application could open your configured IT contact. Contact your IT team directly."; showActionError = true }
    }
    private func openStorageSettings() {
        let configured = ctx.config.preflight.diskSpaceLearnMoreURL
        let url: URL?
        if configured.isEmpty { url = URL(string:"x-apple.systempreferences:com.apple.settings.Storage") }
        else if let candidate = URL(string:configured), candidate.scheme == "https", candidate.host != nil { url = candidate }
        else { url = nil }
        guard let url, NSWorkspace.shared.open(url) else {
            actionError = "Storage Settings could not be opened. Open System Settings > General > Storage manually."; showActionError = true; return
        }
        ctx.noteAction(ctx.config.preflight.diskSpaceLearnMoreURL.isEmpty ? "Open Storage Settings" : "Storage Help")
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
                         ? "Enter the password for \(localAccount.isEmpty ? "your account" : localAccount) to install the update.\n\nYour password will be saved securely in your login keychain so future updates can install automatically."
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
        guard allowsUserPasswordPrompts else {
            password = ""
            errorMsg = "Password collection is disabled. Contact IT for managed authorization."
            return
        }
        guard !password.isEmpty else { return }
        validating = true
        errorMsg   = ""

        // Validate password against the local account using OpenDirectory
        let account = localAccount
        let pwd     = password

        DispatchQueue.global(qos: .userInitiated).async {
            let valid = validatePassword(account: account, password: pwd)
            DispatchQueue.main.async {
                validating = false
                if valid {
                    // Save to user's login keychain for future automatic installs.
                    // This is the disclosed behavior per the prompt text. Failure
                    // here blocks the handoff so no plaintext fallback is needed.
                    if saveUserPasswordToLoginKeychain(account: account, password: pwd) {
                        ctx.exit(.install)
                    } else {
                        password = ""
                        errorMsg = "Could not save password securely. Please try again or contact IT."
                        shaking  = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shaking = false }
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

    /// Validate a local account password using OpenDirectory.
    /// Missing accounts and authentication errors fail closed.
    private func validatePassword(account: String, password: String) -> Bool {
        return verifyLocalPassword(account: account, password: password)
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
                    ctx.exit(.install, automatic: true)
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

// MARK: - Grouped application update toast
// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
struct AppUpdatesToast: View {
    @EnvironmentObject var ctx: UIContext
    private var accent: Color { ctx.config.accentColor }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:12) {
                AppIconView(config:ctx.config,size:44)
                VStack(alignment:.leading,spacing:3) {
                    Text("App updates available").font(.system(size:15,weight:.bold))
                    Text("\(ctx.appUpdates.count) approved apps · save your work").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:4)
                Button { ctx.exit(.dismiss) } label: { Image(systemName:"xmark").frame(width:28,height:28) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss app updates")
            }
            if ctx.isManualTest {
                Text("PREVIEW · Sample versions. No software will be updated.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(ctx.appUpdates) { app in
                VStack(alignment:.leading,spacing:4) {
                    HStack { Text(app.name).font(.system(size:13,weight:.semibold)); Spacer(); Image(systemName:"arrow.down.circle").foregroundStyle(accent) }
                    Text("\(app.installed) → \(app.target)").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
                    if let deadline = ISO8601DateFormatter().date(from:app.deadline) {
                        Text(deadline < Date() ? "Update overdue" : "Due " + deadline.formatted(date:.abbreviated,time:.omitted))
                            .font(.caption2).foregroundStyle(deadline < Date() ? Color.orange : .secondary)
                    }
                }.padding(12).background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius:10))
            }
            Text("Close open apps when you're ready. PUSH updates closed apps and leaves your work open.")
                .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack(spacing:10) {
                Button("Later") { ctx.exit(.defer_) }.buttonStyle(PushToastSecondaryStyle())
                Button("Update Closed Apps") { ctx.exit(.install) }.buttonStyle(PushToastPrimaryStyle(color:accent))
            }
        }
        .padding(20)
        .frame(width:CGFloat(min(700,max(300,ctx.config.toast.width))))
        .background(PopupSurface())
        .clipShape(RoundedRectangle(cornerRadius:16))
        .overlay(RoundedRectangle(cornerRadius:16).stroke(Color.primary.opacity(0.12)))
        .shadow(color:.black.opacity(0.20),radius:20,y:8)
    }
}

// MARK: - Microsoft Entra registration reminder
// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
struct EntraRegistrationView: View {
    @EnvironmentObject var ctx: UIContext
    @State private var supportError = false
    private var notice: EntraNotice { ctx.entraNotice }
    private var supportURL: URL? { supportContactURL(email:ctx.config.ui.itContactEmail,website:ctx.config.ui.helpURL) }
    var body: some View {
        PopupCard(width:CGFloat(ctx.config.ui.popupWidth)) {
            HStack(spacing:14) {
                AppIconView(config:ctx.config,size:48)
                VStack(alignment:.leading,spacing:4) {
                    Text("Microsoft Entra Registration").font(.system(size:17,weight:.bold))
                    Text(notice.heading).font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Button { ctx.exit(.dismiss) } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Close registration reminder")
            }.padding(22)
            PushDivider()
            VStack(alignment:.leading,spacing:18) {
                if ctx.isManualTest { Text("PREVIEW · Self Service will not open. No registration or inventory changes.").font(.caption).foregroundStyle(.secondary) }
                Label("Register this Mac with your organization",systemImage:"person.crop.circle.badge.checkmark").font(.headline)
                Text(notice.message).font(.system(size:14)).fixedSize(horizontal:false,vertical:true)
                HStack {
                    Label("Reminder stage \(notice.stage) of 4",systemImage:"bell.badge").font(.caption)
                    Spacer()
                    Text("Later selected \(notice.laterCount) times").font(.caption).foregroundStyle(.secondary)
                }.padding(12).background(ctx.config.accentColor.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:10))
                Text("Register Now opens the registration policy in Self Service. Follow the instructions there; PUSH does not collect your password.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(22)
            PushDivider()
            HStack(spacing:10) {
                Button("Later") { ctx.exit(.defer_) }.buttonStyle(PushSecondaryButtonStyle())
                if let supportURL {
                    Button("Contact IT") {
                        if ctx.isPreview || ctx.isManualTest { ctx.exit(.contactSupport) }
                        else if NSWorkspace.shared.open(supportURL) { ctx.exit(.contactSupport) }
                        else { supportError = true }
                    }.buttonStyle(PushSecondaryButtonStyle())
                }
                Spacer(minLength:0)
                Button("Register Now") { ctx.exit(.install) }.buttonStyle(PushPrimaryButtonStyle(color:ctx.config.accentColor))
            }.padding(20)
        }
        .alert("Could not open IT contact",isPresented:$supportError) { Button("OK",role:.cancel) {} } message: { Text("Please contact your organization's IT team directly.") }
    }
}
