// PUSH / Regina Pro notification patterns — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct SinglePopupPage:View {
    @EnvironmentObject var store:AdminStore
    @State private var title="A message from IT"
    @State private var message="Please save your work before your scheduled maintenance window. Contact IT if you need help."
    @State private var kind="alert"
    @State private var style="info"
    @State private var result=""
    @State private var revision=UUID()
    private var notice:SinglePopupNotice {var n=SinglePopupNotice(title:title,message:message);n.kind=kind;n.style=style;n.debug=true;n.timeout=0;n.presentation=store.majorSettings.presentation;return n}
    private var presentation:Binding<PopupPresentation>{Binding(get:{store.majorSettings.presentation},set:{var value=store.majorSettings;value.presentation=$0;store.majorSettings=value})}
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:22) {
            PageHeading(eyebrow:"Single popups · Regina Pro patterns",title:"Send one clear message.",subtitle:"Build informational alerts and toasts for a local or MDM command. Buttons return responses; they never execute updates or scripts.")
            AdminCard {
                TextField("Title",text:$title).textFieldStyle(.roundedBorder)
                TextEditor(text:$message).frame(height:100).overlay(RoundedRectangle(cornerRadius:6).stroke(.secondary.opacity(0.2)))
                HStack {Picker("Kind",selection:$kind){Text("Alert").tag("alert");Text("Toast").tag("toast")};Picker("Style",selection:$style){ForEach(["info","warning","error","success"],id:\.self){Text($0.capitalized).tag($0)}}}
                PopupExperienceControls(presentation:presentation)
                HStack {Button("Reset preview"){revision=UUID();result=""};Button("Copy MDM command"){
                    let arguments=["/Library/Management/PUSH/push-cli","notice","--title",title,"--message",message,"--kind",kind,"--style",style,"--width",String(Int(presentation.wrappedValue.width)),"--height",String(Int(presentation.wrappedValue.height)),"--greeting",presentation.wrappedValue.greetingTemplate,"--banner",presentation.wrappedValue.bannerText]
                    NSPasteboard.general.clearContents();NSPasteboard.general.setString(arguments.map(shellQuote).joined(separator:" "),forType:.string);result="Command copied only. Deploy your configured presentation package first if using a banner image. Nothing was delivered. Run through your management tool as root to display to the console user."
                }}
            }
            StandaloneNoticeView(notice:notice){code in result="PREVIEW: response \(code) · no update, script or message delivery."}.frame(maxWidth:min(720,presentation.wrappedValue.width)).id(revision)
            if !result.isEmpty {Text(result).font(.callout).foregroundStyle(.secondary)}
            Text("Regina Pro remains untouched. This combines its alert/toast/size concepts with PUSH's configuration workflow; secure inputs, arbitrary scripts, surveys and restart timers were not imported.").font(.caption).foregroundStyle(.secondary)
        }.padding(28)}
    }
}
