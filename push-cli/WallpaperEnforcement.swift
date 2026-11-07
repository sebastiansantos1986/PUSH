// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

struct WallpaperEnforcement {
    let config:CLIConfig
    static func trustedImage(_ path:String)->Bool {
        let url=URL(fileURLWithPath:path).standardizedFileURL
        guard url.path.hasPrefix(managedBase+"/"),url.path==path else{return false}
        var current=url
        while current.path != "/" {
            var info=stat()
            guard lstat(current.path,&info)==0,info.st_uid==0,info.st_mode&0o022==0,info.st_mode&S_IFMT != S_IFLNK else{return false}
            if current==url && (info.st_mode&S_IFMT != S_IFREG || info.st_size>52_428_800) {return false}
            current.deleteLastPathComponent()
        }
        return true
    }
    func run(running:String) {
        guard !config.debug.dryRun,let action=WallpaperPolicy.action(enabled:config.compliance.wallpaperEnabled,running:running,target:config.update.targetVersion) else{return}
        guard let user=consoleUser() else {NotificationHistory.record(state:"wallpaper",outcome:"delayed",reason:"No desktop session; wallpaper will be reassessed on a later check",retry:Date().addingTimeInterval(300));return}
        let image=action == "enforce" ? config.compliance.nonCompliantWallpaper:config.compliance.compliantWallpaper
        if !image.isEmpty && !Self.trustedImage(image) {NotificationHistory.record(state:"wallpaper",outcome:"failed",reason:"Wallpaper image is missing or outside protected managed storage",uid:user.uid);return}
        let binary=resolveUIBinary()
        guard FileManager.default.isExecutableFile(atPath:binary) else{return}
        var args=["asuser",String(user.uid),"/usr/bin/sudo","-n","-u",user.name,"--",binary,"--wallpaper",action]
        if !image.isEmpty {args += ["--wallpaper-image",image]}
        let bundlePath=binary.components(separatedBy:"/Contents/MacOS/").first ?? ""
        guard let version=Bundle(path:bundlePath)?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,numericOSVersion(version) != nil,versionGTE(version,"1.8.0") else {
            NotificationHistory.record(state:"wallpaper",outcome:"failed",reason:"Wallpaper requires the matching 1.8.0 or later popup helper",uid:user.uid);return
        }
        let result=runHelper(args)
        guard let bytes=result.0.data(using:.utf8),let report=try? JSONDecoder().decode(WallpaperResult.self,from:bytes) else {NotificationHistory.record(state:"wallpaper",outcome:"failed",reason:"Desktop wallpaper helper did not return a valid result",uid:user.uid);return}
        if report.changed>0 || result.1 != 0 {NotificationHistory.record(state:"wallpaper",outcome:result.1==0 ? "applied":"failed",reason:report.reason,uid:user.uid)}
    }
    private func runHelper(_ arguments:[String])->(String,Int32) {
        let process=Process(),pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:"/bin/launchctl");process.arguments=arguments
        process.standardInput=FileHandle.nullDevice;process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        do {try process.run()}catch{return ("",-1)}
        let end=Date().addingTimeInterval(20)
        while process.isRunning && Date()<end {Thread.sleep(forTimeInterval:0.05)}
        if process.isRunning {process.terminate();kill(process.processIdentifier,SIGKILL);process.waitUntilExit();return ("",-2)}
        let data=pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(decoding:data,as:UTF8.self),process.terminationStatus)
    }
}
