// SharedComponents.swift — Shared UI components for PUSH
// Clean, solid card design — opaque background, high contrast text.

import SwiftUI
import AppKit


// MARK: - Custom traffic light buttons

struct TrafficLights: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            trafficButton(color: Color(red: 1.0, green: 0.37, blue: 0.34),
                          hoverIcon: "xmark",
                          action: { Foundation.exit(PushExitCode.dismiss.rawValue) })
            trafficButton(color: Color(red: 1.0, green: 0.73, blue: 0.18),
                          hoverIcon: "minus",
                          action: { NSApp.keyWindow?.miniaturize(nil) })
        }
        .onHover { hovering = $0 }
        .environment(\.hovering, hovering)
    }

    private func trafficButton(color: Color, hoverIcon: String,
                                action: @escaping () -> Void) -> some View {
        TrafficButton(color: color, hoverIcon: hoverIcon, action: action)
    }
}

private struct TrafficButton: View {
    let color:     Color
    let hoverIcon: String
    let action:    () -> Void

    @State  private var localHover = false
    @Environment(\.hovering) private var groupHover

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color).frame(width: 12, height: 12)
                if groupHover || localHover {
                    Image(systemName: hoverIcon)
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.45))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { localHover = $0 }
    }
}

private struct HoveringKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    fileprivate var hovering: Bool {
        get { self[HoveringKey.self] }
        set { self[HoveringKey.self] = newValue }
    }
}

// MARK: - Solid PopupCard (opaque, no glass effect)

struct PopupCard<Content: View>: View {
    let width:             CGFloat
    let showTrafficLights: Bool
    let content:           Content

    init(width: CGFloat = 540,
         showTrafficLights: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.width             = width
        self.showTrafficLights = showTrafficLights
        self.content           = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.08), radius: 4,  x: 0, y: 2)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) {
                if showTrafficLights {
                    TrafficLights()
                        .padding(.leading, 14)
                        .padding(.top, 15)
                }
            }
    }
}

// MARK: - Popup header

struct PopupHeader: View {
    let config:   UIConfig
    let subtitle: String
    var urgent:   Bool = false

    var body: some View {
        HStack(spacing: 13) {
            AppIconView(config: config, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(config.ui.appName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(urgent ? Color.red : Color(NSColor.secondaryLabelColor))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 14)
        .background(urgent ? Color.red.opacity(0.05) : Color.clear)
    }
}

// MARK: - App icon

struct AppIconView: View {
    let config: UIConfig
    let size:   CGFloat

    var body: some View {
        Group {
            if let img = bundleIcon() {
                Image(nsImage: img)
                    .resizable().scaledToFill()
            } else if !config.ui.logoPath.isEmpty,
                      let img = NSImage(contentsOfFile: config.ui.logoPath) {
                Image(nsImage: img)
                    .resizable().scaledToFill()
            } else if !config.ui.sfSymbolName.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(config.accentColor)
                    Image(systemName: config.ui.sfSymbolName)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(LinearGradient(
                            colors: [config.accentColor,
                                     config.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint:   .bottomTrailing))
                    PushArrowIcon()
                        .foregroundStyle(.white)
                        .frame(width: size * 0.52, height: size * 0.52)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }

    private func bundleIcon() -> NSImage? {
        // Try loading from the app bundle — works when icns is in Resources
        if let img = NSImage(named: "InstallAssistant") { return img }
        // Also try direct bundle path
        if let path = Bundle.main.path(forResource: "InstallAssistant", ofType: "icns"),
           let img  = NSImage(contentsOfFile: path) { return img }
        return nil
    }
}

// PUSH default icon — up-arrow with base line
struct PushArrowIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var shaft = Path()
            shaft.move(to: CGPoint(x: w * 0.5, y: h * 0.16))
            shaft.addLine(to: CGPoint(x: w * 0.5, y: h * 0.73))
            ctx.stroke(shaft, with: .foreground,
                       style: StrokeStyle(lineWidth: w * 0.14, lineCap: .round))
            var head = Path()
            head.move(to: CGPoint(x: w * 0.27, y: h * 0.39))
            head.addLine(to: CGPoint(x: w * 0.5, y: h * 0.16))
            head.addLine(to: CGPoint(x: w * 0.73, y: h * 0.39))
            ctx.stroke(head, with: .foreground,
                       style: StrokeStyle(lineWidth: w * 0.13, lineCap: .round, lineJoin: .round))
            var base = Path()
            base.move(to: CGPoint(x: w * 0.2, y: h * 0.85))
            base.addLine(to: CGPoint(x: w * 0.8, y: h * 0.85))
            ctx.stroke(base, with: .color(.white.opacity(0.5)),
                       style: StrokeStyle(lineWidth: w * 0.11, lineCap: .round))
        }
    }
}

// MARK: - Rich message view
// Supports: \n (newline), \n\n (paragraph gap), - item / • item (bullets)

struct RichMessage: View {
    let text:     String
    let fontSize: CGFloat
    var color:    Color = Color.secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                switch block.kind {
                case .text:
                    Text(block.content)
                        .font(.system(size: fontSize))
                        .foregroundStyle(color)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, idx < blocks.count - 1 ? 8 : 0)
                case .bullet:
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(color.opacity(0.45))
                            .frame(width: 5, height: 5)
                            .padding(.top, fontSize * 0.42)
                        Text(block.content)
                            .font(.system(size: fontSize))
                            .foregroundStyle(color)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    struct Block {
        enum Kind { case text, bullet }
        let kind:    Kind
        let content: String
    }

