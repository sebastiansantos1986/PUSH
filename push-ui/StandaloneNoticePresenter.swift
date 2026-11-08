// PUSH / Regina Pro notification patterns — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit
import SwiftUI

@MainActor final class StandaloneNoticePresenter:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let notice:SinglePopupNotice
    private var window:NSWindow?
    init(notice:SinglePopupNotice){self.notice=notice}
    static func run(_ text:String)->Never {
        guard getuid() != 0 else {Foundation.exit(99)}
        var value:SinglePopupNotice
        do {value=try SinglePopupNotice.decode(text);value.presentation.bannerImage=MajorOfferSettings.installed().presentation.bannerImage}catch{fputs("Invalid informational notice. No action taken.\n",stderr);Foundation.exit(99)}
        let app=NSApplication.shared;app.setActivationPolicy(.accessory);let presenter=Self(notice:value);app.delegate=presenter
        withExtendedLifetime(presenter){app.run()};Foundation.exit(2)
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        let screen=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800)
        let width=min(notice.presentation.width,screen.width-40),height=min(notice.presentation.height,screen.height-80)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title=notice.debug ? "PUSH · Notice preview":"PUSH";window.delegate=self;window.isReleasedWhenClosed=false
        window.contentMinSize=NSSize(width:320,height:220);window.contentMaxSize=screen.size
        window.contentView=NSHostingView(rootView:ScrollView{StandaloneNoticeView(notice:notice,onResult:{[weak self] code in self?.finish(code)})})
        if notice.kind=="toast" {window.setFrameOrigin(NSPoint(x:screen.maxX-width-20,y:screen.maxY-height-20));window.level = .floating}else{window.center()}
        self.window=window;window.makeKeyAndOrderFront(nil);NSApplication.shared.activate(ignoringOtherApps:true)
    }
    func windowWillClose(_ notification:Notification){finish(2)}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {finish(2)}
    func finish(_ code:Int32)->Never {
        let result=["action":code==0 ? "acknowledged":code==5 ? "timeout":"dismissed","mode":notice.debug ? "preview":"informational","systemAction":"none"]
        if let data=try? JSONSerialization.data(withJSONObject:result,options:.sortedKeys),let text=String(data:data,encoding:.utf8){print(text)}
        Foundation.exit(code)
    }
}
