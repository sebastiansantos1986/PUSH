// PUSH — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

enum ReminderDeliveryPolicy {
    static func ordinaryAwarenessFirst(pending:Bool,pastDeadline:Bool,automaticInstall:Bool)->Bool {pending && (!pastDeadline || !automaticInstall)}
    static func displayed(_ code:Int32)->Bool {[0,1,2,5,100].contains(code)}
    static func withinHours(restricted:Bool,start:Int,end:Int,weekdays:Bool,now:Date,calendar:Calendar = .current)->Bool {
        if !restricted {return true}
        guard (0...23).contains(start),(1...24).contains(end),start<end else{return false}
        let day=calendar.component(.weekday,from:now),hour=calendar.component(.hour,from:now)
        return (!weekdays || ![1,7].contains(day)) && hour>=start && hour<end
    }
}
struct PreparationState:Codable {
    var target:String
    var phase:String
    var reason:String
    var checkedAt:Date
    var retryAfter:Date?
    var completedAt:Date?
}
struct PreparationPlan:Equatable {
    let executable:String
    let arguments:[String]
    static func native(label:String)->Self? {
        guard !label.isEmpty,!label.hasPrefix("-"),!label.contains("\n"),!label.contains("\u{0}") else{return nil}
        return .init(executable:"/usr/sbin/softwareupdate",arguments:["--download",label,"--agree-to-license"])
    }
    static func fullInstaller(target:String)->Self? {
        guard numericOSVersion(target) != nil else{return nil}
        return .init(executable:"/usr/sbin/softwareupdate",arguments:["--fetch-full-installer","--full-installer-version",target])
    }
}
extension CLIDeferralState {
    mutating func queueAwareness(now:Date = Date()) {if notificationPendingSince == nil {notificationPendingSince=now}}
    mutating func recordToastResult(_ result:Int32,interval:TimeInterval,now:Date=Date(),target:String?=nil)->Bool {
        guard ReminderDeliveryPolicy.displayed(result) else{return false}
        notificationPendingSince=nil;lastToastShownAt=now;lastToastTarget=target;nextToastDate=now.addingTimeInterval(interval)
        return true
    }
}
/// Download-only preparation; it never calls InstallWorkflow, startosinstall,
/// softwareupdate --install, credential retrieval, or restart commands.
struct BackgroundPreparation {
    let config:CLIConfig
    static func eligible(config:CLIConfig,loggedIn:Bool,installPending:Bool,activity:Bool?)->Bool {
        !config.debug.dryRun && config.update.prepareAtDeadlineWhenLoggedOut && config.isPastDeadline && !loggedIn && !installPending && activity == false && numericOSVersion(config.update.targetVersion) != nil
    }
    func run() {
        guard getuid()==0,Self.eligible(config:config,loggedIn:userIsLoggedIn(),installPending:(try? loadStateForAction())?.installStarted ?? true,activity:installationIsActive()) else{return}
        guard preparePushRuntime() else {cliError("Background preparation could not prepare a protected runtime folder.");return}
        let lock=open(managedBase+"/install.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard lock>=0 else {cliError("Background preparation lock is unavailable.");return}
        defer {close(lock)}
        guard flock(lock,LOCK_EX|LOCK_NB)==0 else {cliPrint("Another installation/preparation workflow owns the lock.");return}
        defer{flock(lock,LOCK_UN)}
        guard installationIsActive()==false,let current=try? loadStateForAction(),!current.installStarted else{return}
        let folder=URL(fileURLWithPath:managedBase+"/preparation")
        do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}catch{cliError("Preparation log folder is unavailable.");return}
        var info=stat()
        guard lstat(folder.path,&info)==0,info.st_uid==0,info.st_mode&S_IFMT==S_IFDIR,info.st_mode&0o077==0 else {cliError("Preparation folder is not protected.");return}
        let stateURL=URL(fileURLWithPath:managedBase+"/preparation.json"),now=Date(),target=config.update.targetVersion
        if let bytes=try? Data(contentsOf:stateURL) {
            guard let previous=try? JSONDecoder().decode(PreparationState.self,from:bytes) else {cliError("Saved preparation state is unreadable; no download started.");return}
            if sameOSVersion(previous.target,target),let retry=previous.retryAfter,retry>now {cliPrint("Background preparation is waiting for its saved retry/revalidation time.");return}
        }
        var record=PreparationState(target:target,phase:"checking",reason:"Checking download-only preparation",checkedAt:now)
        func save(_ phase:String,_ reason:String,success:Bool=false) {
            record.phase=phase;record.reason=reason;record.checkedAt=Date()
            record.retryAfter=Date().addingTimeInterval(success ? 86400:3600)
            record.completedAt=success ? Date():nil
            if let data=try? JSONEncoder().encode(record) {try? data.write(to:stateURL,options:.atomic);try? FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:stateURL.path)}
            if phase == "failed" {cliError(reason)}else{cliPrint(reason)}
        }
        let checks=PreflightChecks(config:config)
        if let check=checks.checkDisk(PreflightChecks.availableDiskGB()),case .fail(_,_) = check {save("blocked","Background download deferred: insufficient free disk space.");return}
        if let check=checks.checkBattery(),case .fail(_,_) = check {save("blocked","Background download deferred: power/battery requirements are not met.");return}
        if config.preflight.skipOnVPN && checks.isOnVPN() {save("blocked","Background download deferred by the configured VPN policy.");return}
        guard checks.checkNetworkReachability() else {save("blocked","Background download deferred: update servers are unreachable.");return}
        let directories=[managedBase+"/downloads","/Applications"]
        if InstallerValidation.find(in:directories,target:target) != nil {save("downloaded","Installer metadata matches the target. Installation will revalidate it after login.",success:true);return}
        let listing=runDirect("/usr/sbin/softwareupdate",["--list"])
        let label=config.isMajor ? nil:nativeUpdateLabel(version:target,output:listing.0)
        guard let plan=label.flatMap({PreparationPlan.native(label:$0)}) ?? PreparationPlan.fullInstaller(target:target) else {save("failed","No safe download-only plan could be constructed.");return}
        record.phase="downloading";record.reason="Downloading macOS without a logged-in user; no installation is requested";record.retryAfter=nil
        if let data=try? JSONEncoder().encode(record) {try? data.write(to:stateURL,options:.atomic)}
        RuntimeHealthScope.phase("updating","Background download-only preparation is running; user awareness remains queued")
        let result=execute(plan,log:folder.appendingPathComponent("download.log"))
        guard result==0 else {save("failed","Background download failed or timed out. No installation was requested; retry is delayed one hour.");return}
        if label != nil {save("downloaded","Native download command completed. Installation and cache availability will be rechecked after login.",success:true)}
        else if InstallerValidation.find(in:directories,target:target) != nil {save("downloaded","Full-installer download completed and target metadata matches. Installation remains pending login and authorization.",success:true)}
        else {save("failed","Download command finished but no installer matching the target was found. No installation was requested.")}
    }
    private func execute(_ plan:PreparationPlan,log:URL)->Int32 {
        guard FileManager.default.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600]),let output=try? FileHandle(forWritingTo:log) else{return -1}
        defer{try? output.close()}
        let process=Process();process.executableURL=URL(fileURLWithPath:plan.executable);process.arguments=plan.arguments
        process.standardInput=FileHandle.nullDevice;process.standardOutput=output;process.standardError=output
        do {try process.run()}catch{return -1}
        let end=Date().addingTimeInterval(7200)
        var notifiedUID:Int?,lastPoll=Date.distantPast
        while process.isRunning && Date()<end {
            if Date().timeIntervalSince(lastPoll)>=15 {
                lastPoll=Date()
                RuntimeHealthScope.phase("updating","Background download-only preparation remains active; installation has not started")
                if let user=consoleUser(),notifiedUID != user.uid {
                    // Informational only: no Install/Later action is interpreted here.
                    let command=shellArgument(resolveUIBinary())+" --state toast --preparation-notice --config "+shellArgument(resolvedConfigPath ?? "")
                    launchUIAsUser(command);notifiedUID=user.uid
                }
            }
            Thread.sleep(forTimeInterval:0.5)
        }
        if process.isRunning {process.terminate();kill(process.processIdentifier,SIGKILL);process.waitUntilExit();return -2}
        return process.terminationStatus
    }
}
