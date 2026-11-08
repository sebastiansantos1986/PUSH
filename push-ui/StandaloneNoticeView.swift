// PUSH / Regina Pro notification patterns — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
import Combine

struct PopupGreetingBanner:View {
    let presentation:PopupPresentation
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if let data=presentation.bannerImage,let image=NSImage(data:data) {Image(nsImage:image).resizable().scaledToFill().frame(height:86).clipped().clipShape(RoundedRectangle(cornerRadius:10))}
            if !presentation.bannerText.isEmpty {Text(presentation.bannerText).font(.caption.weight(.semibold)).foregroundStyle(.blue)}
            if !presentation.greetingTemplate.isEmpty {Text(presentation.greeting(fullName:NSFullUserName(),username:NSUserName())).font(.title3.bold())}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct StandaloneNoticeView:View {
    let notice:SinglePopupNotice
    let onResult:(Int32)->Void
    @State private var remaining:Int
    @State private var responded=false
    private let tick=Timer.publish(every:1,on:.main,in:.common).autoconnect()
    init(notice:SinglePopupNotice,onResult:@escaping (Int32)->Void){self.notice=notice;self.onResult=onResult;_remaining=State(initialValue:notice.timeout)}
    private var color:Color {notice.style=="error" ? .red:notice.style=="warning" ? .orange:notice.style=="success" ? .green:.blue}
    private var icon:String {notice.style=="error" ? "xmark.octagon.fill":notice.style=="warning" ? "exclamationmark.triangle.fill":notice.style=="success" ? "checkmark.circle.fill":"info.circle.fill"}
    private func finish(_ code:Int32){guard !responded else{return};responded=true;onResult(code)}
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {Label("PUSH",systemImage:"bubble.left.and.text.bubble.right.fill").font(.headline);Spacer();Text("Sebastian Santos").font(.caption2).foregroundStyle(.secondary)}
            if notice.debug {Label("DEBUG · NOTICE PREVIEW",systemImage:"testtube.2").font(.caption.bold()).foregroundStyle(.blue)}
            PopupGreetingBanner(presentation:notice.presentation)
            HStack(alignment:.top,spacing:14) {Image(systemName:icon).font(.system(size:32)).foregroundStyle(color);Text(notice.title).font(.title2.bold()).fixedSize(horizontal:false,vertical:true)}
            Text(notice.message).font(.body).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
            HStack {if !notice.secondary.isEmpty {Button(notice.secondary){finish(2)}};Spacer();Button(notice.primary){finish(0)}.buttonStyle(.borderedProminent).tint(color)}.controlSize(.large).disabled(responded)
            if remaining>0 {Text("Closes in \(remaining)s · timeout does not mean agreement").font(.caption2).foregroundStyle(.secondary)}
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius:16))
        .onReceive(tick){_ in guard notice.timeout>0,!responded else{return};remaining=max(0,remaining-1);if remaining==0 {finish(5)}}
    }
}
