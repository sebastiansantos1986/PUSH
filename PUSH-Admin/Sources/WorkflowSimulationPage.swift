// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import Combine

struct WorkflowSimulationPage:View {
    var embedded=false
    @EnvironmentObject var store:AdminStore
    @State private var simulation=PopupSimulation()
    @State private var allPopups=false
    @State private var revision=UUID()
    private let tick=Timer.publish(every:1,on:.main,in:.common).autoconnect()
    private var recipe:WorkflowRecipe {WorkflowRecipe.from(document:store.document)}
    private var sample:WorkflowPreviewSample {WorkflowPreviewSample.make(document:store.document,recipe:recipe,currentMajor:ProcessInfo.processInfo.operatingSystemVersion.majorVersion)}
    private var stageTitle:String {simulation.stage=="authorization" ? "Authorization — safe explanation":simulation.stage=="unsupportedHardware" ? "Unsupported hardware":UIState.from(simulation.stage).windowTitle}
    var body:some View {
        Group {
            if embedded {content} else {ScrollView {content.padding(28).frame(maxWidth:1200,alignment:.leading)}}
        }
        .onReceive(tick){_ in simulation.tick(1)}
        .onDisappear {simulation.pause()}
    }
    private var content:some View {
        VStack(alignment:.leading,spacing:18) {
            PageHeading(eyebrow:"Simulation only",title:"See the whole user experience.",subtitle:"Uses the real SwiftUI popup components with example device data. No installer, live request, Keychain access, Self Service action or restart is performed.")
            AdminCard {
                HStack {
                    Toggle("Include every popup and problem screen",isOn:$allPopups).onChange(of:allPopups){_,value in simulation=PopupSimulation(stages:value ? PopupSimulation.allStages:PopupSimulation.updateStages);revision=UUID()}
                    Spacer()
                    Text("\(simulation.index+1) / \(simulation.stages.count)").monospacedDigit()
                }
                Picker("Screen",selection:Binding(get:{simulation.stage},set:{simulation.pause();simulation.select($0)})){ForEach(simulation.stages,id:\.self){Text($0=="authorization" ? "Authorization (safe example)":$0=="unsupportedHardware" ? "Unsupported hardware":UIState.from($0).windowTitle).tag($0)}}
                HStack {
                    Button("Previous"){simulation.pause();simulation.previous()}.disabled(simulation.index==0)
                    Button(simulation.running ? "Pause tour":"Play tour"){if simulation.running {simulation.pause()}else{simulation.play()}}
                    Button("Next screen"){simulation.next()}
                    Button("Reset"){simulation.reset();revision=UUID()}
                }
                Text("Each screen stays for eight seconds during playback. Choosing a button pauses the tour to show its simulated response; it never starts the next real-world action. Choose Next screen to continue manually.").font(.caption).foregroundStyle(.secondary)
            }
            Text(stageTitle).font(.title2.bold())
            if simulation.stage=="authorization" {authorizationExample}
            else if simulation.stage=="unsupportedHardware" {
                StandaloneNoticeView(notice:AppleHardwareResult(state:.unsupported,targetMajor:Int(UIConfig.fromAdminYAML(sample.yaml).update.targetVersion.split(separator:".").first ?? "26"),model:"Example unsupported Mac",reason:"SIMULATED: this example Mac is not supported for the selected macOS generation. IT would review it for replacement; no hardware scan or upgrade was run.",checkedAt:Date()).notice(debug:true)){code in simulation.response(code,automatic:false)}.id(revision).frame(maxWidth:580)
            }else {
                StudioPreview(state:UIState.from(simulation.stage),yaml:sample.yaml,progress:simulation.progress,deferrals:0,logoData:store.document.logoImageData,chooseLogo:{store.choosePopupLogo()},appNotices:store.document.appPreviewNotices(),entraNotice:store.document.entraPreviewNotice(stage:1),sampleCurrentVersion:simulation.stage=="compliant" ? UIConfig.fromAdminYAML(sample.yaml).update.targetVersion:sample.currentVersion,forcedPreview:simulation.stage=="hardBlock",simulationAction:{state,code,automatic in guard state==simulation.stage,let code else{return};simulation.response(code,automatic:automatic)})
                    .id(simulation.stage+revision.uuidString+store.document.setupFingerprint).frame(height:["toast","appUpdates"].contains(simulation.stage) ? 560:800)
            }
            Text(simulation.message).font(.callout).foregroundStyle(.blue).fixedSize(horizontal:false,vertical:true)
            Text("Versions and progress are examples, not a live eligibility result. The authorization screen is a safe stand-in for the real local dialog; no password can be entered here. Icon and copy edits remain saved in your draft; playback and response state stay in memory.").font(.caption).foregroundStyle(.secondary)
            if !embedded {DisclosureGroup("Edit the workflow icon and messages"){WorkflowMessageEditor()}}
        }
    }
    private var authorizationExample:some View {
        AdminCard {
            Label("Authorize the macOS update — simulated",systemImage:"lock.shield.fill").font(.title3.bold())
            Text("PUSH checks its existing Keychain authorization. If a valid saved password is unavailable, the real installation flow asks the logged-in user and saves verified credentials with their consent. Managed authorization uses the configured IT route instead.")
            Text("••••••••  Example only — no input field").font(.system(.body,design:.monospaced)).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:6))
            HStack {Button("Simulate Cancel"){simulation.response(2,automatic:false)};Button("Simulate authorization accepted"){simulation.response(0,automatic:false)}.buttonStyle(.borderedProminent)}
            Text("This does not read or save a real password, unlock Keychain or authorize an installer.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
