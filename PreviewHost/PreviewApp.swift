// PreviewApp.swift — Preview host showing all PUSH popup states

import SwiftUI

@main
struct PreviewApp: App {
    var body: some Scene {
        WindowGroup {
            PreviewGallery()
                .preferredColorScheme(.dark)
        }
    }
}

struct PreviewGallery: View {
    struct Item { let label: String; let ctx: UIContext }

    var items: [Item] {
        let minor = UIConfig.preview(major: false)
        let major = UIConfig.preview(major: true)
        return [
            Item(label: "soft nudge",     ctx: UIContext(config: minor, state: .softNudge,      deferralCount: 1)),
            Item(label: "hard block",     ctx: UIContext(config: minor, state: .hardBlock,      deferralCount: 5)),
            Item(label: "hard — major",   ctx: UIContext(config: major, state: .hardBlock,      deferralCount: 3)),
            Item(label: "toast",          ctx: UIContext(config: minor, state: .toast,          deferralCount: 0)),
            Item(label: "downloading",    ctx: {
                let c = UIContext(config: minor, state: .downloading)
                c.downloadProgress = 0.42
                c.downloadSubtitle = "Downloading macOS… 42% of 1.2 GB"
                return c
            }()),
            Item(label: "installing",     ctx: UIContext(config: minor, state: .installing)),
            Item(label: "rebooting",      ctx: UIContext(config: minor, state: .rebooting)),
            Item(label: "compliant",      ctx: UIContext(config: minor, state: .compliant)),
            Item(label: "power",          ctx: UIContext(config: minor, state: .preflightPower)),
            Item(label: "disk",           ctx: {
                let c = UIContext(config: minor, state: .preflightDisk)
                c.diskAvailableGB = 8.5
                c.diskRequiredGB  = 25.0
                return c
            }()),
            Item(label: "error",          ctx: {
                let c = UIContext(config: minor, state: .error)
                c.errorMessage = "Download failed. Check your connection and try again."
                return c
            }()),
        ]
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 8) {
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.5)
                        Group {
                            switch item.ctx.state {
                            case .softNudge:      SoftNudgeView()
                            case .hardBlock:      HardBlockView()
                            case .toast:          ToastView()
                            case .downloading:    DownloadView()
                            case .installing:     InstallingView()
                            case .rebooting:      RebootingView()
                            case .compliant:      CompliantView()
                            case .preflightPower: PowerWaitView()
                            case .preflightDisk:  DiskSpaceView()
                            case .error:          ErrorView()
                            default:              EmptyView()
                            }
                        }
                        .environmentObject(item.ctx)
                    }
                }
            }
            .padding(28)
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.14))
    }
}
