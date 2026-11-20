// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum WorkflowQuestion:String,CaseIterable,Identifiable {
    case goal,timing,enforcement,authorization,reminders,hardware,apps,registration,restart,wallpaper,branding,messages,delivery
    var id:String {rawValue}
    var title:String {switch self {
    case .goal:return "What should these Macs run?"
    case .timing:return "When should the work be done?"
    case .enforcement:return "What happens if the deadline is missed?"
    case .authorization:return "How should PUSH authorize an update?"
    case .reminders:return "How should users be reminded?"
    case .hardware:return "Do you need a replacement-review list?"
    case .apps:return "Which apps should PUSH manage?"
    case .registration:return "Where should users register?"
    case .restart:return "When should users restart?"
    case .wallpaper:return "What background should users see?"
    case .branding:return "Which icon should users recognize?"
    case .messages:return "What should the popups say?"
    case .delivery:return "Should the workflow start after installation?"
    }}
    var help:String {switch self {
    case .goal:return "Choose your goal. PUSH turns this into the version policy and checks eligibility on each endpoint."
    case .timing:return "Pick a date for a campaign, or allow a number of days for each new update."
    case .enforcement:return "A required installation still needs power, space, a supported installer and valid authorization."
    case .authorization:return "Keep PUSH's existing Keychain behavior, or use authorization your IT team has already configured."
    case .reminders:return "Start with hourly reminders. You can limit interruptions if your team needs that."
    case .hardware:return "For Tahoe, include inventory that separates supported Macs, replacement review and unverified hardware."
    case .apps:return "Only selected apps are managed. Open apps remain running."
    case .registration:return "Use your existing Self Service registration policy. PUSH does not invent server settings."
    case .restart:return "Choose an uptime reminder and escalation period. Live enforcement requires the matching signed client."
    case .wallpaper:return "Images you choose are included in the package. Compliance uses the macOS goal."
    case .branding:return "Choose the standard icon, a system symbol or your own image. Add an optional organization and support contact."
    case .messages:return "Start with professional wording tailored to this workflow, then edit it to match your organization."
    case .delivery:return "A paused package is for testing. A live package starts selected checks after future installation. Building itself does not run them."
    }}
}
struct WorkflowSolution:Identifiable {
    let id:String,title:String,detail:String,action:String
    let question:WorkflowQuestion
}
enum WorkflowGuide {
    static func questions(for recipe:WorkflowRecipe)->[WorkflowQuestion] {
        var q:[WorkflowQuestion]=[]
        if recipe.isOSWorkflow {q.append(.goal)}
        if recipe.isOSWorkflow || recipe.tasks.contains(.apps) {q.append(.timing)}
        if recipe.isOSWorkflow && recipe.hasDeadline {q.append(.enforcement)}
        if recipe.isOSWorkflow {q += [.authorization,.reminders]}
        if recipe.isOSWorkflow && recipe.target == .major && recipe.major==26 {q.append(.hardware)}
        if recipe.tasks.contains(.apps) {q.append(.apps)}
        if recipe.tasks.contains(.registration) {q.append(.registration)}
        if recipe.tasks.contains(.restart) {q.append(.restart)}
        if recipe.tasks.contains(.wallpaper) {q.append(.wallpaper)}
        if !recipe.tasks.isEmpty {q.append(.branding);if recipe.isOSWorkflow {q.append(.messages)};q.append(.delivery)}
        return q
    }
    static func solutions(for recipe:WorkflowRecipe,mistOnAdmin:Bool?,providerOnAdmin:Bool?,now:Date=Date())->[WorkflowSolution] {
        var out:[WorkflowSolution]=[]
        if (recipe.isOSWorkflow || recipe.tasks.contains(.apps)) && recipe.hasDeadline && recipe.deadline<=now {
            out.append(.init(id:"past-deadline",title:"Choose a future deadline",detail:"The saved date has passed. A live package could enforce immediately after installation. Review the date before building.",action:"Choose a date",question:.timing))
        }
        if recipe.isOSWorkflow && recipe.target == .latest {
            out.append(.init(id:"major-choice",title:"This goal permits major upgrades",detail:"If you only want routine updates, stay within each Mac's current generation. Change the goal only if that matches your intention.",action:"Review the goal",question:.goal))
        }
        if recipe.isOSWorkflow && recipe.target == .major && recipe.major==26 && !recipe.includeTahoeAudit {
            out.append(.init(id:"tahoe-audit",title:"Identify Macs that cannot run Tahoe",detail:"You can include the reporting helper in this installer, or export an audit-only package first. Unverified hardware remains separate from replacement review.",action:"Choose inventory reporting",question:.hardware))
        }
        if recipe.isOSWorkflow && mistOnAdmin != true {
            out.append(.init(id:"mist-local",title:"Review full-installer discovery",detail:"Mist is missing or not yet verified on this Admin Mac. That does not tell us whether fleet Macs have it. Native Apple discovery may be sufficient; hidden major upgrades can need your approved Mist deployment.",action:"Review the update goal",question:.goal))
        }
        if recipe.tasks.contains(.apps) && providerOnAdmin != true {
            out.append(.init(id:"provider-local",title:"Check the approved app-update provider",detail:"The provider is missing or unverified on this Admin Mac. Deploy and verify your approved provider on the target Macs before app updates run; local evidence cannot certify the fleet.",action:"Review app prerequisites",question:.apps))
        }
        if recipe.isOSWorkflow && recipe.enforceAfterDeadline && recipe.authorization == .userKeychain {
            out.append(.init(id:"first-authorization",title:"Plan for first-time authorization",detail:"PUSH reuses its existing valid Keychain password. Users without a valid saved password must authorize when asked; a deadline alone cannot bypass that. Managed authorization is an alternative if your IT team has provisioned it.",action:"Review authorization",question:.authorization))
        }
        if !recipe.tasks.isEmpty && !recipe.startAfterInstall {
            out.append(.init(id:"paused",title:"This package will stay paused",detail:"It will not send scheduled reminders after installation. Keep that for testing, or choose live monitoring when ready for your pilot.",action:"Choose deployment mode",question:.delivery))
        }
        return out
    }
    // Recommendations are small, explicit draft choices. They never touch
    // passwords, installed settings or other answers such as a fixed deadline.
    static func recommend(_ question:WorkflowQuestion,in recipe:WorkflowRecipe)->WorkflowRecipe {
        var next=recipe
        switch question {
        case .reminders:next.hourlyReminders=true
        case .authorization:next.authorization = .userKeychain
        case .hardware:if recipe.isOSWorkflow && recipe.target == .major && recipe.major==26 {next.includeTahoeAudit=true}
        case .delivery:next.startAfterInstall=false
        default:break
        }
        return next
    }
}
