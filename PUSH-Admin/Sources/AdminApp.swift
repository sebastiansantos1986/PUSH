// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
import Combine

enum AdminPage: String, CaseIterable, Identifiable {
    case singlePopup = "Single Popups"
    case majorUpgrade = "Major Upgrade (Debug)"
    case recovery = "User Status & Recovery", history = "Delivery History", wallpaper = "Wallpaper", setup = "Guided Setup", readiness = "Readiness", overview = "Overview", catalog = "macOS Releases", configuration = "Configuration", apps = "App Updates", entra = "Entra Registration", studio = "Popup Studio", deployment = "Deployment"
    var id: String { rawValue }
    var icon: String {
        switch self { case .singlePopup:return "bubble.left.and.text.bubble.right"; case .majorUpgrade:return "arrow.up.square"; case .recovery:return "arrow.clockwise.circle"; case .history:return "clock.arrow.circlepath"; case .wallpaper:return "photo"; case .setup:return "wand.and.stars"; case .readiness:return "checklist"; case .overview:return "square.grid.2x2"; case .catalog:return "globe.americas"; case .configuration:return "slider.horizontal.3"; case .apps:return "square.stack.3d.up"; case .entra:return "person.crop.circle.badge.checkmark"; case .studio:return "rectangle.on.rectangle"; case .deployment:return "shippingbox" }
    }
}
@main
struct PUSHAdminApp: App {
    @StateObject private var store = AdminStore()
    var body: some Scene {
        WindowGroup("PUSH Admin") { AdminRoot().environmentObject(store).frame(minWidth:1100,minHeight:780) }
            .defaultSize(width:1250,height:900)
        Settings { VStack(alignment:.leading,spacing:12) {
            Text("PUSH Admin").font(.title2.bold()); Text("Version 1.3.0 · Developer: Sebastian Santos")
            Text("Mist checks run at launch and when you refresh. They list stable installers compatible with this Mac; they never download an installer.")
            Link("mist-cli project",destination:URL(string:"https://github.com/ninxsoft/mist-cli")!)
        }.padding(28).frame(width:500) }
    }
}
struct AdminRoot: View {
    @EnvironmentObject var store: AdminStore
    @State private var page: AdminPage = .readiness
    var body: some View {
        GeometryReader { window in
            HStack(spacing: 0) {
                sidebar.frame(width: 238, height: max(1, window.size.height))
                Divider()
                detail.frame(width: max(1, window.size.width - 239), height: max(1, window.size.height))
            }
            .frame(width: max(1, window.size.width), height: max(1, window.size.height), alignment: .topLeading)
        }
        .task { await store.startup() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 34)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PUSH").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("ADMIN CONSOLE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                }
            }.padding(22)
            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(AdminPage.allCases) { item in
                        Button { page = item } label: {
                            Label(item.rawValue, systemImage: item.icon)
                                .font(.callout.weight(page == item ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 11)
                                .foregroundStyle(page == item ? Color.blue : Color.primary)
                                .background(page == item ? Color.blue.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12)
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Label("User password prompts disabled", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Text("Sebastian Santos · v1.3.0").font(.caption2).foregroundStyle(.tertiary)
            }.padding(18)
        }.background(Color(NSColor.controlBackgroundColor))
    }
    private var detail: some View {
        VStack(spacing: 0) {
            HStack {
                Text(page.rawValue).font(.headline)
                Spacer()
                Button("New draft") { store.newDraft() }
                Button { store.chooseImport() } label: { Label("Import YAML", systemImage: "square.and.arrow.down") }
                Button { store.exportDocument() } label: { Label("Export YAML", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent).disabled(!store.document.problems.isEmpty)
            }.padding(.horizontal, 24).padding(.vertical, 16).fixedSize(horizontal: false, vertical: true)
            Divider()
            Group {
                switch page {
                case .singlePopup: SinglePopupPage()
                case .majorUpgrade: MajorUpgradePage()
                case .recovery: RecoverySettingsPage()
                case .history: NotificationHistoryPage(navigate: {page = $0})
                case .wallpaper: WallpaperPage(navigate: {page = $0})
                case .setup: SetupWizardPage(navigate: { page = $0 })
                case .readiness: ReadinessPage(navigate: { page = $0 })
                case .overview: OverviewPage(navigate: { page = $0 })
                case .catalog: CatalogPage()
                case .configuration: ConfigurationPage()
                case .apps: AppsPage()
                case .entra: EntraPage()
                case .studio: PopupStudioPage()
                case .deployment: DeploymentPage()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).layoutPriority(1)
            if !store.notice.isEmpty {
                Divider()
                HStack(alignment: .top) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                    Text(store.notice).font(.callout).textSelection(.enabled).lineLimit(4)
                    Spacer()
                    Button { store.notice = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.padding(14).background(.blue.opacity(0.05)).fixedSize(horizontal: false, vertical: true)
            }
        }.background(Color(NSColor.windowBackgroundColor))
    }
}

struct PageHeading: View {
    let eyebrow: String, title: String, subtitle: String
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(eyebrow.uppercased()).font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(.blue)
            Text(title).font(.system(size:30,weight:.bold,design:.rounded))
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct AdminCard<Content:View>: View {
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment:.leading,spacing:16){content}.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(Color(NSColor.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(.primary.opacity(0.07))) }
}
struct MetricCard: View {
    let icon: String, title: String, value: String, detail: String
    var body: some View { AdminCard {
        Image(systemName:icon).font(.title2).foregroundStyle(.blue)
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.system(size:23,weight:.bold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.7)
        Text(detail).font(.caption).foregroundStyle(.secondary)
    } }
}
struct OverviewPage: View {
    @EnvironmentObject var store: AdminStore
    let navigate: (AdminPage)->Void
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            PageHeading(eyebrow:"Welcome to PUSH Admin",title:"One place to set up PUSH.",subtitle:"Discover macOS releases, shape your policy, and see exactly what users will see.")
            Button("Open guided setup") {navigate(.setup)}.buttonStyle(.borderedProminent)
            HStack(alignment:.top,spacing:16) {
                MetricCard(icon:"desktopcomputer",title:"Installed PUSH",value:store.pushVersion,detail:store.pushInstalled ? "Engine detected on this Mac" : "Companion works without enrollment")
                MetricCard(icon:"globe",title:store.catalogIsCached ? "Latest cached release" : "Latest compatible release",value:store.releases.first?.version ?? (store.isRefreshing ? "Checking…" : "Unavailable"),detail:store.lastChecked.map {"Checked " + $0.formatted(date:.abbreviated,time:.shortened)} ?? "Checks automatically when this app opens")
                MetricCard(icon:"shield.lefthalf.filled",title:"Draft mode",value:(store.document.value("debug.dryRun") ?? "true") == "true" ? "Dry run" : "Live policy",detail:"Drafts do not change the installed policy")
            }
            InstalledHealthCard()
            HStack(alignment:.top,spacing:18) {
                AdminCard {
                    Label("Your setup path",systemImage:"list.number").font(.headline)
                    setupStep("1","Choose your macOS target","Review stable compatible releases from Mist.",.catalog)
                    Divider(); setupStep("2","Configure your policy","Set deadlines, branding, hours, and restart reminders.",.configuration)
                    Divider(); setupStep("3","Preview the experience","Click through real popup layouts with simulated actions.",.studio)
                    Divider(); setupStep("4","Export or apply","Save YAML for Jamf, or apply it to this Mac with a backup.",.deployment)
                }
                VStack(spacing:18) {
                    AdminCard {
                        Label("Existing setup?",systemImage:"folder.badge.gearshape").font(.headline)
                        Text("Import your installed configuration into a draft. Unknown settings are kept; known plaintext credential values are omitted.").font(.callout).foregroundStyle(.secondary)
                        Button("Import installed config") {store.importDocument(URL(fileURLWithPath:store.livePath))}.disabled(!store.pushInstalled)
                    }
                    AdminCard {
                        Label("Catalog status",systemImage:"antenna.radiowaves.left.and.right").font(.headline)
                        Text(store.catalogMessage).font(.callout).foregroundStyle(.secondary)
                        Button(store.isRefreshing ? "Checking…" : "Refresh releases") {Task {await store.refreshCatalog()}}.disabled(store.isRefreshing)
                    }
                }.frame(maxWidth:320)
            }
        }.padding(30) }
    }
    func setupStep(_ number:String,_ title:String,_ subtitle:String,_ page:AdminPage)->some View {
        Button {navigate(page)} label:{HStack(alignment:.top,spacing:12){
            Text(number).font(.callout.bold()).frame(width:28,height:28).background(.blue.opacity(0.12)).clipShape(Circle()).foregroundStyle(.blue)
            VStack(alignment:.leading,spacing:4){Text(title).font(.headline);Text(subtitle).font(.caption).foregroundStyle(.secondary)}
            Spacer();Image(systemName:"chevron.right").foregroundStyle(.tertiary)
        }.padding(.vertical,4)}.buttonStyle(.plain)
    }
}
struct CatalogPage: View {
    @EnvironmentObject var store: AdminStore
    var body: some View {
        ScrollView {VStack(alignment:.leading,spacing:24){
            PageHeading(eyebrow:"Powered by mist-cli",title:"Choose your next macOS.",subtitle:"Stable installers compatible with the Mac running this companion. A mixed fleet may need different targets by hardware model.")
            AdminCard {
                HStack {Label(store.catalogIsCached ? "Cached catalog · refresh needed" : "Compatible stable releases",systemImage:store.catalogIsCached ? "clock.arrow.circlepath" : "checkmark.seal").font(.headline); Spacer();if store.isRefreshing {ProgressView().controlSize(.small)};Button("Refresh") {Task{await store.refreshCatalog()}}.disabled(store.isRefreshing)}
                Text(store.catalogMessage).font(.callout).foregroundStyle(.secondary)
                if let latest = store.releases.first {
                    HStack {VStack(alignment:.leading,spacing:6){Text("LATEST AVAILABLE").font(.caption2.bold()).tracking(1).foregroundStyle(.blue);Text(latest.name + " " + latest.version).font(.title2.bold());Text("Build " + latest.build).font(.caption).foregroundStyle(.secondary)};Spacer();Button("Use in draft") {store.selectRelease(latest)}.buttonStyle(.borderedProminent)}.padding(18).background(.blue.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius:12))
                } else {ContentUnavailableView("No catalog yet",systemImage:"globe",description:Text("Install mist-cli and refresh, or enter a target version in Configuration."))}
                if store.mistPath == nil {Link("Get mist-cli from its official releases",destination:URL(string:"https://github.com/ninxsoft/mist-cli/releases")!)}
            }
            if !store.releases.isEmpty {AdminCard {
                ForEach(Array(store.releases.enumerated()),id:\.element.id) { index,release in
                    if index > 0 {Divider()}
                    HStack {Image(systemName:"apple.logo").font(.title2).frame(width:36);VStack(alignment:.leading,spacing:3){Text(release.name + " " + release.version).font(.headline);Text("Build " + release.build + (release.date.isEmpty ? "" : " · " + release.date)).font(.caption).foregroundStyle(.secondary)};Spacer();Button(store.document.value("update.targetVersion") == release.version ? "Selected" : "Use version") {store.selectRelease(release)}}
                }
            }}
            Text("Checking the catalog never downloads macOS, changes your target, or starts an installation. Beta releases are excluded.").font(.caption).foregroundStyle(.secondary)
        }.padding(30)}
    }
}
struct ConfigurationPage: View {
    @EnvironmentObject var store: AdminStore
    var group:ConfigGroup {configGroups.first {$0.id==store.groupID} ?? configGroups[0]}
    var body: some View {
        HStack(spacing:0) {
            ScrollView {VStack(alignment:.leading,spacing:6){
                Text("POLICY SECTIONS").font(.caption2.bold()).tracking(1).foregroundStyle(.secondary).padding(.bottom,10)
                ForEach(configGroups){g in Button {store.groupID=g.id} label:{Label(g.title,systemImage:g.icon).font(.callout).frame(maxWidth:.infinity,alignment:.leading).padding(11).background(store.groupID==g.id ? Color.blue.opacity(0.12):Color.clear).clipShape(RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)}
            }.padding(16)}.frame(width:235)
            Divider()
            ScrollView {VStack(alignment:.leading,spacing:22){
                PageHeading(eyebrow:store.document.sourceName,title:group.title,subtitle:group.subtitle)
                if group.id == "detection" || group.id == "updates" { SmartPolicySetupCard() }
                if group.id == "identity" { AdminCard { PopupLogoControls(); Divider(); PopupAppearanceControls() } }
                AdminCard {ForEach(Array(group.fields.enumerated()),id:\.element.id){index,field in
                    if index>0 {Divider()}; fieldEditor(field)
                }}
                ValidationSummary()
                DisclosureGroup("YAML preview",isExpanded:$store.expandedYAML) {
                    Text(store.document.yaml).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(14).background(.primary.opacity(0.03)).clipShape(RoundedRectangle(cornerRadius:8))
                }
                if store.document.omittedCredentials>0 {Text("Plaintext credential values were excluded from the imported draft. Use your IT provisioning process for secrets.").font(.caption).foregroundStyle(.orange)}
            }.padding(26)}
        }
    }
    @ViewBuilder func fieldEditor(_ field:ConfigField)->some View {
        let binding = Binding<String>(get:{store.document.value(field)},set:{ value in
            store.document.edits[field.id] = value
            if field.id == "ui.logoPath" && value != deployedPopupLogoPath {
                store.document.logoImageData = nil; store.document.logoImageName = nil
            }
        })
        VStack(alignment:.leading,spacing:7){
            if field.id == "update.deadline" {
                Toggle("Use an explicit deadline",isOn:Binding(get:{!binding.wrappedValue.isEmpty},set:{binding.wrappedValue = $0 ? ISO8601DateFormatter().string(from:Date().addingTimeInterval(7*86400)):""}))
                if !binding.wrappedValue.isEmpty {
                    DatePicker("Deadline",selection:Binding(get:{ISO8601DateFormatter().date(from:binding.wrappedValue) ?? Date()},set:{binding.wrappedValue=ISO8601DateFormatter().string(from:$0)}),displayedComponents:[.date,.hourAndMinute])
                }
            } else { switch field.kind {
            case .boolean:Toggle(field.title,isOn:Binding(get:{binding.wrappedValue=="true"},set:{binding.wrappedValue=$0 ? "true":"false"})).toggleStyle(.switch)
            case .choice(let options):Picker(field.title,selection:binding){ForEach(options,id:\.self){Text($0).tag($0)}}
            case .number(let range):HStack {
                Text(field.title).font(.callout.weight(.medium)); Spacer()
                TextField("",text:binding).textFieldStyle(.roundedBorder).frame(width:80)
                Stepper("",value:Binding(get:{Int(binding.wrappedValue) ?? range.lowerBound},set:{binding.wrappedValue=String($0)}),in:range).labelsHidden()
            }
            case .multiline:Text(field.title).font(.callout.weight(.medium)); TextEditor(text:binding).font(.body).frame(minHeight:90).padding(6).overlay(RoundedRectangle(cornerRadius:6).stroke(.primary.opacity(0.15)))
            default:Text(field.title).font(.callout.weight(.medium));TextField(field.initial,text:binding).textFieldStyle(.roundedBorder)
            }}
            if !field.help.isEmpty {Text(field.help).font(.caption).foregroundStyle(.secondary)}
        }.padding(.vertical,4)
    }
}
struct ValidationSummary: View {
    @EnvironmentObject var store:AdminStore
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            if store.document.problems.isEmpty {Label("Configuration is ready to export",systemImage:"checkmark.circle.fill").foregroundStyle(.green)}
            else {Label("Review before exporting",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange);ForEach(store.document.problems,id:\.self){Text("• " + $0).font(.callout)}}
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background((store.document.problems.isEmpty ? Color.green:Color.orange).opacity(0.06)).clipShape(RoundedRectangle(cornerRadius:10))
    }
}
struct PopupStudioPage: View {
    @EnvironmentObject var store: AdminStore
    @State private var selected: UIState = .softNudge
    @State private var progress = 0.42
    @State private var deferrals = 1
    @State private var revision = UUID()
    @State private var showLogoControls = false
    let states: [UIState] = [.updateRecovery, .softNudge, .hardBlock, .toast, .appUpdates, .entraRegistration, .downloading, .installing, .rebootNudge, .rebootForce, .rebooting, .preflightPower, .preflightDisk, .compliant, .error]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(eyebrow: "Popup Studio", title: "See it before you deploy it.", subtitle: "Choose a popup below. Click its icon to add an image directly to the preview. Buttons are simulated.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Popup", selection: $selected) {
                        ForEach(states, id: \.rawValue) { state in Text(state.windowTitle).tag(state) }
                    }.pickerStyle(.menu)
                    Button("Choose preview image…") { store.choosePopupLogo() }
                    Button("Reset preview") { revision = UUID() }
                }
                HStack(spacing: 20) {
                    HStack {
                        Text("Download").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $progress, in: 0...1, onEditingChanged: { if !$0 { revision = UUID() } })
                        Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                    }
                    Stepper("Deferrals: \(deferrals)", value: $deferrals, in: 0...20).font(.caption).fixedSize()
                }
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Popup appearance & icon", isExpanded: $showLogoControls) {
                VStack(spacing:14) { PopupAppearanceControls(); Divider(); PopupLogoControls() }.padding(.top,10)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius:12))
            .fixedSize(horizontal:false, vertical:true)
            if store.document.problems.isEmpty {
                StudioPreview(state: selected, yaml: store.previewYAML, progress: progress, deferrals: deferrals,
                              logoData: store.previewLogoImageData, chooseLogo: {store.choosePopupLogo()})
                    .id(PopupPreviewIdentity(revision:revision,yaml:store.previewYAML,imageData:store.document.logoImageData)).layoutPriority(1)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Review configuration before previewing", systemImage: "exclamationmark.triangle.fill").font(.headline)
                        ValidationSummary()
                    }.padding(20)
                }
            }
        }
        .padding(24)
        .onChange(of: selected) { _, _ in revision = UUID() }
        .onChange(of: deferrals) { _, _ in revision = UUID() }
    }
}
private struct PopupHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 720
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let measured = nextValue()
        if measured.isFinite && measured > 0 { value = measured }
    }
}
struct StudioPreview: View {
    @EnvironmentObject private var store: AdminStore
    @StateObject private var ctx: UIContext
    @State private var showButtonChecks = false
    @State private var measuredHeight: CGFloat = 720
    let logoData: Data?
    let chooseLogo: () -> Void
    init(state: UIState, yaml: String, progress: Double, deferrals: Int, logoData: Data?, chooseLogo: @escaping () -> Void, appNotices: [AppUpdateNotice]? = nil, entraNotice: EntraNotice? = nil, informationalToastMessage: String? = nil, recoveryNotice: RecoveryNotice? = nil) {
        self.logoData = logoData
        self.chooseLogo = chooseLogo
        var config = UIConfig.fromAdminYAML(yaml)
        config.ui.popupWidth = min(900, max(420, config.ui.popupWidth))
        config.toast.width = min(700, max(300, config.toast.width))
        if informationalToastMessage != nil {config.toast.autoDismissSeconds=30;config.toast.showCloseButton=true}
        let context = UIContext(config: config, state: state, deferralCount: deferrals)
        context.informationalToastMessage=informationalToastMessage
        context.recoveryNotice=recoveryNotice ?? RecoveryNotice.preview()
        if let entraNotice { context.entraNotice = entraNotice }
        if let appNotices { context.appUpdates = appNotices }
        context.downloadProgress = progress
        context.downloadSubtitle = "SIMULATED · Downloading macOS… \(Int(progress * 100))%"
        context.errorMessage = "Preview: The installer could not be verified for the required version."
        context.diskAvailableGB = 8.5; context.diskRequiredGB = 40
        context.uptimeDays = 18; context.uptimeDeferralsRemaining = 2; context.uptimeTimerSeconds = 600
        _ctx = StateObject(wrappedValue: context)
    }
    private var cardWidth: CGFloat { CGFloat([UIState.toast, .appUpdates].contains(ctx.state) ? ctx.config.toast.width : ctx.config.ui.popupWidth) }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { canvas in
                let layout = PreviewSizing(cardWidth: Double(cardWidth), viewportWidth: Double(canvas.size.width), contentHeight: Double(measuredHeight))
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: 0)
                        popup
                            .environmentObject(ctx)
                            .environment(\.popupPreviewLogoData, logoData)
                            .environment(\.popupPreviewLogoAction, chooseLogo)
                            .frame(width: CGFloat(layout.cardWidth))
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { measured in
                                Color.clear.preference(key: PopupHeightKey.self, value: measured.size.height)
                            })
                            .scaleEffect(CGFloat(layout.scale), anchor: .topLeading)
                            .frame(width: CGFloat(layout.scaledWidth), height: CGFloat(layout.scaledHeight), alignment: .topLeading)
                        Spacer(minLength: 0)
                    }
                    .frame(width: max(1, canvas.size.width - 40), alignment: .top)
                    .padding(20)
                }
                .frame(width: max(1, canvas.size.width), height: max(1, canvas.size.height))
                .onPreferenceChange(PopupHeightKey.self) { height in
                    if height.isFinite && height > 0 && abs(height - measuredHeight) > 0.5 { measuredHeight = height }
                }
            }
            Divider()
            ButtonChecksPanel(expanded:$showButtonChecks)
            Label(ctx.demoAction, systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).fixedSize(horizontal: false, vertical: true)
        }
        .background {
            ZStack {
                Color.primary.opacity(0.025)
                LinearGradient(colors:[Color.blue.opacity(0.15),Color.purple.opacity(0.12),Color.orange.opacity(0.09)],startPoint:.topLeading,endPoint:.bottomTrailing)
            }
        }
        .onAppear { ctx.onPreviewAction = { state, action, code, automatic in if ctx.informationalToastMessage == nil {store.recordButtonCheck(state:state,action:action,code:code,automatic:automatic)} } }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
    }
    @ViewBuilder private var popup: some View {
        switch ctx.state {
        case .updateRecovery: UpdateRecoveryView()
        case .softNudge: SoftNudgeView()
        case .hardBlock: HardBlockView()
        case .toast: ToastView()
        case .appUpdates: AppUpdatesToast()
        case .entraRegistration: EntraRegistrationView()
        case .downloading: DownloadView()
        case .installing: InstallingView()
        case .rebooting: RebootingView()
        case .preflightPower: PowerWaitView()
        case .preflightDisk: DiskSpaceView()
        case .compliant: CompliantView()
        case .error: ErrorView()
        case .rebootNudge: RebootNudgeView()
        case .rebootForce: RebootForceView()
        case .passwordPrompt: Text("End-user password collection is disabled.")
        }
    }
}
struct DeploymentPage:View {
    @EnvironmentObject var store:AdminStore
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:24){
            PageHeading(eyebrow:"Deployment",title:"From draft to managed policy.",subtitle:"Export for your fleet, or apply to a test Mac first. This companion never starts a macOS installer.")
            ValidationSummary()
            SetupAdvisorCard()
            DeploymentExportCard()
            AdminCard {
                Label("1 · Export for Jamf or another deployment tool",systemImage:"square.and.arrow.up").font(.headline)
                Text("Save config.yaml with your complete policy. Existing unknown settings are preserved; known plaintext credential values are excluded. Distribute the file to /Library/Management/PUSH/config.yaml using your normal management workflow.").font(.callout).foregroundStyle(.secondary)
                Button("Export config.yaml"){store.exportDocument()}.buttonStyle(.borderedProminent).disabled(!store.document.problems.isEmpty)
            }
            AdminCard {
                Label("2 · Apply to this Mac",systemImage:"desktopcomputer").font(.headline)
                Text("Creates a backup of the installed YAML before replacing it. Administrator authorization is requested only when you choose Apply. If a schedule is active, its future checks will use the new policy.").font(.callout).foregroundStyle(.secondary)
                HStack{Text("Installed PUSH: " + store.pushVersion).font(.caption).foregroundStyle(.secondary);Spacer();Button("Apply configuration…"){store.confirmApply()}.disabled(!store.pushInstalled || !store.document.problems.isEmpty)}
            }
            AdminCard {
                Label("3 · Enable automatic monitoring",systemImage:"calendar.badge.clock").font(.headline)
                Text("Check every five minutes after applying your policy; toast timing remains hourly. Dry-run policies only log; live policies can notify users and install according to your settings. The first check runs immediately.").font(.callout).foregroundStyle(.secondary)
                Label(store.schedulePresent ? "Schedule definition is installed" : "No schedule definition found",systemImage:store.schedulePresent ? "clock.badge.checkmark":"pause.circle").font(.callout)
                HStack{Button("Enable monitoring…"){store.changeSchedule(enable:true)}.disabled(!store.pushInstalled);Button("Pause schedule…"){store.changeSchedule(enable:false)}.disabled(!store.pushInstalled)}
            }
            AdminCard {
                Label("Unattended authorization",systemImage:"lock.shield").font(.headline)
                Text("Configure management enrollment and IT-managed authorization before attempting real upgrades. The companion does not collect users’ login passwords, store API secrets, or change Keychain access. A catalog result is not proof that a Mac is enrolled or authorized to upgrade.").font(.callout).foregroundStyle(.secondary)
            }
        }.padding(30)}
    }
}
