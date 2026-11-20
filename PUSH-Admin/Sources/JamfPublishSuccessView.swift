// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
struct JamfPublishSuccessView:View {
    let report:JamfPublishSuccess
    let showFiles:()->Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied=false
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            HStack(spacing:14){
                Image(systemName:report.isPreview ? "eye.circle.fill":"checkmark.circle.fill").font(.system(size:44)).foregroundStyle(report.isPreview ? .blue:.green)
                VStack(alignment:.leading,spacing:6){Text(report.title).font(.title2.bold());Text(report.subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            }
            if report.isPreview {Text("SIMULATION · EXAMPLE NAMES AND IDS").font(.caption.bold()).foregroundStyle(.blue)}
            Text(report.server).font(.callout).textSelection(.enabled)
            ScrollView {
                VStack(alignment:.leading,spacing:18){
                    GroupBox("Pilot computer group") {
                        VStack(alignment:.leading,spacing:6){Text(report.group.name).font(.headline).textSelection(.enabled);Text("Jamf ID \(report.group.id) · "+report.group.action).font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(8)
                    }
                    Text("Policies").font(.headline)
                    ForEach(report.policies){item in
                        VStack(alignment:.leading,spacing:6){
                            Text(item.purpose).font(.headline)
                            Text(item.name).font(.callout).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                            HStack{Text("Jamf ID \(item.id) · "+item.action);Spacer();Text(report.enabled ? "Enabled for pilot":"Disabled").fontWeight(.semibold).foregroundStyle(report.enabled ? .green:.secondary)}.font(.caption)
                        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.045),in:RoundedRectangle(cornerRadius:10))
                    }
                }
            }.frame(minHeight:220,maxHeight:400)
            Text(report.nextStep).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack{
                Button(copied ? "Copied":"Copy names & IDs") {NSPasteboard.general.clearContents();NSPasteboard.general.setString(report.text,forType:.string);copied=true}
                if !report.isPreview {
                    Button("Open saved summary"){showFiles()}
                    if let url=URL(string:report.server){Link("Open Jamf Pro",destination:url)}
                }
                Spacer();Button("Done"){dismiss()}.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(26).frame(width:680)
    }
}
