// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI

struct WorkflowLibraryBar:View {
    @EnvironmentObject var store:AdminStore
    @State private var selected:UUID?
    var body:some View {
        AdminCard {
            HStack {Label("Saved workflows",systemImage:"square.stack").font(.headline);Spacer();Button("Save workflow…"){if let id=store.saveNamedWorkflow(){selected=id}}}
            Text("Reuse a policy with its messages and images. Saving creates a new copy; loading preserves your current draft as a recovery copy.").font(.caption).foregroundStyle(.secondary)
            Picker("Saved copy",selection:$selected) {
                Text("Choose a saved workflow").tag(Optional<UUID>.none)
                ForEach(store.savedWorkflows){item in Text(item.name+" · "+item.savedAt.formatted(date:.abbreviated,time:.shortened)).tag(Optional(item.id))}
            }
            HStack {
                Button("Load selected"){if let selected{store.loadSavedWorkflow(selected)}}.disabled(selected==nil)
                Button("Compare with selected"){if let selected{store.compareWithSavedWorkflow(selected)}}.disabled(selected==nil)
                Spacer();Button("Refresh saved copies"){store.refreshSavedWorkflows()}
            }
            if !store.workflowLibraryIssue.isEmpty {Text(store.workflowLibraryIssue).font(.caption).foregroundStyle(.orange)}
        }.onAppear{store.refreshSavedWorkflows()}
    }
}
struct WorkflowChangesView:View {
    @EnvironmentObject var store:AdminStore
    var body:some View {
        let comparison=store.workflowComparison
        AdminCard {
            Label("What changed before building",systemImage:"arrow.left.arrow.right").font(.title2.bold())
            if let baseline=comparison.baseline {
                Text("Compared with: "+baseline.name).font(.headline)
                Text("Captured "+baseline.capturedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                if comparison.changes.isEmpty {Text("No policy or selected image changes were found.").foregroundStyle(.green)}
                else {
                    Text("\(comparison.changes.count) changed settings or images. Enforcement changes appear first.").font(.callout)
                    ForEach(comparison.changes){change in
                        Divider()
                        Text(change.title).font(.headline).foregroundStyle(change.affectsEnforcement ? Color.orange:Color.primary)
                        Text(change.id).font(.caption).foregroundStyle(.secondary)
                        HStack(alignment:.top,spacing:16) {
                            value("BEFORE",change.before)
                            value("AFTER",change.after)
                        }
                    }
                }
            }else {
                Text("No earlier workflow is selected for comparison.").font(.headline)
                Text("Use Compare with selected above, or build your first package. After a successful build, the exact packaged policy becomes this draft’s baseline. A first build is not reported as unchanged.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Compares policy values and selected image content. It does not compare installer binaries, profile identities, fleet state or Keychain passwords. The packaged review uses the final export settings.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func value(_ title:String,_ text:String)->some View {
        VStack(alignment:.leading,spacing:6){Text(title).font(.caption.bold()).foregroundStyle(.secondary);Text(text.isEmpty ? "Empty":text).font(.callout).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)}.frame(maxWidth:.infinity,alignment:.leading)
    }
}
