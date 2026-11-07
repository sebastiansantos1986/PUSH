// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

private struct AppReport: Decodable {
    struct Record: Decodable { var installed: String?; var target: String?; var result: String?; var checked: Date?; var deadline: Date? }
    var apps: [String:Record]
}
struct AppsPage: View {
    @EnvironmentObject var store: AdminStore
    @State private var refreshID = UUID()
    private var selected: [String] { AppUpdatePolicy.ids(store.document.value("apps.approved") ?? "") }
    private var report: AppReport? {
        guard let data = FileManager.default.contents(atPath:"/Library/Management/PUSH/apps-state.json") else { return nil }
        return try? JSONDecoder().decode(AppReport.self,from:data)
    }
    private func resolved(_ key: String) -> String {
        if let field = configGroups.flatMap(\.fields).first(where: { $0.id == key }) { return store.document.value(field) }
        return store.document.value(key) ?? ""
    }
    private func value(_ key: String) -> Binding<String> {
        Binding(get:{resolved(key)},set:{store.document.edits[key] = $0})
    }
    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get:{resolved(key) == "true"},set:{store.document.edits[key] = $0 ? "true" : "false"})
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageHeading(eyebrow:"APP MANAGEMENT",title:"Keep approved apps current.",subtitle:"Choose once. Discover vendor releases, remind users, and update apps after they close them.")
                AdminCard {
                    HStack {
                        Label("Approved applications",systemImage:"checkmark.shield").font(.headline)
                        Spacer()
                        Text("\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(ApprovedApp.catalog) { app in
                        HStack(alignment:.top,spacing:14) {
                            Image(systemName:app.id == "vscode" ? "chevron.left.forwardslash.chevron.right" : "globe").font(.title2).foregroundStyle(.blue).frame(width:40,height:40).background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:10))
                            VStack(alignment:.leading,spacing:4) {
                                Text(app.name).font(.headline)
                                Text("Stable release · installed copies only").font(.caption).foregroundStyle(.secondary)
                                if let saved = report?.apps[app.id] {
                                    Text(saved.result ?? "Not checked").font(.caption).foregroundStyle(.secondary)
                                    if let installed = saved.installed, !installed.isEmpty { Text(installed + " → " + (saved.target ?? "Unknown")).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary) }
                                }
                            }
                            Spacer()
                            Toggle("Approve " + app.name,isOn:Binding(get:{selected.contains(app.id)},set:{store.document.approveApp(app.id,enabled:$0)})).labelsHidden().toggleStyle(.switch)
                        }.padding(.vertical,8)
                        if app.id != ApprovedApp.catalog.last?.id { Divider() }
                    }
                    Text("Leave apps managed by another tool unchecked. App Store copies, missing apps, and unverified publisher/channel identities are skipped.").font(.caption).foregroundStyle(.secondary)
                }
                AdminCard {
                    Label("One policy, recurring checks",systemImage:"clock.arrow.circlepath").font(.headline)
                    Toggle("Enable approved app management",isOn:flag("apps.enabled"))
                    Toggle("Show one grouped reminder every hour",isOn:flag("apps.notifyHourly"))
                    Toggle("Automatically update approved apps when closed",isOn:flag("apps.autoUpdateClosed"))
                    HStack {
                        Text("Grace period")
                        Spacer()
                        Stepper("\(Int(value("apps.graceDays").wrappedValue) ?? 7) days",value:Binding(get:{Int(value("apps.graceDays").wrappedValue) ?? 7},set:{value("apps.graceDays").wrappedValue=String($0)}),in:1...365)
                    }
                    TextField("All-app deadline override · optional ISO 8601 timestamp",text:value("apps.deadline")).textFieldStyle(.roundedBorder)
                    DisclosureGroup("Per-app deadline overrides") {
                        VStack(spacing:10) {
                            TextField("Chrome deadline",text:value("apps.chromeDeadline"))
                            TextField("Firefox deadline",text:value("apps.firefoxDeadline"))
                            TextField("VS Code deadline",text:value("apps.vscodeDeadline"))
                        }.textFieldStyle(.roundedBorder).padding(.top,10)
                    }
                    Text("Per-app overrides take priority, then the all-app override, then days from first detection. Overdue reminders do not force an open app to quit. Quiet updates can run before the deadline when enabled.").font(.caption).foregroundStyle(.secondary)
                }
                AdminCard {
                    Label("Preview the user experience",systemImage:"rectangle.on.rectangle").font(.headline)
                    Text("Sample data. Buttons are simulated and never update software.").font(.caption).foregroundStyle(.secondary)
                    StudioPreview(state:.appUpdates,yaml:store.document.yaml,progress:0,deferrals:0,logoData:store.document.logoImageData,chooseLogo:{store.choosePopupLogo()},appNotices:store.document.appPreviewNotices())
                        .id(store.document.yaml).frame(height:560)
                }
                AdminCard {
                    Label("Readiness & saved results",systemImage:"wrench.and.screwdriver").font(.headline)
                    TextField("Installomator script path",text:value("apps.installomatorPath")).textFieldStyle(.roundedBorder)
                    Text(FileManager.default.fileExists(atPath:resolved("apps.installomatorPath")) ? "Script found. The engine verifies administrator ownership and permissions before use." : "Installomator is not installed at this path. Discovery and previews work without it; actual updates require it.").font(.caption).foregroundStyle(.secondary)
                    Link("Installomator stable releases",destination:URL(string:"https://github.com/Installomator/Installomator/releases")!)
                    HStack {
                        Button("Copy check command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("sudo /Library/Management/PUSH/push-cli apps check",forType:.string);store.notice="Copied the read-only app discovery command. Apply your approved app policy first." }
                        Button("Refresh saved results") { refreshID = UUID() }
                    }
                    Text("Apply the draft in Deployment, then enable hourly checks. No commands run from this page. Its results come from the installed engine's saved app report.").font(.caption).foregroundStyle(.secondary)
                }
                ValidationSummary()
            }.padding(28).id(refreshID)
        }
    }
}
