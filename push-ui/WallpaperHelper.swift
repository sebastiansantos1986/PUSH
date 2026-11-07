// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit
import CoreGraphics
import Darwin

/// Runs only in the console user's session. No window, credential, installer,
/// network request or privileged wallpaper database edit is involved.
func handleWallpaperRequest(_ args:[String]) {
    guard let index=args.firstIndex(of:"--wallpaper"),args.indices.contains(index+1) else{return}
    NSApplication.shared.setActivationPolicy(.prohibited)
    let action=args[index+1]
    func finish(_ report:WallpaperResult,_ code:Int32)->Never {
        if let data=try? JSONEncoder().encode(report),let text=String(data:data,encoding:.utf8){print(text)}
        Foundation.exit(code)
    }
    guard ["enforce","restore"].contains(action) else {finish(.init(action:action,changed:0,verified:0,displays:0,reason:"Unknown wallpaper action"),3)}
    let imageIndex=args.firstIndex(of:"--wallpaper-image")
    let path=imageIndex.flatMap{args.indices.contains($0+1) ? args[$0+1]:nil}
    let desired=path.map{URL(fileURLWithPath:$0).standardizedFileURL.resolvingSymlinksInPath()}
    if action=="enforce" && desired==nil {finish(.init(action:action,changed:0,verified:0,displays:0,reason:"Managed image is missing"),3)}
    if let desired, !FileManager.default.isReadableFile(atPath:desired.path) || NSImage(contentsOf:desired)==nil {finish(.init(action:action,changed:0,verified:0,displays:0,reason:"Managed image cannot be read as an image"),3)}
    let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PUSH Wallpaper")
    do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}catch {finish(.init(action:action,changed:0,verified:0,displays:0,reason:"Wallpaper baseline directory is unavailable"),3)}
    let lock=open(folder.appendingPathComponent("state.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
    guard lock>=0 else {finish(.init(action:action,changed:0,verified:0,displays:0,reason:"Wallpaper lock is unavailable"),3)}
    defer{close(lock)}
    guard flock(lock,LOCK_EX|LOCK_NB)==0 else {finish(.init(action:action,changed:0,verified:0,displays:0,reason:"Another wallpaper check is running"),2)}
    defer{flock(lock,LOCK_UN)}
    let file=folder.appendingPathComponent("baseline.json")
    var saved=WallpaperUserDocument()
    if FileManager.default.fileExists(atPath:file.path) {
        guard let data=try? Data(contentsOf:file),data.count<=524_288,let decoded=try? JSONDecoder().decode(WallpaperUserDocument.self,from:data) else {finish(.init(action:action,changed:0,verified:0,displays:0,reason:"Saved wallpaper baseline is unreadable; no changes were made"),3)}
        saved=decoded
    }
    func save()throws {try JSONEncoder().encode(saved).write(to:file,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)}
    let screens=NSScreen.screens,workspace=NSWorkspace.shared
    var changed=0,verified=0,failures=0
    for screen in screens {
        guard let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {failures+=1;continue}
        let display=CGDirectDisplayID(number.uint32Value)
        let serial=CGDisplaySerialNumber(display)
        let key=CGDisplayIsBuiltin(display) != 0 ? "builtin":(serial != 0 ? "\(CGDisplayVendorNumber(display))-\(CGDisplayModelNumber(display))-\(serial)":"display-\(display)")
        let currentURL=workspace.desktopImageURL(for:screen)?.standardizedFileURL.resolvingSymlinksInPath()
        let current=currentURL?.path
        let options=workspace.desktopImageOptions(for:screen) ?? [:]
        if action=="enforce",let desired {
            if current==desired.path {
                if saved.displays[key]==nil {saved.displays[key] = .init(priorURL:nil,managedURL:desired.path,scaling:nil,clipping:nil)}
                verified+=1;continue
            }
            if saved.displays[key]==nil {
                // Never record an already managed image as the user's original.
                let prior=current.flatMap{$0.hasPrefix(WallpaperPolicy.managedDirectory+"/") ? nil:$0}
                saved.displays[key] = .init(priorURL:prior,managedURL:desired.path,scaling:options[.imageScaling] as? Int,clipping:options[.allowClipping] as? Bool)
            }
            do {
                try save() // Preserve baseline before replacing anything.
                try workspace.setDesktopImageURL(desired,for:screen,options:options)
                RunLoop.current.run(until:Date().addingTimeInterval(0.15))
                if workspace.desktopImageURL(for:screen)?.standardizedFileURL.resolvingSymlinksInPath()==desired {changed+=1;verified+=1;saved.displays[key]?.managedURL=desired.path}else{failures+=1}
            } catch {failures+=1}
        } else if action=="restore",let record=saved.displays[key] {
            if current != record.managedURL {saved.displays.removeValue(forKey:key);continue} // Preserve the user's newer choice.
            let restoration=desired ?? record.priorURL.map{URL(fileURLWithPath:$0)}
            guard let restoration,FileManager.default.isReadableFile(atPath:restoration.path),restoration.path != record.managedURL else {failures+=1;continue}
            var restoreOptions=options
            if let scaling=record.scaling {restoreOptions[.imageScaling]=scaling}
            if let clipping=record.clipping {restoreOptions[.allowClipping]=clipping}
            do {
                try workspace.setDesktopImageURL(restoration,for:screen,options:restoreOptions)
                RunLoop.current.run(until:Date().addingTimeInterval(0.15))
                if workspace.desktopImageURL(for:screen)?.standardizedFileURL.resolvingSymlinksInPath()==restoration.standardizedFileURL.resolvingSymlinksInPath() {changed+=1;verified+=1;saved.displays.removeValue(forKey:key)}else{failures+=1}
            } catch {failures+=1}
        } else {verified+=1}
    }
    do {try save()}catch {failures+=1}
    let reason=failures>0 ? "Wallpaper check could not complete on every active display; baseline retained for retry":"Wallpaper \(action): \(changed) active display(s) changed, \(verified) verified; personal wallpaper preserved when no replacement was needed"
    finish(.init(action:action,changed:changed,verified:verified,displays:screens.count,reason:reason),failures>0 || screens.isEmpty ? 2:0)
}
