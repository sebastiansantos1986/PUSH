// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI

struct WorkflowAssistantCard:View {
    @EnvironmentObject var store:AdminStore
    @Binding var recipe:WorkflowRecipe
    var navigate:(AdminPage)->Void
    var focusQuestion:()->Void = {}
    var skipPresentationQuestions=false
    @State private var index=0
    private var questions:[WorkflowQuestion] {WorkflowGuide.questions(for:recipe).filter{!skipPresentationQuestions || ($0 != .branding && $0 != .messages)}}
    private var selected:WorkflowQuestion? {questions.isEmpty ? nil:questions[min(index,questions.count-1)]}
    private var solutions:[WorkflowSolution] {WorkflowGuide.solutions(for:recipe,mistOnAdmin:store.mistPath == nil ? nil:true,providerOnAdmin:store.readiness?.providerPresent)}
    private func value<T>(_ path:WritableKeyPath<WorkflowRecipe,T>)->Binding<T> {Binding(get:{recipe[keyPath:path]},set:{recipe[keyPath:path]=$0;if !(recipe.isOSWorkflow && recipe.target == .major && recipe.major==26){recipe.includeTahoeAudit=false}})}
    private func go(_ question:WorkflowQuestion){if let found=questions.firstIndex(of:question){index=found;focusQuestion()}}
    private func choice(_ title:String,_ detail:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action){HStack(alignment:.top,spacing:12){Image(systemName:selected ? "checkmark.circle.fill":"circle").foregroundStyle(selected ? Color.blue:Color.secondary);VStack(alignment:.leading,spacing:5){Text(title).font(.headline);Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)};Spacer(minLength:0)}.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(selected ? Color.blue.opacity(0.08):Color.secondary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            if let question=selected {
                AdminCard {
                    HStack {Label("Setup assistant",systemImage:"sparkles").font(.headline);Spacer();Text("Question \(min(index+1,questions.count)) of \(questions.count)").font(.caption).foregroundStyle(.secondary)}
                    ProgressView(value:Double(min(index+1,questions.count)),total:Double(questions.count))
                    Text(question.title).font(.title2.bold())
                    Text(question.help).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    answer(question)
                    HStack {Button("Previous question"){index=max(0,index-1);focusQuestion()}.disabled(index==0);Spacer();if index<questions.count-1 {Button("Next question"){index+=1;focusQuestion()}.buttonStyle(.borderedProminent)}else{Label("Answers saved — continue to Preview below",systemImage:"checkmark.circle").foregroundStyle(.blue)}}
                }
                if !solutions.isEmpty {
                    AdminCard {
                        Label("Suggestions for your choices",systemImage:"lightbulb").font(.headline)
                        Text("These explain what to do next. Local checks describe this Admin Mac, not the readiness of every endpoint. Nothing is installed or changed automatically.").font(.caption).foregroundStyle(.secondary)
                        ForEach(solutions){item in VStack(alignment:.leading,spacing:7){Text(item.title).font(.subheadline.bold());Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);Button(item.action){go(item.question)}}.padding(.vertical,7)}
                    }
                }
            } else {AdminCard {Text("Choose a task first, then PUSH will ask the relevant questions.")}}
        }.onChange(of:questions){_,_ in index=min(index,max(0,questions.count-1))}
    }
    @ViewBuilder private func answer(_ question:WorkflowQuestion)->some View {
        switch question {
        case .goal:
            choice("Keep the current generation updated","Recommended for routine updates without moving users to a new macOS generation.",selected:recipe.target == .current){recipe.target = .current;recipe.includeTahoeAudit=false}
            choice("Move older Macs to Tahoe 26.x","Use the latest eligible stable Tahoe release, and stay within Tahoe.",selected:recipe.target == .major && recipe.major==26){recipe.target = .major;recipe.major=26}
            choice("Use the latest compatible macOS","Includes major upgrades. Choose this only when you intend to allow them.",selected:recipe.target == .latest){recipe.target = .latest;recipe.includeTahoeAudit=false}
            Picker("Another goal",selection:value(\.target)){ForEach(WorkflowTarget.allCases){Text($0.title).tag($0)}}
            if recipe.target == .major {Picker("Generation",selection:value(\.major)){Text("Tahoe 26.x").tag(26);Text("Sequoia 15.x").tag(15);Text("Sonoma 14.x").tag(14);Text("macOS 27.x").tag(27)}}
            Link("Installer discovery setup (Mist)",destination:URL(string:"https://github.com/ninxsoft/mist-cli")!)
            if recipe.target == .fixed {TextField("Exact version",text:value(\.fixedVersion)).textFieldStyle(.roundedBorder);Button("Choose from the release catalog"){store.document=recipe.proposed(from:store.document);navigate(.catalog)}}
        case .timing:
            Picker("Deadline",selection:value(\.hasDeadline)){Text("A specific date and time").tag(true);Text("Days after each update is found").tag(false)}
            if recipe.hasDeadline {
                Picker("Time zone",selection:value(\.timeZoneID)){ForEach(Array(Set([TimeZone.current.identifier,recipe.timeZoneID,"America/Chicago","America/New_York","America/Denver","America/Los_Angeles","Europe/London","UTC"])).sorted(),id:\.self){Text(TimeZone(identifier:$0)?.localizedName(for:.generic,locale:.current) ?? $0).tag($0)}}
                DatePicker("Deadline",selection:value(\.deadline),displayedComponents:[.date,.hourAndMinute]).environment(\.timeZone,TimeZone(identifier:recipe.timeZoneID) ?? .current)
                Text(recipe.deadlineText).font(.callout.weight(.semibold))
            }else{Stepper("Allow \(recipe.graceDays) days",value:value(\.graceDays),in:1...365)}
        case .enforcement:
            choice("Require installation after the deadline","PUSH starts the required workflow when authorization and safety checks pass. A saved password or managed authorization is still needed.",selected:recipe.enforceAfterDeadline){recipe.enforceAfterDeadline=true}
            choice("Continue reminders","Users can choose to update; PUSH does not start an automatic deadline installation.",selected:!recipe.enforceAfterDeadline){recipe.enforceAfterDeadline=false}
        case .authorization:
            choice("Use PUSH's existing user Keychain — recommended","Reuse a valid saved password. Ask and save securely with user consent when the password is missing or invalid.",selected:recipe.authorization == .userKeychain){recipe=WorkflowGuide.recommend(.authorization,in:recipe)}
            choice("Use existing IT-managed authorization","Keep your provisioned managed account/System Keychain or LAPS route. This tool does not package passwords.",selected:recipe.authorization == .managed){recipe.authorization = .managed}
        case .reminders:
            choice("Hourly small reminders — recommended","Keep the update visible, with a full reminder once a day.",selected:recipe.hourlyReminders){recipe=WorkflowGuide.recommend(.reminders,in:recipe)}
            choice("Daily small reminders","Use a quieter cadence while retaining the daily full reminder.",selected:!recipe.hourlyReminders){recipe.hourlyReminders=false}
            Toggle("Limit reminders to weekday working hours",isOn:value(\.workingHoursOnly))
            Toggle("Wait during meetings",isOn:value(\.skipMeetings))
        case .hardware:
            choice("Include replacement-review inventory — recommended","The reporter goes into this installer. The export includes the Jamf inventory script and grouping instructions.",selected:recipe.includeTahoeAudit){recipe=WorkflowGuide.recommend(.hardware,in:recipe)}
            choice("Leave inventory out","Use this if you already scope only supported Macs through your management system.",selected:!recipe.includeTahoeAudit){recipe.includeTahoeAudit=false}
            Button("Export an audit-only workflow first"){store.exportTahoeAudit()}
            Button("Refresh Apple hardware information"){Task {do{_=try await AppleHardwareReader.refresh();store.notice="Apple hardware information refreshed."}catch{store.notice=error.localizedDescription}}}
        case .apps:
            ForEach(ApprovedApp.catalog){item in Toggle(item.name,isOn:Binding(get:{recipe.approvedApps.contains(item.id)},set:{if $0 {recipe.approvedApps.insert(item.id)}else{recipe.approvedApps.remove(item.id)}}))}
            Toggle("Update closed apps automatically",isOn:value(\.updateClosedApps))
            Text("Your approved Installomator provider must be deployed on target Macs. Open apps are not quit automatically.").font(.caption).foregroundStyle(.secondary)
            Link("Approved app provider setup",destination:URL(string:"https://github.com/Installomator/Installomator")!)
            Button("Open app setup and provider details"){store.document=recipe.proposed(from:store.document);navigate(.apps)}
        case .registration:
            TextField("Your Self Service registration policy number",text:value(\.registrationPolicy)).textFieldStyle(.roundedBorder)
            Button("Open registration setup"){store.document=recipe.proposed(from:store.document);navigate(.entra)}
        case .restart:
            Stepper("First reminder after \(recipe.restartWarningDays) days",value:value(\.restartWarningDays),in:1...365)
            Stepper("Escalate after \(recipe.restartForceDays) days",value:value(\.restartForceDays),in:1...365)
            Text("Review will ask for your matching production-signed client before packaging live restart enforcement.").font(.caption).foregroundStyle(.secondary)
        case .wallpaper:
            Button("Choose the noncompliant background…"){store.chooseWallpaper(role:"noncompliant")}
            Button("Choose the compliant background…"){store.chooseWallpaper(role:"compliant")}
        case .branding:
            PopupLogoControls()
            TextField("Organization name (optional)",text:Binding(get:{store.document.setupValue("ui.orgName")},set:{store.document.edits["ui.orgName"]=$0})).textFieldStyle(.roundedBorder)
            TextField("Support email (optional)",text:Binding(get:{store.document.setupValue("ui.itContactEmail")},set:{store.document.edits["ui.itContactEmail"]=$0})).textFieldStyle(.roundedBorder)
        case .messages:
            WorkflowMessageEditor()
        case .delivery:
            choice("Build a paused package for testing — recommended first","No scheduled reminders or installs begin after installation. Preview and pilot before enabling live policy.",selected:!recipe.startAfterInstall){recipe=WorkflowGuide.recommend(.delivery,in:recipe)}
            choice("Start the selected workflow after installation","Selected checks begin after a five-minute delay. This can show prompts and later install or restart under the reviewed policy.",selected:recipe.startAfterInstall){recipe.startAfterInstall=true}
        }
    }
}
