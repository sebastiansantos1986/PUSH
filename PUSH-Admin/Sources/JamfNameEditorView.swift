// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct JamfNameEditorView:View {
    let review:JamfNameReview
    @ObservedObject var model:JamfPublisherModel
    @Environment(\.dismiss) private var dismiss
    @State private var policyNames:[Int:String]
    @State private var groupName:String
    init(review:JamfNameReview,model:JamfPublisherModel){self.review=review;self.model=model;_policyNames=State(initialValue:Dictionary(uniqueKeysWithValues:review.policies.map{($0.id,$0.name)}));_groupName=State(initialValue:review.group.name)}
    private var changes:[String] {
        var result=review.policies.compactMap{item in policyNames[item.id] != item.name ? "Policy \(item.id): \(item.name) → \(policyNames[item.id] ?? "")":nil}
        if groupName != review.group.name {result.append("Group \(review.group.id): \(review.group.name) → \(groupName)")};return result
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text("Edit published Jamf names").font(.title2.bold())
            Text(review.server).font(.callout).foregroundStyle(.secondary)
            Text("Names change on the same Jamf IDs. Policy scope and enabled state, group membership and smart-group criteria are preserved.").font(.callout).fixedSize(horizontal:false,vertical:true)
            ScrollView {VStack(alignment:.leading,spacing:16){
                ForEach(review.policies){item in
                    VStack(alignment:.leading,spacing:6){
                        Text(item.role=="client" ? "PUSH client prerequisite":"macOS "+item.role.replacingOccurrences(of:"macOS-",with:"")+" offer policy").font(.headline)
                        Text("Jamf policy ID \(item.id)").font(.caption).foregroundStyle(.secondary)
                        TextField("Policy name in Jamf",text:Binding(get:{policyNames[item.id] ?? item.name},set:{policyNames[item.id]=$0})).textFieldStyle(.roundedBorder)
                    }
                }
                Divider()
                Text(review.group.role=="smart" ? "Smart computer group":"Static pilot computer group").font(.headline)
                Text("Jamf group ID \(review.group.id)").font(.caption).foregroundStyle(.secondary)
                TextField("Group name in Jamf",text:$groupName).textFieldStyle(.roundedBorder)
                Text("A changed group name requires "+(review.group.role=="smart" ? "Update Smart Computer Groups":"Update Static Computer Groups")+" on your API role.").font(.caption).foregroundStyle(.secondary)
                Button("Use suggested readable names"){
                    for item in review.policies {policyNames[item.id]=item.role=="client" ? "PUSH - Install Client":item.role=="macOS-26" ? "PUSH - macOS Tahoe Upgrade":"PUSH - macOS 27 Upgrade"}
                    groupName="PUSH - Pilot"
                }
                Text("Review your changes").font(.headline)
                if changes.isEmpty {Text("Edit a name above to prepare a rename.").foregroundStyle(.secondary)}
                ForEach(changes,id:\.self){Text($0).font(.callout).fixedSize(horizontal:false,vertical:true)}
                Text("Self Service display titles stay as configured in Jamf Self Service. These fields edit the internal names you see in Jamf Pro.").font(.caption).foregroundStyle(.secondary)
            }}.frame(maxHeight:430)
            if model.busy {ProgressView()}
            Text(model.status).font(.caption).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            HStack{Button("Cancel"){dismiss()}.disabled(model.busy);Spacer();Button("Save reviewed names to Jamf"){model.saveNames(review,policies:policyNames,group:groupName)}.buttonStyle(.borderedProminent).disabled(model.busy || changes.isEmpty)}
        }.padding(26).frame(width:740)
    }
}
struct JamfNameResultView:View {
    let result:JamfNameResult
    @Environment(\.dismiss) private var dismiss
    @State private var copied=false
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            Label("Names updated in Jamf",systemImage:"checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
            ScrollView{Text(result.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:400)
            HStack{Button(copied ? "Copied":"Copy names & IDs"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(result.text,forType:.string);copied=true};if let url=URL(string:result.server){Link("Open Jamf Pro",destination:url)};Spacer();Button("Done"){dismiss()}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)}
        }.padding(26).frame(width:700)
    }
}
