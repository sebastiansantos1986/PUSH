// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct MajorUpgradePage:View {
    @EnvironmentObject var store:AdminStore
    @State private var options=MajorUpgradeDemoOptions.sample
    @State private var revision=UUID()
    @State private var issue=""
    @State private var hardwareResult:AppleHardwareResult?
    private var presentation:Binding<PopupPresentation>{Binding(get:{store.majorSettings.presentation},set:{var value=store.majorSettings;value.presentation=$0;store.majorSettings=value})}
    private func text(_ key:WritableKeyPath<MajorOfferSettings,String>)->Binding<String> {Binding(get:{store.majorSettings[keyPath:key]},set:{var value=store.majorSettings;value[keyPath:key]=$0;store.majorSettings=value})}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageHeading(eyebrow:"Optional major upgrade · Debug",title:"Personalized, compact and configurable.",subtitle:"Resize the popup, add a banner and greet the logged-in user. The upgrade flow remains a safe simulation.")
                AdminCard {
                    PopupExperienceControls(presentation:presentation)
                    HStack {TextField("Example current version",text:text(\.currentExample));TextField("Example target major",text:text(\.targetExample))}.textFieldStyle(.roundedBorder)
                    Button("Load / reset preview") {do{options=try store.majorSettings.validated().options;revision=UUID();issue=""}catch{issue=error.localizedDescription}}
                    if !issue.isEmpty {Text(issue).foregroundStyle(.orange)}
                    Text("These presentation settings are saved in the draft and packaged as major-offer.json. The standalone app reads only that dedicated presentation file, never the full enforcement YAML.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {Spacer();MajorUpgradeDemoView(options:options,embedded:true,presentation:store.majorSettings.presentation,logoData:store.previewLogoImageData).frame(width:min(720,store.majorSettings.presentation.width)).id(revision);Spacer()}
                AdminCard {
                    Label("Apple hardware compatibility",systemImage:"desktopcomputer.trianglebadge.exclamationmark").font(.headline)
                    Text("Uses Apple's published device lists, matched to local device/board identity. Unknown, missing or stale evidence is not labeled unsupported.").font(.callout).foregroundStyle(.secondary)
                    HStack {Button("Check this Mac (read only)"){hardwareResult=AppleHardwareReader.assessment(target:store.majorSettings.targetExample)};Button("Refresh Apple catalog"){Task{do{_=try await AppleHardwareReader.refresh();hardwareResult=AppleHardwareReader.assessment(target:store.majorSettings.targetExample)}catch{issue=error.localizedDescription}}};Button("Preview unsupported hardware"){hardwareResult = .init(state:.unsupported,targetMajor:AppleHardwareCatalog.major(store.majorSettings.targetExample),model:"Example Mac",reason:"PREVIEW: This example Mac is not listed for the selected major version. No real hardware verdict was made.",checkedAt:Date())}}
                    if let hardwareResult {Text(hardwareResult.state.rawValue.uppercased()+" · "+hardwareResult.model).font(.headline);Text(hardwareResult.reason).font(.callout).foregroundStyle(.secondary);Text("Source: "+hardwareResult.source+" · "+hardwareResult.checkedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary);if hardwareResult.state != .supported {StandaloneNoticeView(notice:hardwareResult.notice(debug:true)){code in issue="Preview response \(code); no system action."}.id(hardwareResult.checkedAt)}}
                }
                Text("Live optional upgrades remain disabled pending installer/auth/progress/restart verification. A presentation package cannot bypass MDM restrictions.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.onAppear {if let configured=try? store.majorSettings.options {options=configured}}
    }
}
