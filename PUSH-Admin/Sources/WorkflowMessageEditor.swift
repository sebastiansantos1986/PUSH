// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI

struct WorkflowMessageEditor:View {
    @EnvironmentObject var store:AdminStore
    @State private var localSelection:WorkflowMessage = .toast
    var selection:Binding<WorkflowMessage>? = nil
    private var selected:WorkflowMessage {selection?.wrappedValue ?? localSelection}
    private var selectedBinding:Binding<WorkflowMessage> {selection ?? Binding(get:{localSelection},set:{localSelection=$0})}
    private var recipe:WorkflowRecipe {WorkflowRecipe.from(document:store.document)}
    private var text:Binding<String> {Binding(get:{store.document.setupValue(selected.key)},set:{store.document.edits[selected.key]=$0})}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            PopupLogoControls()
            TextField("Organization (optional)",text:Binding(get:{store.document.setupValue("ui.orgName")},set:{store.document.edits["ui.orgName"]=$0})).textFieldStyle(.roundedBorder)
            TextField("Support email (optional)",text:Binding(get:{store.document.setupValue("ui.itContactEmail")},set:{store.document.edits["ui.itContactEmail"]=$0})).textFieldStyle(.roundedBorder)
            TextField("Full reminder title",text:Binding(get:{store.document.setupValue("ui.appName")},set:{store.document.edits["ui.appName"]=$0})).textFieldStyle(.roundedBorder)
            Picker("Message",selection:selectedBinding){ForEach(WorkflowMessage.allCases){Text($0.title).tag($0)}}
            Text("Message shown to users").font(.subheadline.bold())
            TextEditor(text:text).font(.body).frame(height:110).overlay(RoundedRectangle(cornerRadius:6).stroke(.secondary.opacity(0.2)))
            Text("Suggested wording for this workflow").font(.subheadline.bold())
            Text(WorkflowWording.suggested(selected,recipe:recipe)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
            HStack {
                Button("Use this suggestion"){store.document=WorkflowWording.apply(selected,recipe:recipe,to:store.document)}
                Button("Use suggested message set…"){
                    store.confirmSuggestedMessages(recipe:recipe)
                }
            }
            Text("Suggestions use your selected OS and deadline. Applying changes the draft only and preserves your icon, organization, authorization and update rules. The full set also changes the popup title to Software Update Required.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
