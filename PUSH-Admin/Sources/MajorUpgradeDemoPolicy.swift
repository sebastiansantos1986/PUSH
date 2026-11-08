// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum MajorUpgradeDemoError:LocalizedError {
    case invalid(String)
    var errorDescription:String? {switch self {case .invalid(let message):return message}}
}
struct MajorUpgradeDemoOptions:Equatable,Codable {
    let current:String,target:String,duration:Double
    static let sample=try! Self(current:"26.0",target:"27.0",duration:20)
    init(current:String,target:String,duration:Double)throws {
        func major(_ value:String)->Int? {
            let parts=value.split(separator:".",omittingEmptySubsequences:false)
            guard (1...3).contains(parts.count),parts.allSatisfy({!$0.isEmpty && $0.utf8.allSatisfy{(48...57).contains($0)} && Int($0).map{(0...999).contains($0)}==true}),let first=Int(parts[0]),first>0 else{return nil}
            return first
        }
        guard let from=major(current),let to=major(target),to>from else {throw MajorUpgradeDemoError.invalid("Use example numeric versions with a newer MAJOR target, such as --from 26.0 --to 27.0. Minor updates and downgrades are not offered.")}
        guard duration.isFinite,(8...180).contains(duration) else {throw MajorUpgradeDemoError.invalid("Demo duration must be 8–180 seconds.")}
        self.current=current;self.target=target;self.duration=duration
    }
    static func parse(_ arguments:[String],requireExplicitDebug:Bool=true,defaults:MajorUpgradeDemoOptions = .sample)throws->Self {
        var current=defaults.current,target=defaults.target,duration=defaults.duration,debug=false,seen=Set<String>(),index=0
        while index<arguments.count {
            let key=arguments[index]
            guard seen.insert(key).inserted else {throw MajorUpgradeDemoError.invalid("Duplicate option: "+key)}
            if key=="--debug" {debug=true;index+=1;continue}
            guard ["--from","--to","--duration"].contains(key),index+1<arguments.count else {throw MajorUpgradeDemoError.invalid("Debug-only command. Supported options: --debug --from <version> --to <major version> --duration <seconds>. No live or install option exists.")}
            let value=arguments[index+1]
            switch key {case "--from":current=value;case "--to":target=value;default:guard let number=Double(value) else {throw MajorUpgradeDemoError.invalid("Use a numeric demo duration.")};duration=number}
            index+=2
        }
        guard debug || !requireExplicitDebug else {throw MajorUpgradeDemoError.invalid("Live major offers are not enabled. Add --debug to open the safe simulation. No download, installation or restart will run.")}
        return try .init(current:current,target:target,duration:duration)
    }
    var launchArguments:[String] {["--debug","--from",current,"--to",target,"--duration",String(duration)]}
}
enum MajorUpgradeDemoPhase:String {case offer,downloading,preparing,restartReady,finished,declined,failed}
struct MajorUpgradeSimulation {
    let options:MajorUpgradeDemoOptions
    private(set) var phase:MajorUpgradeDemoPhase = .offer
    private(set) var progress:Double=0
    private(set) var message="Choose Update to play the simulation."
    private(set) var paused=false
    private var elapsed:Double=0
    var isWorking:Bool {phase == .downloading || phase == .preparing}
    init(options:MajorUpgradeDemoOptions = .sample){self.options=options}
    mutating func chooseUpdate() {
        guard phase == .offer else{return};phase = .downloading;elapsed=0;progress=0;paused=false;message="SIMULATED: Update selected. No installation request was sent."
    }
    mutating func notNow() {guard phase == .offer else{return};phase = .declined;message="SIMULATED: Not now selected. No deferral or preference was saved."}
    mutating func advance(seconds:Double) {
        guard isWorking,!paused,seconds.isFinite,seconds>0 else{return}
        elapsed+=min(seconds,180)
        let download=options.duration*0.65,prepare=options.duration*0.35
        if phase == .downloading {
            if elapsed<download {progress=min(1,elapsed/download);return}
            elapsed-=download;phase = .preparing;progress=0;message="SIMULATED: Download complete. Preparing the example upgrade."
        }
        if phase == .preparing {
            progress=min(1,elapsed/prepare)
            if elapsed>=prepare {phase = .restartReady;progress=1;paused=false;message="SIMULATED: Ready to restart. No restart is scheduled."}
        }
    }
    mutating func skipStage() {
        guard isWorking else{return}
        phase = phase == .downloading ? .preparing:.restartReady;elapsed=0;progress=phase == .restartReady ? 1:0;paused=false
        message=phase == .restartReady ? "SIMULATED: Ready to restart. No restart is scheduled.":"SIMULATED: Download skipped; preparation preview."
    }
    mutating func togglePause(){guard isWorking else{return};paused.toggle()}
    mutating func keepWorking(){guard isWorking else{return};message="SIMULATED: Progress continues in this demo only."}
    mutating func restartLater(){guard phase == .restartReady else{return};message="SIMULATED: Restart postponed. No real schedule was saved."}
    mutating func restartNow(){guard phase == .restartReady else{return};phase = .finished;message="SIMULATED: Restart now selected. Your Mac was not restarted."}
    mutating func fail(_ reason:String){guard isWorking else{return};phase = .failed;paused=false;message="SIMULATED: "+String(reason.prefix(300))+" No system action was taken."}
    mutating func reset(){self=Self(options:options)}
}
