// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum WorkflowMessage:String,CaseIterable,Identifiable {
    case toast,minor,major,deadline,forced,installing,complete
    var id:String {rawValue}
    var title:String {switch self {case .toast:return "Small reminder";case .minor:return "Full update reminder";case .major:return "Major upgrade reminder";case .deadline:return "Deadline reached";case .forced:return "Required installation";case .installing:return "Installation progress";case .complete:return "Up to date"}}
    var previewState:UIState {switch self {case .toast:return .toast;case .minor,.major:return .softNudge;case .deadline,.forced:return .hardBlock;case .installing:return .installing;case .complete:return .compliant}}
    var key:String {switch self {case .toast:return "toast.message";case .minor:return "ui.minorMessage";case .major:return "ui.majorMessage";case .deadline:return "ui.deadlineMessage";case .forced:return "ui.forcedInstallMessage";case .installing:return "ui.installingMessage";case .complete:return "ui.alreadyUpToDateMessage"}}
}
enum WorkflowWording {
    static func suggested(_ item:WorkflowMessage,recipe:WorkflowRecipe)->String {
        let os=recipe.target == .major ? (recipe.major==26 ? "macOS Tahoe":"macOS \(recipe.major)"):recipe.target == .fixed ? "macOS \(recipe.fixedVersion)":"macOS"
        let f=DateFormatter();f.timeZone=TimeZone(identifier:recipe.timeZoneID);f.dateFormat="EEE, MMM d 'at' h:mm a zzz"
        let due=recipe.hasDeadline ? " by "+f.string(from:recipe.deadline):" within \(recipe.graceDays) days of this update being identified"
        switch item {
        case .toast:return "Please update your Mac to \(os)\(due).\nSave your work and connect to power before you begin."
        case .minor:return "An update to \(os) is required\(due).\n\nBefore you begin:\n- Save your work\n- Connect your Mac to power and the internet\n- Be prepared for a restart\n\nChoose Install Now when you are ready. Contact your IT team if you need assistance."
        case .major:return "Your IT team requires an upgrade to \(os)\(due).\n\nPlease save your work and keep your Mac connected to power and the internet. The installation may take some time and requires a restart.\n\nChoose Begin Upgrade when you are ready. You may be asked to authorize the update with your Mac login password."
        case .deadline:return "This required \(os) update needs your attention.\n\nSave your work and keep your Mac connected to power. Choose Install Now to continue. Installation authorization and safety checks still apply."
        case .forced:return "The required \(os) update is being started under your IT policy.\n\nSave your work and keep your Mac connected to power and the internet. Complete any authorization request that appears. Installation can proceed only after the required checks pass."
        case .installing:return "Your Mac is preparing the \(os) installation.\n\nKeep it powered on and connected to power. It will restart when the installation is ready. If PUSH reports a problem, contact your IT team for assistance."
        case .complete:return "Your Mac meets the required macOS version.\n\nNo further action is needed. Thank you for keeping your Mac up to date."
        }
    }
    static func apply(_ item:WorkflowMessage,recipe:WorkflowRecipe,to document:ConfigDocument)->ConfigDocument {var result=document;result.edits[item.key]=suggested(item,recipe:recipe);return result}
    static func applySet(recipe:WorkflowRecipe,to document:ConfigDocument)->ConfigDocument {
        var result=document
        for item in WorkflowMessage.allCases {result=apply(item,recipe:recipe,to:result)}
        result.edits["ui.appName"]="Software Update Required"
        result.edits["ui.forcedInstallNotice"]="Save your work\nKeep your Mac connected to power and the internet\nComplete any authorization request\nA restart is required to finish"
        return result
    }
}
struct PopupSimulation {
    static let updateStages=["toast","softNudge","preflightPower","authorization","downloading","installing","rebooting","compliant"]
    static let allStages=["toast","softNudge","hardBlock","preflightPower","preflightDisk","authorization","downloading","installing","rebooting","compliant","updateRecovery","error","unsupportedHardware","appUpdates","entraRegistration","rebootNudge","rebootForce"]
    var stages:[String]=updateStages
    private(set) var index=0
    private(set) var elapsed:Double=0
    private(set) var running=false
    private(set) var message="Ready. All actions in this tour are simulated."
    var stage:String {stages.isEmpty ? "compliant":stages[min(index,stages.count-1)]}
    var progress:Double {min(1,max(0,elapsed/8))}
    mutating func play(){running=true}
    mutating func pause(){running=false}
    mutating func reset(){index=0;elapsed=0;running=false;message="Simulation reset. No real action occurred."}
    mutating func select(_ value:String){guard let i=stages.firstIndex(of:value) else{return};index=i;elapsed=0;message="Showing a simulated \(value) stage."}
    mutating func next(){elapsed=0;if index+1<stages.count {index+=1}else{running=false;message="Tour complete. No update, password request or restart was performed."}}
    mutating func previous(){index=max(0,index-1);elapsed=0}
    mutating func tick(_ seconds:Double){guard running,seconds.isFinite,seconds>0 else{return};elapsed+=min(seconds,8);if elapsed>=8{next()}}
    mutating func response(_ code:Int32,automatic:Bool){
        guard [0,1,2,3,4,5,6,7].contains(code) else{return}
        if !automatic {running=false}
        message="SIMULATED: "+(code==0 ? "Install/continue selected. No system action sent.":code==1 ? "Later selected. No real deferral saved.":code==3 ? "Schedule confirmed. No real schedule saved.":code==5 ? "Timeout, not installation consent.":"Response \(code) recorded in this tour only.")
        // Responses are shown truthfully. Navigation/tour playback alone changes stages.
    }
}

struct WorkflowPreviewSample {
    let yaml:String,currentVersion:String
    static func make(document:ConfigDocument,recipe:WorkflowRecipe,currentMajor:Int)->Self {
        var preview=recipe.proposed(from:document)
        let targetMajor=recipe.target == .major ? recipe.major:recipe.target == .fixed ? (Int(recipe.fixedVersion.split(separator:".").first ?? "") ?? currentMajor):currentMajor
        let from=recipe.target == .current ? targetMajor:targetMajor==26 ? 15:max(14,targetMajor-1)
        if preview.setupValue("update.targetVersion").isEmpty {preview.edits["update.targetVersion"]=String(targetMajor)+".0"}
        preview.edits["update.releaseType"]=from<targetMajor ? "major":"minor"
        preview.edits["toast.soundName"]="";preview.edits["toast.autoDismissSeconds"]="0";preview.edits["debug.dryRun"]="true"
        return .init(yaml:preview.yaml,currentVersion:String(from)+".0")
    }
}
