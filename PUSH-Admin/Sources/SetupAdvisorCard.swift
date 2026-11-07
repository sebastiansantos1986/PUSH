// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct SetupAdvisorCard:View {
    @EnvironmentObject var store:AdminStore
    private var advice:[SetupAdvice] {SetupAdvisor.evaluate(store.document,catalogDate:store.lastChecked,catalogCached:store.catalogIsCached,providerPresent:store.readiness?.providerPresent,mistPresent:store.mistPath != nil)}
    var body:some View {
        AdminCard {
            Label("Setup suggestions",systemImage:"sparkles").font(.headline)
            Text("Based on your current draft and saved local evidence. Suggestions explain their effect and change the draft only when you choose Apply.").font(.callout).foregroundStyle(.secondary)
            ForEach(advice) {item in
                VStack(alignment:.leading,spacing:7) {
                    Label(item.title,systemImage:item.tone == .ready ? "checkmark.circle":item.tone == .attention ? "exclamationmark.circle":"lightbulb").font(.subheadline.bold())
                    Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    if !item.changes.isEmpty {Button(item.action){
                        let alert=NSAlert();alert.messageText=item.action+"?";alert.informativeText=item.detail+"\n\n"+item.changes.keys.sorted().map{$0+" = "+(item.changes[$0]!.isEmpty ? "(blank)":item.changes[$0]!)}.joined(separator:"\n");alert.addButton(withTitle:"Apply to Draft");alert.addButton(withTitle:"Cancel")
                        if alert.runModal() == .alertFirstButtonReturn {for (key,value) in item.changes {store.document.edits[key]=value};store.notice="Suggestion applied to your draft. No installed policy or service changed."}
                    }.disabled(store.isBuildingDeployment)}
                }.padding(.vertical,7)
                if item.id != advice.last?.id {Divider()}
            }
        }
    }
}
