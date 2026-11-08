// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit
import SwiftUI
import Darwin

/// Isolated demo process. No production UIContext, CLI, policy/Keychain/state,
/// shared popup responses, notification history or user-request channel is used.
@MainActor final class MajorUpgradeDemoPresenter:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let options:MajorUpgradeDemoOptions
    private var presentation=PopupPresentation()
    private var window:NSWindow?
    private var statusItem:NSStatusItem?
    init(options:MajorUpgradeDemoOptions,presentation:PopupPresentation){self.options=options;self.presentation=presentation}
    static func run(_ arguments:[String])->Never {
        guard getuid() != 0 else {fputs("Open the demo as the logged-in user, without sudo.\n",stderr);Foundation.exit(2)}
        let settings=MajorOfferSettings.installed()
        if arguments == ["--help"] {print(MajorUpgradeDemoCommandHelp.text);Foundation.exit(0)}
        let options:MajorUpgradeDemoOptions
        do {options=try .parse(arguments,requireExplicitDebug:false,defaults:try settings.options)}catch{fputs(error.localizedDescription+"\n",stderr);Foundation.exit(2)}
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        let presenter=Self(options:options,presentation:settings.presentation);app.delegate=presenter
        withExtendedLifetime(presenter){app.run()};Foundation.exit(0)
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        let height=max(300,min(presentation.height,(NSScreen.main?.visibleFrame.height ?? 900)-90))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:presentation.width,height:height),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="PUSH — Major Upgrade Debug";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false;window.delegate=self
        let view=ScrollView(.vertical){MajorUpgradeDemoView(options:options,presentation:presentation,onHide:{[weak self] in self?.window?.orderOut(nil)},onReady:{[weak self] in self?.showWindow()}).padding(.horizontal,20).padding(.top,12).padding(.bottom,20)}
        window.contentMinSize=NSSize(width:360,height:300);window.contentMaxSize=NSScreen.main?.visibleFrame.size ?? NSSize(width:1000,height:1000);window.contentView=NSHostingView(rootView:view);window.center();self.window=window
        let item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);item.button?.title="PUSH Demo";item.button?.toolTip="Simulation only — no real updates or restarts"
        let menu=NSMenu();let show=NSMenuItem(title:"Show upgrade demo",action:#selector(showWindow),keyEquivalent:"");show.target=self;menu.addItem(show);menu.addItem(.separator());let quit=NSMenuItem(title:"Quit demo",action:#selector(quitDemo),keyEquivalent:"q");quit.target=self;menu.addItem(quit);item.menu=menu;statusItem=item
        showWindow()
    }
    @objc func showWindow(){window?.makeKeyAndOrderFront(nil);NSApplication.shared.activate(ignoringOtherApps:true)}
    @objc func quitDemo(){NSApplication.shared.terminate(nil)}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {showWindow();return false}
    func windowWillClose(_ notification:Notification){quitDemo()}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {.terminateNow}
    func applicationWillTerminate(_ notification:Notification){if let statusItem {NSStatusBar.system.removeStatusItem(statusItem)}}
}
private enum MajorUpgradeDemoCommandHelp {
    static let text="PUSH Major Upgrade Demo — simulation only. Options: --from 26.0 --to 27.0 --duration 20. No live mode."
}
