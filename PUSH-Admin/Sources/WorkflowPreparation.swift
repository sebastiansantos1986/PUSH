// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum WorkflowStep:Int,CaseIterable,Identifiable {
    case goal,customize,simulate,readiness,build
    var id:Int {rawValue}
    var title:String {switch self {case .goal:return "Choose goal";case .customize:return "Customize";case .simulate:return "Simulate";case .readiness:return "Check readiness";case .build:return "Build"}}
}
struct WorkflowPreparationItem:Identifiable {
    enum Kind {case ready,attention,pilot}
    let id:String,title:String,detail:String,kind:Kind
}
struct WorkflowPreparation {
    let blockers:[String]
    let items:[WorkflowPreparationItem]
    var canBuild:Bool {blockers.isEmpty}
    var title:String {canBuild ? "Draft can be packaged":"Fix the draft before building"}
    init(recipe:WorkflowRecipe,document:ConfigDocument,now:Date=Date()) {
        let proposal=recipe.proposed(from:document)
        blockers=Array(Set(recipe.issues(now:now)+proposal.problems)).sorted()
        var rows:[WorkflowPreparationItem]=[]
        rows.append(.init(id:"mode",title:recipe.startAfterInstall ? "Live monitoring selected":"Paused package selected",detail:recipe.startAfterInstall ? "Installing this package starts selected checks after five minutes. Prompts and later installation follow the policy.":"After installation, scheduled reminders and updates stay paused. Choose live monitoring in Customize when ready for a pilot.",kind:recipe.startAfterInstall ? .ready:.attention))
        if recipe.isOSWorkflow {
            rows.append(.init(id:"wording",title:"User communication",detail:proposal.setupValue("toast.message").isEmpty ? "The small reminder uses the client default. Customize lets you write a message or apply the suggested wording beside its preview.":"Your custom small-reminder message and selected icon are included in the configured package. Review every message in Simulate.",kind:proposal.setupValue("toast.message").isEmpty ? .attention:.ready))
            rows.append(.init(id:"authorization",title:"Verify authorization on a pilot Mac",detail:recipe.authorization == .userKeychain ? "Existing valid Keychain credentials are reused. A user without valid saved credentials must authorize; the deadline cannot bypass that requirement.":"Provision and test the configured managed authorization on target Macs. No password is embedded in this installer.",kind:.pilot))
            rows.append(.init(id:"hardware",title:"Check target Mac eligibility",detail:recipe.includeTahoeAudit ? "The Tahoe reporting helper and inventory script are included. Collect results on fleet Macs to identify unsupported hardware; unknown results need review.":"Each target Mac must support the selected macOS and have sufficient power, space and an available installer. A preview cannot prove eligibility.",kind:.pilot))
            rows.append(.init(id:"discovery",title:"Verify update discovery",detail:"Same-generation updates use an eligible Apple Software Update offer meeting the minimum target. A move to a newer macOS generation uses a full installer. If no suitable native point update is offered, PUSH waits instead of automatically fetching a full image. Verify discovery on a pilot; major upgrades may need your approved Mist deployment.",kind:.pilot))
        }
        if recipe.tasks.contains(.apps) {rows.append(.init(id:"apps",title:"Verify the approved app provider",detail:"Deploy and verify your protected Installomator provider on target Macs. Open applications remain running.",kind:.pilot))}
        if recipe.tasks.contains(.registration) {rows.append(.init(id:"entra",title:"Test registration on an enrolled Mac",detail:"Confirm the configured Self Service policy exists and local registration evidence is detected. A local result does not assess cloud compliance.",kind:.pilot))}
        if recipe.tasks.contains(.restart) {rows.append(.init(id:"restart",title:"Select a production-signed client in Build",detail:"Live restart enforcement requires the verified client and matching management approval. An ad-hoc local client cannot provide that approval.",kind:.pilot))}
        rows.append(.init(id:"deployment",title:"Validate a managed pilot before rollout",detail:"Install the exported profiles through management and test notification delivery and background monitoring. The Admin application is excluded from employee packages. Local installers are unsigned; production signing must be verified separately.",kind:.pilot))
        items=rows
    }
}
