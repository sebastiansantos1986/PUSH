// PUSH / Regina Pro notification patterns — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
import Combine

struct PopupGreetingBanner:View {
    let presentation:PopupPresentation
    var compact=false
    var body:some View {
        VStack(alignment:.leading,spacing:compact ? 5:8) {
            if let data=presentation.bannerImage,let image=NSImage(data:data) {
                Image(nsImage:image).resizable().scaledToFill().frame(height:compact ? 52:76).clipped().clipShape(RoundedRectangle(cornerRadius:8))
            }
            if !presentation.bannerText.isEmpty {Text(presentation.bannerText).font(.caption.weight(.semibold)).foregroundStyle(.blue).fixedSize(horizontal:false,vertical:true)}
            if !presentation.greetingTemplate.isEmpty {Text(presentation.greeting(fullName:NSFullUserName(),username:NSUserName())).font(compact ? .subheadline.weight(.semibold):.headline).fixedSize(horizontal:false,vertical:true)}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct NoticeMarkdownView:View {
    let source:String
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            ForEach(Array(NoticeMarkdown.blocks(source).enumerated()),id:\.offset) { _,block in
                switch block {
                case .paragraph(let text):Text(NoticeMarkdown.inline(text))
                case .heading(let level,let text):Text(NoticeMarkdown.inline(text)).font(level==1 ? .title3.bold():.headline).padding(.top,3)
                case .bullet(let text):HStack(alignment:.firstTextBaseline,spacing:8){Text("•");Text(NoticeMarkdown.inline(text)).frame(maxWidth:.infinity,alignment:.leading)}
                case .numbered(let marker,let text):HStack(alignment:.firstTextBaseline,spacing:8){Text(marker).monospacedDigit();Text(NoticeMarkdown.inline(text)).frame(maxWidth:.infinity,alignment:.leading)}
                case .quote(let text):HStack(spacing:10){Rectangle().fill(.secondary.opacity(0.4)).frame(width:3);Text(NoticeMarkdown.inline(text)).foregroundStyle(.secondary)}.fixedSize(horizontal:false,vertical:true)
                case .code(let text):Text(text).font(.system(.caption,design:.monospaced)).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:6))
                }
            }
        }.font(.body).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
        .environment(\.openURL,OpenURLAction {url in NoticeMarkdown.allowsLink(url) ? .systemAction:.discarded})
    }
}
struct StandaloneNoticeView:View {
    let notice:SinglePopupNotice
    var scrollContent=true
    let onResult:(Int32)->Void
    @State private var remaining:Int
    @State private var response=NoticeResponseState()
    private let tick=Timer.publish(every:1,on:.main,in:.common).autoconnect()
    init(notice:SinglePopupNotice,scrollContent:Bool=true,onResult:@escaping (Int32)->Void){self.notice=notice;self.scrollContent=scrollContent;self.onResult=onResult;_remaining=State(initialValue:notice.timeout)}
    private var compact:Bool {notice.kind=="toast"}
    private var color:Color {notice.style=="error" ? .red:notice.style=="warning" ? .orange:notice.style=="success" ? .green:.blue}
    private var icon:String {notice.style=="error" ? "xmark.octagon.fill":notice.style=="warning" ? "exclamationmark.triangle.fill":notice.style=="success" ? "checkmark.circle.fill":"info.circle.fill"}
    private func finish(_ code:Int32){if response.respond(code){onResult(code)}}
    private var content:some View {
        VStack(alignment:.leading,spacing:compact ? 10:14) {
            HStack {Label("PUSH",systemImage:"bubble.left.and.text.bubble.right.fill").font(.caption.weight(.semibold));Spacer();Text("by Sebastian Santos").font(.caption2).foregroundStyle(.secondary)}
            if notice.debug {Label("PREVIEW · NO SYSTEM ACTIONS",systemImage:"testtube.2").font(.caption2.bold()).foregroundStyle(.blue)}
            PopupGreetingBanner(presentation:notice.presentation,compact:compact)
            HStack(alignment:.top,spacing:10) {Image(systemName:icon).font(.system(size:compact ? 22:28)).foregroundStyle(color);Text(notice.title).font(compact ? .headline:.title3.bold()).fixedSize(horizontal:false,vertical:true)}
            NoticeMarkdownView(source:notice.message)
        }.padding(compact ? 16:20).frame(maxWidth:.infinity,alignment:.leading)
    }
    private var footer:some View {
        VStack(alignment:.leading,spacing:8) {
            ViewThatFits(in:.horizontal) {
                HStack {if !notice.secondary.isEmpty {secondaryButton};Spacer(minLength:12);primaryButton}
                VStack(alignment:.trailing,spacing:8){primaryButton;if !notice.secondary.isEmpty {secondaryButton}}
            }.controlSize(.regular).disabled(response.result != nil)
            if notice.timeout>0 {Text("Closes in \(remaining)s · no response is recorded as consent").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
        }.padding(.horizontal,compact ? 16:20).padding(.top,12).padding(.bottom,compact ? 14:16)
    }
    private var primaryButton:some View {Button(action:{finish(0)}){Text(notice.primary).fixedSize(horizontal:false,vertical:true)}.buttonStyle(.borderedProminent).tint(color).keyboardShortcut(.defaultAction)}
    private var secondaryButton:some View {Button(action:{finish(2)}){Text(notice.secondary).fixedSize(horizontal:false,vertical:true)}.keyboardShortcut(.cancelAction)}
    var body:some View {
        VStack(spacing:0) {
            if scrollContent {ScrollView {content}.scrollBounceBehavior(.basedOnSize)}else{content}
            Divider()
            footer
        }.frame(maxWidth:.infinity,alignment:.leading).background(.regularMaterial)
        .onReceive(tick){_ in if response.tick(remaining:&remaining,timeout:notice.timeout){onResult(5)}}
    }
}
