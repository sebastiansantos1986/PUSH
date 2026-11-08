// PUSH / Regina Pro notification patterns — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import IOKit
import Darwin

enum StandalonePopupLauncher {
    static func show(_ notice:SinglePopupNotice)->Int32 {
        do {
            let payload=try notice.payload()
            let binary=managedBase+"/PUSH Notices.app/Contents/MacOS/push-notice"
            guard FileManager.default.isExecutableFile(atPath:binary) else {print("Install the matching PUSH client: the isolated popup app is missing.");return 99}
            let process=Process()
            if getuid()==0 {
                let attributes=try FileManager.default.attributesOfItem(atPath:"/dev/console")
                guard let uid=(attributes[.ownerAccountID] as? NSNumber)?.intValue,uid>0 else {print("No logged-in desktop user; no popup was delivered.");return 101}
                process.executableURL=URL(fileURLWithPath:"/bin/launchctl")
                process.arguments=["asuser",String(uid),"/usr/bin/sudo","-n","-H","-u","#"+String(uid),binary,"--notice-payload",payload]
            } else {process.executableURL=URL(fileURLWithPath:binary);process.arguments=["--notice-payload",payload]}
            process.standardInput=FileHandle.nullDevice
            print("Opening informational popup; waiting for acknowledgement, close or timeout. No update action is attached to its buttons.")
            try process.run();process.waitUntilExit();return process.terminationStatus
        }catch{print("Popup could not be prepared. No system action occurred.");return 99}
    }
}
struct StandaloneNoticeCommand {
    let args:[String]
    func run() {
        if args==["--help"] {print("push-cli notice --title <text> --message <text> [--kind alert|toast] [--style info|warning|error|success] [--width 480] [--height 480] [--timeout 60] [--debug]. Buttons only return acknowledgement/close/timeout; never execute commands.");return}
        let allowed=Set(["--title","--message","--kind","--style","--width","--height","--timeout","--primary","--secondary","--banner","--greeting"])
        var values:[String:String]=[:],debug=false,index=0
        while index<args.count {
            if args[index]=="--debug" {debug=true;index+=1;continue}
            guard allowed.contains(args[index]),index+1<args.count,values[args[index]]==nil else {print("Unsupported, duplicate or incomplete notice option.");return}
            values[args[index]]=args[index+1];index+=2
        }
        var notice=SinglePopupNotice(title:values["--title"] ?? "PUSH",message:values["--message"] ?? "")
        notice.presentation=MajorOfferSettings.installed().presentation
        notice.kind=values["--kind"] ?? "alert";if notice.kind=="toast" {notice.presentation.width=420;notice.presentation.height=320};notice.style=values["--style"] ?? "info";notice.debug=debug
        notice.primary=values["--primary"] ?? "Got it";notice.secondary=values["--secondary"] ?? "Close"
        if let value=values["--width"] {guard let n=Double(value) else{print("Invalid width");return};notice.presentation.width=n}
        if let value=values["--height"] {guard let n=Double(value) else{print("Invalid height");return};notice.presentation.height=n}
        if let value=values["--timeout"] {guard let n=Int(value) else{print("Invalid timeout");return};notice.timeout=n}
        if let value=values["--banner"] {notice.presentation.bannerText=value}
        if let value=values["--greeting"] {notice.presentation.greetingTemplate=value}
        Foundation.exit(StandalonePopupLauncher.show(notice))
    }
}
struct HardwareCompatibilityCommand {
    let args:[String]
    func run() {
        guard let target=argValue("--target",in:args),AppleHardwareCatalog.major(target) != nil else {print("Usage: push-cli hardware check --target 27 [--popup]. Reads local hardware and the bundled Apple catalog only; no download or install.");return}
        let result=AppleHardwareReader.assessment(target:target)
        print("Hardware: \(result.model) · \(result.state.rawValue.uppercased()) for macOS \(target)\n\(result.reason)\nSource: \(result.source)")
        if args.contains("--popup"),result.state != .supported {Foundation.exit(StandalonePopupLauncher.show(result.notice()))}
    }
}
