// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
import Combine

struct MajorUpgradeDemoView:View {
    @State private var simulation:MajorUpgradeSimulation
    @State private var lastTick=Date()
    let presentation:PopupPresentation
    @State private var controlsExpanded=false
    let embedded:Bool
    let logoData:Data?
    let onHide:()->Void
    let onReady:()->Void
    private let tick=Timer.publish(every:0.2,on:.main,in:.common).autoconnect()
    init(options:MajorUpgradeDemoOptions = .sample,embedded:Bool=false,presentation:PopupPresentation=PopupPresentation(),logoData:Data?=nil,onHide:@escaping ()->Void={},onReady:@escaping ()->Void={}) {
        _simulation=State(initialValue:MajorUpgradeSimulation(options:options));self.embedded=embedded;self.presentation=presentation;self.logoData=logoData;self.onHide=onHide;self.onReady=onReady
    }
    private var active:Bool {simulation.isWorking}
    private var title:String {
        switch simulation.phase {case .offer:return "Try the next macOS";case .downloading:return "Downloading macOS";case .preparing:return "Preparing your upgrade";case .restartReady:return "Ready to restart";case .finished:return "Demo complete";case .declined:return "Maybe another time";case .failed:return "Let’s try that again"}
    }
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:12) {
                Group {if let logoData,let image=NSImage(data:logoData){Image(nsImage:image).resizable().scaledToFit()}else{Image(systemName:"arrow.up.square.fill").resizable().foregroundStyle(.blue,.purple)}}.frame(width:34,height:34)
                VStack(alignment:.leading,spacing:2){Text("PUSH").font(.headline);Text("by Sebastian Santos").font(.caption2).foregroundStyle(.secondary)}
                Spacer();Text("Optional major upgrade").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal,26).padding(.vertical,20)
            Divider()
            VStack(spacing:20) {
                Label("DEBUG · SIMULATION ONLY",systemImage:"testtube.2").font(.caption.bold()).foregroundStyle(.blue).padding(.horizontal,12).padding(.vertical,7).background(.blue.opacity(0.09)).clipShape(Capsule())
                Group {
                    if simulation.phase == .offer {hero.frame(height:105)}
                    else if simulation.phase == .restartReady || simulation.phase == .finished {Image(systemName:simulation.phase == .finished ? "checkmark.circle.fill":"arrow.clockwise.circle.fill").font(.system(size:66)).foregroundStyle(.green)}
                    else if simulation.phase == .failed {Image(systemName:"wifi.exclamationmark").font(.system(size:52)).foregroundStyle(.orange)}
                }
                Text(title).font(.system(size:29,weight:.bold,design:.rounded)).multilineTextAlignment(.center)
                PopupGreetingBanner(presentation:presentation)
                content
                if simulation.phase == .offer || simulation.phase == .declined {versionComparison}
                buttons
                Text(simulation.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            }.padding(26)
            Divider()
            DisclosureGroup("Debug controls",isExpanded:$controlsExpanded){debugControls}.padding(.horizontal,20).padding(.vertical,14).background(Color.blue.opacity(0.035))
        }.frame(maxWidth:.infinity).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius:20))
        .onReceive(tick){now in let elapsed=now.timeIntervalSince(lastTick);lastTick=now;simulation.advance(seconds:elapsed)}
        .onChange(of:simulation.phase){_,phase in if phase == .restartReady {onReady()}}
    }
    private var hero:some View {
        ZStack {
            RoundedRectangle(cornerRadius:16).fill(LinearGradient(colors:[.cyan.opacity(0.2),.indigo.opacity(0.25),.purple.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing))
            Image(systemName:"mountain.2.fill").font(.system(size:82)).foregroundStyle(LinearGradient(colors:[.cyan,.blue,.purple],startPoint:.leading,endPoint:.trailing))
        }
    }
    @ViewBuilder private var content:some View {
        switch simulation.phase {
        case .offer:
            Text("Your IT team is inviting you to test the next major version of macOS.").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment:.leading,spacing:12){Label("Your files and apps stay in place",systemImage:"folder");Label("A restart is required to finish",systemImage:"restart")}.font(.callout).frame(maxWidth:.infinity,alignment:.leading)
        case .downloading,.preparing:
            Text(simulation.phase == .downloading ? "You can keep working while the example download finishes.":"Checking and preparing the example upgrade. Nothing is being installed.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("\(Int(simulation.progress*100))%").font(.system(size:42,weight:.semibold,design:.rounded)).monospacedDigit()
            ProgressView(value:simulation.progress).tint(.blue)
            Text("SIMULATED PROGRESS · No network transfer or installer activity").font(.caption2).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:15){step("Downloading",icon:"arrow.down.circle.fill",done:simulation.phase == .preparing);step("Preparing",icon:"shippingbox.fill",done:false);step("Restart when ready",icon:"restart.circle",done:false)}.frame(maxWidth:.infinity,alignment:.leading)
        case .restartReady:
            Text("Save your work. In a live upgrade, a restart would finish installation.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment:.leading,spacing:16){Label("Example download complete",systemImage:"checkmark.circle.fill");Label("Example preparation complete",systemImage:"checkmark.circle.fill")}.foregroundStyle(.green).frame(maxWidth:.infinity,alignment:.leading).padding(18).background(.green.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:14))
        case .finished:
            Text("You completed the example flow. No download, installation or restart happened.").foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .declined:
            Text("The optional offer was declined in this session only. No deferral was saved.").foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .failed:
            Text("Example failure. A real workflow would explain the blocker and recheck readiness before retrying. This demo cannot request a password or bypass authorization.").foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
    private func step(_ title:String,icon:String,done:Bool)->some View {Label(title,systemImage:done ? "checkmark.circle.fill":icon).font(.callout.weight(.medium)).foregroundStyle(done ? Color.green:Color.secondary)}
    private var versionComparison:some View {
        HStack {VStack(alignment:.leading,spacing:4){Text("CURRENT · EXAMPLE").font(.caption2).foregroundStyle(.secondary);Text("macOS "+simulation.options.current).font(.headline)};Spacer();Image(systemName:"arrow.right").foregroundStyle(.secondary);Spacer();VStack(alignment:.leading,spacing:4){Text("AVAILABLE · EXAMPLE").font(.caption2).foregroundStyle(.secondary);Text("macOS "+simulation.options.target).font(.headline).foregroundStyle(.blue)}}.padding(18).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:14))
    }
    @ViewBuilder private var buttons:some View {
        switch simulation.phase {
        case .offer:
            HStack {Button("Not now"){simulation.notNow()}.frame(maxWidth:.infinity);Button("Update"){lastTick=Date();simulation.chooseUpdate()}.buttonStyle(.borderedProminent).frame(maxWidth:.infinity)}.controlSize(.large)
        case .downloading,.preparing:
            Button(embedded ? "Keep working (simulated)":"Keep working"){simulation.keepWorking();if !embedded {onHide()}}.controlSize(.large)
            if !embedded {Text("Reopen this example from the temporary PUSH Demo menu.").font(.caption2).foregroundStyle(.secondary)}
        case .restartReady:
            HStack {Button("Later"){simulation.restartLater();if !embedded {onHide()}}.frame(maxWidth:.infinity);Button("Restart now"){simulation.restartNow()}.buttonStyle(.borderedProminent).frame(maxWidth:.infinity)}.controlSize(.large)
        case .failed:
            Button("Retry demo"){simulation.reset();lastTick=Date();simulation.chooseUpdate()}.buttonStyle(.borderedProminent).controlSize(.large)
        case .finished,.declined:
            Button("Replay demo"){simulation.reset()}.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }
    private var debugControls:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {Button("Reset demo"){simulation.reset()};Button("Skip stage"){simulation.skipStage()}.disabled(!active);Button(simulation.paused ? "Resume":"Pause"){simulation.togglePause()}.disabled(!active)}.font(.caption)
            Menu("Simulate a problem") {Button("Network unavailable"){simulation.fail("The network is unavailable.")};Button("Not enough disk space"){simulation.fail("There is not enough free disk space.")};Button("IT authorization missing"){simulation.fail("Unattended authorization is missing; IT must configure it.")}}.disabled(!active).font(.caption)
            Text("Example versions and progress. No live checks, saved policy changes or system actions.").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