    var blocks: [Block] {
        let resolved = text.resolvedNewlines
        let lines    = resolved.components(separatedBy: "\n")
        var result:  [Block] = []
        var para:    [String] = []

        func flushPara() {
            let joined = para.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { result.append(Block(kind: .text, content: joined)) }
            para = []
        }

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                flushPara()
            } else if t.hasPrefix("- ") || t.hasPrefix("• ") {
                flushPara()
                let content = t.hasPrefix("- ")
                    ? String(t.dropFirst(2))
                    : String(t.dropFirst(2))
                result.append(Block(kind: .bullet, content: content))
            } else {
                para.append(t)
            }
        }
        flushPara()
        return result
    }
}

// MARK: - Version row

struct VersionRow: View {
    let config: UIConfig

    var body: some View {
        HStack(spacing: 0) {
            versionChip(label: "Current",
                        value: "macOS \(config.currentVersion)",
                        accent: false)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            versionChip(label: "Required",
                        value: config.friendlyTargetVersion,
                        accent: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.primary.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
        .cornerRadius(10)
    }

    private func versionChip(label: String, value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .kerning(0.5)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(accent ? config.accentColor : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status bar (deadline + deferrals)

struct StatusBar: View {
    let config:        UIConfig
    let deferralsLeft: Int

    @State private var countdownText = ""
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            if !countdownText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(countdownText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: deferralsLeft > 1
                      ? "arrow.uturn.backward.circle.fill"
                      : "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(deferralsLeft > 1 ? Color.secondary : Color.orange)
                Text("\(deferralsLeft) deferral\(deferralsLeft == 1 ? "" : "s") left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(deferralsLeft > 1 ? Color.secondary : Color.orange)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
        .cornerRadius(8)
        .onAppear { countdownText = buildCountdown() }
        .onReceive(timer) { _ in countdownText = buildCountdown() }
    }

    private func buildCountdown() -> String {
        guard let deadline = config.deadlineDate else { return "" }
        let diff = deadline.timeIntervalSinceNow
        if diff <= 0 { return "Deadline passed" }
        let d = Int(diff) / 86400
        let h = Int(diff) % 86400 / 3600
        let m = Int(diff) % 3600 / 60
        if d > 0 { return "\(d)d \(h)h remaining" }
        if h > 0 { return "\(h)h \(m)m remaining" }
        return "\(m)m remaining"
    }
}

// MARK: - IT contact strip

struct ITContactStrip: View {
    let config: UIConfig

    var hasContact: Bool {
        !config.ui.itContactEmail.isEmpty || !config.ui.itContactPhone.isEmpty
    }

    var body: some View {
        if hasContact {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 30, height: 30)
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Need help?")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if !config.ui.itContactEmail.isEmpty {
                            Text(config.ui.itContactEmail)
                                .font(.system(size: 12))
                                .foregroundStyle(config.accentColor)
                        }
                        if !config.ui.itContactPhone.isEmpty {
                            Text(config.ui.itContactPhone)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(Color.primary.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
            .cornerRadius(10)
        }
    }
}

// MARK: - Urgent banner

struct UrgentBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.red)
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color.red.opacity(0.18), lineWidth: 0.5))
        .cornerRadius(8)
    }
}

// MARK: - Indeterminate progress bar (shimmer animation)

struct IndeterminateBar: View {
    let color:  Color
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * 0.32)
                    .offset(x: (geo.size.width + geo.size.width * 0.32) * phase
                              - geo.size.width * 0.32)
            }
        }
        .frame(height: 5)
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

// MARK: - Countdown drain bar

struct CountdownDrainBar: View {
    let progress: Double   // 1.0 → 0.0
    let color:    Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * max(0, min(1, progress)))
                    .animation(.linear(duration: 1), value: progress)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Divider

struct PushDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}

// MARK: - Primary full-width button

struct PrimaryActionButton: View {
    let label:  String
    let icon:   String?
    let color:  Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Deferral reason sheet

struct DeferralReasonSheet: View {
    let config:    UIConfig
    let onConfirm: (String) -> Void
    let onCancel:  () -> Void

    @State private var selected: String = ""

    var reasons: [String] {
        config.ui.deferralReasons.isEmpty
            ? ["I am busy right now", "I am in a meeting", "I am traveling",
               "I need IT support", "Other"]
            : config.ui.deferralReasons
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Why are you deferring?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 14)

            PushDivider()

            VStack(spacing: 6) {
                ForEach(reasons, id: \.self) { reason in
                    Button(action: { selected = reason }) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(selected == reason
                                        ? config.accentColor
                                        : Color.secondary.opacity(0.3),
                                        lineWidth: selected == reason ? 2 : 1)
                                    .frame(width: 18, height: 18)
                                if selected == reason {
                                    Circle()
                                        .fill(config.accentColor)
                                        .frame(width: 10, height: 10)
                                }
                            }
                            Text(reason)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(selected == reason
                            ? config.accentColor.opacity(0.06)
                            : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)

            PushDivider()

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(PushSecondaryButtonStyle())
                Spacer()
                Button("Confirm") {
                    onConfirm(selected.isEmpty ? reasons[0] : selected)
                }
                .buttonStyle(PushPrimaryButtonStyle(color: config.accentColor))
                .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear { selected = reasons[0] }
    }
}

// MARK: - Button styles

struct PushPrimaryButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(8)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PushSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
            .cornerRadius(8)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PushToastPrimaryStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1))
            .cornerRadius(7)
    }
}

struct PushToastSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.09), lineWidth: 0.5))
            .cornerRadius(7)
    }
}
