// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
struct PopupAppearanceControls: View {
    @EnvironmentObject var store: AdminStore
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var frosted: Bool { store.document.value("ui.popupBackgroundStyle") == "frosted" }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("Popup background").font(.headline)
                Spacer()
                Picker("Background",selection:Binding(get:{store.document.value("ui.popupBackgroundStyle") ?? "solid"},set:{store.document.edits["ui.popupBackgroundStyle"]=$0})) {
                    Text("Solid").tag("solid");Text("Frosted").tag("frosted")
                }.pickerStyle(.segmented).labelsHidden().frame(width:180)
            }
            HStack {
                Text("Transparency").font(.caption)
                Slider(value:Binding(get:{min(45,max(0,100-(Double(store.document.value("ui.popupOpacityPercent") ?? "85") ?? 85)))},set:{store.document.edits["ui.popupOpacityPercent"]=String(100-Int($0))}),in:0...45,step:1)
                    .disabled(!frosted || reduceTransparency)
                Text("\(100-(Int(store.document.value("ui.popupOpacityPercent") ?? "85") ?? 85))%").font(.caption.monospacedDigit()).frame(width:36)
            }
            Text(reduceTransparency ? "macOS Reduce Transparency is enabled, so the card stays solid." : "Only the background changes. Labels and buttons stay fully opaque. The live popup uses your desktop backdrop.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct ButtonChecksPanel: View {
    @EnvironmentObject var store: AdminStore
    @Binding var expanded: Bool
    var body: some View {
        DisclosureGroup("Button test results · \(store.buttonChecks.count) observed actions",isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:8) {
                Text("This log records handlers that actually ran in Studio. Timer events are labeled separately. It does not prove a real upgrade or restart succeeded.").font(.caption).foregroundStyle(.secondary)
                if store.buttonChecks.isEmpty { Text("Click a popup button to record its result.").font(.caption) }
                ScrollView(.vertical) {
                    VStack(alignment:.leading,spacing:7) {
                        ForEach(store.buttonChecks.prefix(12)) { event in
                            HStack(alignment:.top) {
                                Image(systemName:event.automatic ? "timer":"checkmark.circle.fill").foregroundStyle(event.automatic ? .orange:.green)
                                VStack(alignment:.leading,spacing:2) {
                                    Text(event.action).font(.caption.bold())
                                    Text(event.state + (event.exitCode.map { " · exit \($0)" } ?? " · no exit") + (event.automatic ? " · automatic":" · handler observed")).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer();Text(event.date,style:.time).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxHeight:130)
                Button("Clear test results") {store.buttonChecks.removeAll()}.font(.caption)
            }.padding(.top,10)
        }.font(.caption).padding(.horizontal,14).padding(.vertical,8)
    }
}
