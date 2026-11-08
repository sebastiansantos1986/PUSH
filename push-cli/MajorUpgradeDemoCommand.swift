// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

struct MajorUpgradeDemoCommand {
    let args:[String]
    static let usage="""
    Safe optional major-upgrade simulation:
      push-cli major-offer --debug
      push-cli major-offer --debug --from 26.0 --to 27.0 --duration 20
    Run as your logged-in user, without sudo. Versions and progress are example data.
    One demo window: Offer → Downloading → Preparing → Ready to restart.
    All buttons are simulated. No live checks, config/state writes, downloads,
    Keychain access, installation, update request or restart. Live mode is disabled.
    """
    func run() {
        if args == ["--help"] || args == ["-h"] {print(Self.usage);return}
        let options:MajorUpgradeDemoOptions
        do {options=try .parse(args,defaults:try MajorOfferSettings.installed().options)}catch{fputs(error.localizedDescription+"\n"+Self.usage+"\n",stderr);Foundation.exit(2)}
        guard getuid() != 0 else {fputs("Run this simulation without sudo from the logged-in desktop session.\n",stderr);Foundation.exit(2)}
        let app=URL(fileURLWithPath:"/Library/Management/PUSH/PUSH Major Upgrade Demo.app")
        guard let bundle=Bundle(url:app),bundle.bundleIdentifier=="com.push.major-demo",FileManager.default.isExecutableFile(atPath:app.appendingPathComponent("Contents/MacOS/push-major-demo").path) else {fputs("Install the matching PUSH 1.11.0 client first; the isolated demo app is missing.\n",stderr);Foundation.exit(2)}
        // LaunchServices only. Never use root, install workflow, live config or
        // shared production popup/result files. Existing demo sessions reopen.
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/open");process.arguments=[app.path,"--args"]+options.launchArguments
        do {try process.run();process.waitUntilExit();print(process.terminationStatus==0 ? "Debug launch requested. Use the temporary PUSH Demo menu to reopen progress. All actions are simulated.":"The demo launch request failed. No update was started.")}
        catch {fputs("Could not request the debug window. No update was started.\n",stderr)}
    }
}
