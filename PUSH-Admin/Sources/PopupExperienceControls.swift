// PUSH / Regina Pro notification patterns — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PopupExperienceControls:View {
    @Binding var presentation:PopupPresentation
    @State private var issue=""
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Stepper("Width: \(Int(presentation.width)) pt",value:$presentation.width,in:360...900,step:20)
            Stepper("Height: \(Int(presentation.height)) pt",value:$presentation.height,in:240...1000,step:20)
            TextField("Banner text",text:$presentation.bannerText).textFieldStyle(.roundedBorder)
            TextField("Greeting template",text:$presentation.greetingTemplate).textFieldStyle(.roundedBorder)
            Text("Use {fullName}, {firstName} or {username}. The logged-in user is resolved when the popup opens; names are not baked into the package.").font(.caption).foregroundStyle(.secondary)
            HStack {Button("Choose banner image…"){chooseBanner()};Button("Remove image"){presentation.bannerImage=nil}.disabled(presentation.bannerImage==nil)}
            if !issue.isEmpty {Text(issue).font(.caption).foregroundStyle(.orange)}
            Text("Native windows are resizable and fit the visible screen. Scrollbars keep all controls reachable on smaller displays.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func chooseBanner() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.image];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            let info=try url.resourceValues(forKeys:[.fileSizeKey]);guard (info.fileSize ?? Int.max)<20_971_520,let image=NSImage(contentsOf:url) else {throw MajorUpgradeDemoError.invalid("Choose an image below 20 MB.")}
            let size=NSSize(width:960,height:180);let result=NSImage(size:size)
            result.lockFocus();NSColor.clear.setFill();NSRect(origin:.zero,size:size).fill();image.draw(in:NSRect(origin:.zero,size:size),from:.zero,operation:.sourceOver,fraction:1);result.unlockFocus()
            guard let tiff=result.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:]),png.count<=262144 else {throw MajorUpgradeDemoError.invalid("Use a simpler banner image that normalizes below 256 KB.")}
            presentation.bannerImage=png;issue="Banner staged in this draft only."
        }catch{issue=error.localizedDescription}
    }
}
extension AdminStore {
    var majorSettings:MajorOfferSettings {get {document.majorOfferSettings ?? MajorOfferSettings()} set {document.majorOfferSettings=newValue}}
}
