// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation
import Darwin
import Security

/// Validate product OS metadata, never the installer's unrelated bundle version.
enum InstallerValidation {
    /// All install paths use the same search before and after downloading.
    /// Mist writes into the managed cache; softwareupdate writes /Applications.
    static func findForInstall(target:String,managedRoot:String=managedBase,applications:String="/Applications")->String? {
        find(in:[managedRoot+"/downloads",applications],target:target)
    }
    static func productVersion(in plist: URL) -> String? {
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = object as? [String: Any] else { return nil }
        if let image = dict["System Image Info"] as? [String: Any],
           let version = image["version"] as? String, numericOSVersion(version) != nil { return version }
        if let assets = dict["Assets"] as? [[String: Any]] {
            let versions = Set(assets.compactMap { $0["OSVersion"] as? String }.filter { numericOSVersion($0) != nil })
            if versions.count == 1 { return versions.first }
        }
        return nil
    }
    static func matches(_ installer: String, target: String) -> Bool {
        guard numericOSVersion(target) != nil,
              FileManager.default.isExecutableFile(atPath: installer + "/Contents/Resources/startosinstall") else { return false }
        let base = URL(fileURLWithPath: installer)
        for name in ["Contents/SharedSupport/InstallInfo.plist", "Contents/Resources/InstallInfo.plist"] {
            if let version = productVersion(in: base.appendingPathComponent(name)) { return sameOSVersion(version, target) }
        }
        // Modern installers hold MobileAsset product metadata in SharedSupport.dmg.
        let dmg = base.appendingPathComponent("Contents/SharedSupport/SharedSupport.dmg").path
        guard FileManager.default.fileExists(atPath: dmg) else { return false }
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("push-metadata-" + UUID().uuidString)
        do { try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700]) } catch { return false }
        defer { try? FileManager.default.removeItem(at: mount) }
        let (_, status) = runDirect("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg])
        guard status == 0 else { return false }
        defer { _ = runDirect("/usr/bin/hdiutil", ["detach", mount.path]) }
        guard let files = FileManager.default.enumerator(at: mount, includingPropertiesForKeys: nil) else { return false }
        var versions = Set<String>()
        for case let file as URL in files where ["xml", "plist"].contains(file.pathExtension) {
            if file.lastPathComponent.contains("MacSoftwareUpdate"), let version = productVersion(in: file) { versions.insert(version) }
        }
        return versions.count == 1 && versions.first.map { sameOSVersion($0, target) } == true
    }
    static func find(in directories: [String], target: String) -> String? {
        for directory in directories {
            guard let files = FileManager.default.enumerator(at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in files {
                if url.pathExtension == "app" {
                    files.skipDescendants()
                    if url.lastPathComponent.hasPrefix("Install"), matches(url.path, target: target) { return url.path }
                }
            }
        }
        return nil
    }
}

func currentBootTimestamp() -> Double? {
    var boot = timeval(), size = MemoryLayout<timeval>.stride
    guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
    return Double(boot.tv_sec)
}

extension CLIDeferralState {
    mutating func beginInstallation(target: String, running: String, boot: Double?, origin:String?=nil) {
        installOrigin=origin
        installStartedAt = Date()
        installOwnerPID = getpid()
        lastSeenVersion = running
        installTargetVersion = target
        installBootTimestamp = boot
        installStarted = true
        installCompleted = false
    }
    mutating func failInstallation() {
        installStarted = false
        installCompleted = false
        installTargetVersion = nil
        installBootTimestamp = nil
        installStartedAt = nil
        installOwnerPID = nil
    }
    /// Returns true only for a verified completion; an unsuccessful reboot releases retries.
    mutating func reconcileInstallation(running: String, boot: Double?, fallbackTarget: String) -> Bool {
        guard installStarted, !installCompleted else { return false }
        let rebooted = installBootTimestamp.flatMap { previous in boot.map { abs($0 - previous) > 1 } } ?? (running != lastSeenVersion)
        guard rebooted else { return false }
        let target = installTargetVersion ?? fallbackTarget
        if numericOSVersion(running) != nil, numericOSVersion(target) != nil,
           versionGTE(running, target), running != lastSeenVersion {
            installStarted = false
            installCompleted = true
            return true
        }
        failInstallation()
        return false
    }
}

func preparePushRuntime() -> Bool {
    let path = "/private/var/run/com.push"
    if mkdir(path, 0o755) != 0 && errno != EEXIST { return false }
    var info = stat()
    return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
        && info.st_uid == 0 && (info.st_mode & 0o022) == 0
}

// MARK: - Discovery policy and installation health
// Developer: Sebastian Santos

enum DiscoveryPolicy {
    static func deadline(config: CLIConfig, target: String, isMajor: Bool, firstSeen: Date) -> String {
        if !config.update.deadline.isEmpty { return config.update.deadline }
        if sameOSVersion(config.update.automaticDeadlineTarget, target), ISO8601DateFormatter().date(from: config.update.automaticDeadline) != nil {
            return config.update.automaticDeadline
        }
        let days = max(1, min(365, isMajor ? config.auto.majorDeadlineDays : config.auto.minorDeadlineDays))
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: firstSeen) ?? firstSeen.addingTimeInterval(Double(days) * 86400)
        return ISO8601DateFormatter().string(from: date)
    }
    static func eligible(version: String, beta: Bool, current: String, config: CLIConfig) -> Bool {
        guard numericOSVersion(version) != nil, !versionGTE(current, version),
              !(config.auto.skipBetas && beta), !config.auto.skipVersions.contains(version) else { return false }
        let currentMajor = Int(current.split(separator: ".").first ?? "0") ?? 0
        let targetMajor = Int(version.split(separator: ".").first ?? "0") ?? 0
        if config.auto.maximumMajorVersion>0 && targetMajor>config.auto.maximumMajorVersion {return false}
        if currentMajor < config.auto.enforceMinimumMajorVersion && targetMajor < config.auto.enforceMinimumMajorVersion { return false }
        // Explicit minimum-major enforcement is an exception to the minor-only ceiling.
        let ceiling = max(currentMajor, config.auto.enforceMinimumMajorVersion)
        return !config.auto.minorOnly || targetMajor <= ceiling
    }
}

/// Returns nil when activity cannot be established safely. No installer is launched.
func installationIsActive() -> Bool? {
    let path = managedBase + "/install.lock"
    if FileManager.default.fileExists(atPath: path) {
        let fd = open(path, O_RDWR | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { return errno == EWOULDBLOCK ? true : nil }
        flock(fd, LOCK_UN)
    }
    for name in ["startosinstall", "softwareupdate", "mist", "osinstallersetupd", "installer"] {
        let (_, result) = runDirect("/usr/bin/pgrep", ["-x", name])
        if result == 0 { return true }
        if result != 1 { return nil }
    }
    return false
}

extension CLIDeferralState {
    /// Recover only demonstrably obsolete flags. A modern staged install still waits for a reboot.
    mutating func recoverInstallation(running: String, boot: Double?, target: String, active: Bool?) -> String? {
        guard installStarted, active == false else { return nil }
        let intended = installTargetVersion ?? target
        if installCompleted && !intended.isEmpty && versionGTE(running, intended) {
            installStarted = false
            lastRecoveryMessage = "Cleared legacy pending flag; macOS already meets the completed target."
            return lastRecoveryMessage
        }
        if reconcileInstallation(running: running, boot: boot, fallbackTarget: target) {
            lastRecoveryMessage = "Verified completed macOS installation after restart."
            return lastRecoveryMessage
        }
        if !installStarted {
            lastRecoveryMessage = "The restart did not reach the target; installation may be retried."
            return lastRecoveryMessage
        }
        // Legacy flags with no target or boot evidence cannot represent a verified staged installation.
        // Only release these when no installer/lock is active and the owning workflow is gone.
        let ownerAlive = installOwnerPID.map { kill($0, 0) == 0 || errno == EPERM } ?? false
        if installTargetVersion == nil && installBootTimestamp == nil && !ownerAlive {
            failInstallation()
            lastRecoveryMessage = "Recovered obsolete installation flags without staging metadata; no installer is active."
            return lastRecoveryMessage
        }
        return nil
    }
}

/// A required target is a minimum. Native offers may satisfy it with a newer
/// stable point release in the running generation, never a different major.
struct NativeOSUpdate:Equatable {
    let label:String,title:String,version:String
    let restart:Bool,beta:Bool
    static func parse(_ output:String)->[Self] {
        var result:[Self]=[],label:String?,metadata:[String]=[]
        func append(){
            guard let label,!label.isEmpty,!label.hasPrefix("-"),!label.contains("\u{0}") else{return}
            let fields=metadata.joined(separator:" ").components(separatedBy:",").reduce(into:[String:String]()){values,part in
                guard let colon=part.firstIndex(of:":") else{return}
                let key=part[..<colon].trimmingCharacters(in:.whitespaces).lowercased()
                values[key]=part[part.index(after:colon)...].trimmingCharacters(in:.whitespaces)
            }
            guard let title=fields["title"],title.lowercased().hasPrefix("macos"),let version=fields["version"],numericOSVersion(version) != nil else{return}
            let beta=(title+" "+label).range(of:#"\b(beta|seed|preview|rc)\b|release candidate"#,options:[.regularExpression,.caseInsensitive]) != nil
            result.append(.init(label:label,title:title,version:version,restart:fields["action"]?.lowercased()=="restart",beta:beta))
        }
        for line in output.components(separatedBy:.newlines){
            let text=line.trimmingCharacters(in:.whitespaces)
            if text.hasPrefix("* Label:"){append();label=String(text.dropFirst(8)).trimmingCharacters(in:.whitespaces);metadata=[]}
            else if label != nil {metadata.append(text)}
        }
        append();return result
    }
}
enum MacOSUpdateRoute:Equatable {case compliant,native(NativeOSUpdate),fullInstaller,unavailable(String)}
enum MacOSUpdateRouting {
    static func route(running:String,target:String,listing:String,catalogSucceeded:Bool=true,maximumMajor:Int=0,skipBetas:Bool=true,restartOnly:Bool=true)->MacOSUpdateRoute {
        guard let current=numericOSVersion(running),let required=numericOSVersion(target) else{return .unavailable("The running or target macOS version is invalid.")}
        guard maximumMajor<=0 || required[0]<=maximumMajor else{return .unavailable("The target exceeds the configured macOS generation limit.")}
        if !current.lexicographicallyPrecedes(required){return .compliant}
        if required[0]>current[0]{return .fullInstaller}
        guard catalogSucceeded else{return .unavailable("Apple Software Update could not be checked. No full installer was downloaded for this same-generation update.")}
        let offers=NativeOSUpdate.parse(listing).filter{offer in
            guard let v=numericOSVersion(offer.version) else{return false}
            return v[0]==current[0] && !v.lexicographicallyPrecedes(required) && current.lexicographicallyPrecedes(v) && (maximumMajor<=0 || v[0]<=maximumMajor) && (!skipBetas || !offer.beta) && (!restartOnly || offer.restart)
        }.sorted{lhs,rhs in
            let a=numericOSVersion(lhs.version)!,b=numericOSVersion(rhs.version)!
            return a==b ? lhs.label<rhs.label:b.lexicographicallyPrecedes(a)
        }
        if let offer=offers.first{return .native(offer)}
        return .unavailable("No eligible native macOS update meeting \(target) is currently offered in macOS \(current[0]). PUSH will retry discovery; it will not automatically download a full installer for this same-generation update.")
    }
}

/// Shared bounded catalog lookup. Failure is data, never permission to fetch a
/// full image for a same-generation update.
func nativeOSUpdateCatalog()->(String,Int32) {
    do{return (try discoveryOutput("/usr/sbin/softwareupdate",["--list"],timeout:180),0)}
    catch{cliLog("[Native Update] Apple catalog lookup failed: \(error.localizedDescription)");return ("",1)}
}

/// Isolated, explicitly selected Jamf Self Service offers. No campaign timing.
enum SelfServiceOfferPolicy {
    static let supportedMajors=Set([26,27])
    static let popupStates=Set(["downloading","preflightDisk","preflightPower","rebooting"])
    static func latest(major:Int,running:String,updates:[AutoCheckCommand.DetectedUpdate])->AutoCheckCommand.DetectedUpdate? {
        guard supportedMajors.contains(major),let current=numericOSVersion(running),current[0]<=major else{return nil}
        return updates.filter{item in guard let v=numericOSVersion(item.version) else{return false};return v[0]==major && !item.isBeta && current.lexicographicallyPrecedes(v)}.max{numericOSVersion($0.version)!.lexicographicallyPrecedes(numericOSVersion($1.version)!)}
    }
    static func withManagedAuthorization(_ offer:CLIConfig,installed:CLIConfig)->CLIConfig {
        var result=offer
        result.auth.localAccount=installed.auth.localAccount
        // Existing managed Keychain/LAPS settings only; no plaintext local password
        // fallback is exported or imported into this new offer route.
        result.auth.localPassword=""
        result.jamf=installed.jamf
        result.auth.promptUserForInstall=true
        return result
    }
    static func isolated(_ base:CLIConfig,major:Int,version:String,running:String)->CLIConfig? {
        guard supportedMajors.contains(major),numericOSVersion(version)?.first==major,let current=numericOSVersion(running),current[0]<=major else{return nil}
        var c=base
        c.update.targetVersion=version;c.update.macOSName=base.update.macOSName.isEmpty ? "macOS":base.update.macOSName;c.update.releaseType=current[0]<major ? "major":"minor"
        c.update.deadline="";c.update.automaticDeadline="";c.update.automaticDeadlineTarget="";c.update.autoInstallAfterDeadline=false;c.update.silentInstallAfterDeadline=false
        c.auto.enabled=false;c.auto.trackLatest=false;c.auto.maximumMajorVersion=major;c.auto.enforceMinimumMajorVersion=major;c.auto.autoInstallNonSystemUpdates=false
        c.apps.enabled=false;c.entra.enabled=false;c.uptime.enabled=false;c.compliance.wallpaperEnabled=false
        c.auth.promptUserForInstall=true;c.debug.dryRun=false
        return c
    }
}

// Observes only the installer's documented prepare-complete signal. The callback
// never starts an installer and cannot run before the associated child exists.
final class PreparedRestartObserver {
    private let queue=DispatchQueue(label:"com.push.prepared-restart")
    private let source:DispatchSourceSignal
    private var process:Process?
    private var received=false,finished=false,announced=false
    private let callback:(Process)->Void
    init(callback:@escaping(Process)->Void){
        self.callback=callback
        signal(SIGUSR1,SIG_IGN)
        source=DispatchSource.makeSignalSource(signal:SIGUSR1,queue:queue)
        source.setEventHandler{[weak self] in self?.receive()}
        source.resume()
    }
    func started(process:Process){queue.async{[weak self] in self?.process=process;self?.announce()}}
    private func receive(){received=true;announce()}
    private func announce(){
        guard received,!finished,!announced,let process,process.isRunning else{return}
        announced=true;callback(process)
    }
    func stop(){queue.async{[weak self] in self?.finished=true;self?.source.cancel()}}
    deinit{source.cancel()}
}

/// Apple InstallAssistant bundles can intentionally omit SharedSupport resources
/// from their outer resource seal. Validate the executable we actually launch
/// with Apple-anchored code-signature checks. Gatekeeper app assessment applies
/// only to ordinary top-level bundles, not embedded command-line tools (TN2206).
/// Never disable Gatekeeper or accept a non-Apple installer on this route.
struct InstallerCodeSignature {
    var status:Int32
    var identifier:String=""
}
struct InstallerTrustResult {
    var accepted:Bool
    var reason:String
}
enum AppleInstallerTrust {
    static func prepareDownloadDirectory()->Bool {
        let path=managedBase+"/downloads"
        do {
            try FileManager.default.createDirectory(atPath:path,withIntermediateDirectories:true,attributes:[.posixPermissions:0o755])
        } catch {cliLog("[InstallerValidation] Cannot create installer cache: \(error.localizedDescription)");return false}
        var cursor=path
        while cursor != "/" {
            var item=stat()
            guard lstat(cursor,&item)==0,item.st_uid==0,item.st_mode&S_IFMT==S_IFDIR,item.st_mode&0o022==0 else {
                cliLog("[InstallerValidation] Unprotected installer cache directory: \(cursor)");return false
            }
            cursor=(cursor as NSString).deletingLastPathComponent
        }
        return true
    }
    static func validate(_ path:String,target:String,
                         protected:(String)->Bool=protectedBundle,
                         matches:(String,String)->Bool=InstallerValidation.matches,
                         signature:(String,Bool)->InstallerCodeSignature=codeSignature,
                         assess:(String)->Int32={runDirect("/usr/sbin/spctl",["--assess","--type","execute",$0]).1},
                         image:(String)->Bool=verifyImage,
                         nested:(String)->Bool=verifyNestedCode)->InstallerTrustResult {
        guard protected(path) else{return .init(accepted:false,reason:"Installer files must be root-owned and protected from modification; no installer was launched.")}
        guard matches(path,target) else{return .init(accepted:false,reason:"Installer product version could not be verified for the requested macOS target.")}
        let outer=signature(path,false)
        // Only this exact Apple resource-format error may use the specialized
        // route. Invalid signatures, old v1 seals and trust failures still stop.
        let customRules=outer.status == errSecCSWeakResourceRules
        let verified=customRules ? signature(path,true):outer
        guard verified.status==errSecSuccess,
              verified.identifier=="com.apple.InstallAssistant" || verified.identifier.hasPrefix("com.apple.InstallAssistant.") else {
            return .init(accepted:false,reason:"The installer app did not pass Apple signature verification (status \(verified.status)); no installer was launched.")
        }
        let executable=path+"/Contents/Resources/startosinstall"
        let tool=signature(executable,false)
        guard tool.status==errSecSuccess else{return .init(accepted:false,reason:"startosinstall did not pass strict Apple signature verification (status \(tool.status)); credentials were not submitted.")}
        if customRules {
            // spctl rejects this Apple installer format's omitted resources and
            // cannot assess its embedded command-line tool as a top-level app.
            // This route requires Apple's cryptographic signature on BOTH app
            // code and helper, the protected cache, target version and image CRC.
            // No Gatekeeper/quarantine policy or system setting is changed.
            guard nested(path) else{return .init(accepted:false,reason:"A nested installer executable did not pass Apple signature verification. The rejected file and status are recorded in the log; credentials were not submitted.")}
            guard image(path+"/Contents/SharedSupport/SharedSupport.dmg") else{return .init(accepted:false,reason:"The installer disk image did not pass integrity verification; credentials were not submitted.")}
        }else{
            let assessment=assess(path)
            guard assessment==0 else{return .init(accepted:false,reason:"Gatekeeper rejected the installer app (exit \(assessment)); credentials were not submitted.")}
        }
        return .init(accepted:true,reason:customRules ? "Apple InstallAssistant and nested code signatures, strict startosinstall signature and disk-image integrity verified; Apple installer resource rules handled.":"Apple installer signatures and top-level app Gatekeeper assessment verified.")
    }
    /// /Applications is normally writable by the admin group. Move a
    /// root-owned downloaded installer into PUSH's protected cache before
    /// validation/execution, so another user cannot swap its path afterwards.
    /// This is a reversible cache move, not an installer launch or redownload.
    static func securedInstaller(_ path:String)->String? {
        if protectedBundle(path){return path}
        let source=URL(fileURLWithPath:path).standardizedFileURL
        let cache=URL(fileURLWithPath:managedBase).appendingPathComponent("downloads")
        if source.deletingLastPathComponent()==cache,prepareDownloadDirectory() {
            guard normalizeCachePermissions(path) else{return nil}
            if let failure=protectionFailure(path) {
                cliLog("[InstallerValidation] Cached installer protection check failed: "+failure)
                return nil
            }
            return path
        }
        var entry=stat()
        guard source.path==path,source.deletingLastPathComponent().path=="/Applications",
              source.pathExtension=="app",source.lastPathComponent.hasPrefix("Install"),
              lstat(path,&entry)==0,entry.st_uid==0,entry.st_mode&S_IFMT==S_IFDIR,entry.st_mode&0o022==0 else{return nil}
        var cursor=cache.path
        while cursor != "/" {
            guard lstat(cursor,&entry)==0,entry.st_uid==0,entry.st_mode&S_IFMT==S_IFDIR,entry.st_mode&0o022==0 else{return nil}
            cursor=(cursor as NSString).deletingLastPathComponent
        }
        let destination=cache.appendingPathComponent("Install macOS Cached-"+UUID().uuidString+".app")
        do {
            try FileManager.default.moveItem(at:source,to:destination)
            cliLog("[InstallerValidation] Moved the cached installer into PUSH's protected downloads folder; no redownload was requested.")
            guard normalizeCachePermissions(destination.path) else{return nil}
            if let failure=protectionFailure(destination.path) {
                cliLog("[InstallerValidation] Cached installer protection check failed: "+failure)
                return nil
            }
            return destination.path
        }catch{cliLog("[InstallerValidation] Installer cache move failed: \(error.localizedDescription)");return nil}
    }
    /// Extraction may preserve group-writable modes in Apple's app. Only remove
    /// write bits from existing root-owned objects after securing the parent.
    /// Never follow symlinks, adopt user-owned content, or change executable bits.
    static func normalizeCachePermissions(_ path:String)->Bool {
        let url=URL(fileURLWithPath:path).standardizedFileURL
        guard url.path==path,url.pathExtension=="app",
              url.deletingLastPathComponent().path==managedBase+"/downloads",
              prepareDownloadDirectory() else{return false}
        guard chmod(managedBase+"/downloads",0o700)==0,repairExtractedPayloadOwnership(url) else{return false}
        return removeWritableModes(url,owner:0)
    }
    /// Apple installer extraction can preserve nobody/_unknown (99) ownership
    /// on these two payload objects. Adopt only that identity and those exact
    /// paths, never an end-user UID or executable. Trust checks still follow.
    static func repairExtractedPayloadOwnership(_ root:URL,
        inspect:(String)->(uid_t,mode_t)?={path in var s=stat();return lstat(path,&s)==0 ? (s.st_uid,s.st_mode&S_IFMT):nil},
        adopt:(String)->Bool=adoptUnknownPayload)->Bool {
        let paths=[("Contents/SharedSupport",mode_t(S_IFDIR)),("Contents/SharedSupport/SharedSupport.dmg",mode_t(S_IFREG))]
        var repairs=[String]()
        for (relative,kind) in paths {
            let path=root.appendingPathComponent(relative).path
            guard let (uid,type)=inspect(path),type==kind,[uid_t(0),uid_t(99)].contains(uid) else {
                cliLog("[InstallerValidation] Unexpected payload ownership or type: "+path);return false
            }
            if uid==99 {repairs.append(path)}
        }
        for path in repairs {
            guard adopt(path) else{cliLog("[InstallerValidation] Could not repair extracted payload ownership: "+path);return false}
            cliLog("[InstallerValidation] Repaired _unknown ownership on cached payload: "+path)
        }
        return true
    }
    static func adoptUnknownPayload(_ path:String)->Bool {
        let fd=open(path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
        guard fd>=0 else{return false}
        defer{close(fd)}
        var item=stat()
        guard fstat(fd,&item)==0,item.st_uid==99,[S_IFREG,S_IFDIR].contains(item.st_mode&S_IFMT) else{return false}
        return fchown(fd,0,0)==0
    }
    static func removeWritableModes(_ root:URL,owner:uid_t)->Bool {
        var complete=true
        guard let entries=FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil,options:[],errorHandler:{_,_ in complete=false;return false}) else{return false}
        var paths=[root]
        for case let file as URL in entries {
            guard paths.count<100_000 else{return false}
            paths.append(file)
        }
        guard complete else{return false}
        // Inspect the whole tree before changing anything. Reject user-owned
        // files, escaping links and special devices rather than claiming trust.
        for file in paths {
            var item=stat()
            guard lstat(file.path,&item)==0,item.st_uid==owner else {
                cliLog("[InstallerValidation] Cannot secure non-owned/unreadable installer item: "+file.path);return false
            }
            if item.st_mode&S_IFMT==S_IFLNK {
                let target=file.resolvingSymlinksInPath().path
                guard target.hasPrefix(root.path+"/"),stat(target,&item)==0,item.st_uid==owner else {
                    cliLog("[InstallerValidation] Cannot secure installer link: "+file.path+" -> "+target);return false
                }
            }else if ![S_IFREG,S_IFDIR].contains(item.st_mode&S_IFMT) {return false}
        }
        for file in paths {
            var before=stat()
            guard lstat(file.path,&before)==0,before.st_uid==owner else{return false}
            if before.st_mode&S_IFMT==S_IFLNK || before.st_mode&0o022==0 {continue}
            let fd=open(file.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
            guard fd>=0 else{return false}
            var opened=stat()
            let valid=fstat(fd,&opened)==0 && opened.st_ino==before.st_ino && opened.st_dev==before.st_dev && opened.st_uid==owner
            let changed=valid && fchmod(fd,opened.st_mode&0o7777 & ~mode_t(0o022))==0
            close(fd)
            guard changed else{return false}
        }
        return true
    }
    static func codeSignature(_ path:String,allowInstallerResources:Bool)->InstallerCodeSignature {
        var code:SecStaticCode?,requirement:SecRequirement?
        let created=SecStaticCodeCreateWithPath(URL(fileURLWithPath:path) as CFURL,SecCSFlags(),&code)
        guard created==errSecSuccess,let code else{return .init(status:created)}
        let required=SecRequirementCreateWithString("anchor apple" as CFString,SecCSFlags(),&requirement)
        guard required==errSecSuccess,let requirement else{return .init(status:required)}
        // Resource exclusion is narrowly gated above by the exact custom-rule
        // error. Executable hashes and the Apple signing chain remain required.
        let raw=kSecCSCheckAllArchitectures | (allowInstallerResources ? kSecCSDoNotValidateResources:kSecCSStrictValidate)
        let status=SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:raw),requirement)
        guard status==errSecSuccess else{return .init(status:status)}
        var info:CFDictionary?
        let copied=SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info)
        guard copied==errSecSuccess,let fields=info as? [String:Any],let identifier=fields[kSecCodeInfoIdentifier as String] as? String else{return .init(status:copied==errSecSuccess ? errSecCSUnsigned:copied)}
        return .init(status:status,identifier:identifier)
    }
    /// The outer Apple resource exception must not hide modified executable
    /// dependencies. Verify every Mach-O slice separately against Apple's anchor.
    static func verifyNestedCode(_ path:String)->Bool {
        checkNestedCode(path,signature:codeSignature)
    }
    /// Called only for the validated Apple InstallAssistant custom-resource
    /// route. Its frameworks/plugins can carry the same legacy omit rules as
    /// the outer app. Only that exact error permits code-only revalidation;
    /// Apple's signing anchor and every architecture's code hashes still apply.
    static func nestedSignature(_ path:String,signature:(String,Bool)->InstallerCodeSignature=codeSignature)->InstallerCodeSignature {
        let strict=signature(path,false)
        guard strict.status==errSecCSWeakResourceRules,
              URL(fileURLWithPath:path).lastPathComponent != "startosinstall" else{return strict}
        let result=signature(path,true)
        if result.status==errSecSuccess {
            cliLog("[InstallerValidation] Apple nested code verified with installer resource rules: "+path)
        }
        return result
    }
    static func checkNestedCode(_ path:String,signature:(String,Bool)->InstallerCodeSignature)->Bool {
        let root=URL(fileURLWithPath:path)
        var complete=true,count=0
        guard let files=FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey],options:[],errorHandler:{_,_ in complete=false;return false}) else{return false}
        let magic:Set<Data>=Set([[0xfe,0xed,0xfa,0xce],[0xfe,0xed,0xfa,0xcf],[0xce,0xfa,0xed,0xfe],[0xcf,0xfa,0xed,0xfe],[0xca,0xfe,0xba,0xbe],[0xbe,0xba,0xfe,0xca],[0xca,0xfe,0xba,0xbf],[0xbf,0xba,0xfe,0xca]].map{Data($0.map{UInt8($0)})})
        var seen=Set<String>(),executables=0
        for case let file as URL in files {
            count+=1;guard count<=100_000 else{return false}
            let resolved=file.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(root.path+"/") else{return false}
            guard (try? resolved.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true,seen.insert(resolved.path).inserted else{continue}
            guard let handle=try? FileHandle(forReadingFrom:resolved) else{return false}
            let prefix=try? handle.read(upToCount:4);try? handle.close()
            guard let prefix else{return false}
            if magic.contains(prefix) {
                executables+=1
                let result=nestedSignature(resolved.path,signature:signature)
                guard result.status==errSecSuccess,!result.identifier.isEmpty else {
                    let reason=(SecCopyErrorMessageString(result.status,nil) as String?) ?? "Unknown signature error"
                    cliLog("[InstallerValidation] Rejected nested executable: "+resolved.path+" status="+String(result.status)+" "+reason)
                    return false
                }
            }
        }
        return complete && executables>0
    }
    static func verifyImage(_ path:String)->Bool {
        guard FileManager.default.isReadableFile(atPath:path) else{return false}
        let (output,status)=runDirect("/usr/bin/hdiutil",["verify",path])
        return validImageResult(output,status:status)
    }
    static func validImageResult(_ output:String,status:Int32)->Bool {
        status==0 && output.contains("is VALID") && !output.lowercased().contains("no checksum")
    }
    static func protectedBundle(_ path:String)->Bool {
        protectionFailure(path)==nil
    }
    static func protectionFailure(_ path:String)->String? {
        let bundle=URL(fileURLWithPath:path).standardizedFileURL
        guard bundle.pathExtension=="app",bundle.path==path else{return "Noncanonical installer path: "+path}
        var cursor=bundle.path
        while cursor != "/" {
            var entry=stat()
            guard lstat(cursor,&entry)==0 else{return "Cannot inspect directory: "+cursor}
            guard entry.st_uid==0,entry.st_mode&S_IFMT==S_IFDIR,entry.st_mode&0o022==0 else{return "Unprotected directory: "+cursor+" uid="+String(entry.st_uid)+" mode="+String(entry.st_mode & 0o7777,radix:8)}
            cursor=(cursor as NSString).deletingLastPathComponent
        }
        var complete=true,count=0
        guard let files=FileManager.default.enumerator(at:bundle,includingPropertiesForKeys:nil,options:[],errorHandler:{_,_ in complete=false;return false}) else{return "Cannot enumerate installer: "+path}
        for case let file as URL in files {
            count+=1;guard count<=100_000 else{return "Installer has too many filesystem entries"}
            var entry=stat()
            guard lstat(file.path,&entry)==0 else{return "Cannot inspect installer item: "+file.path}
            guard entry.st_uid==0 else{return "Non-root installer item: "+file.path+" uid="+String(entry.st_uid)}
            if entry.st_mode&S_IFMT==S_IFLNK {
                let target=file.resolvingSymlinksInPath().path
                guard target.hasPrefix(bundle.path+"/"),stat(target,&entry)==0,entry.st_uid==0,entry.st_mode&0o022==0 else{return "Unprotected installer link: "+file.path+" -> "+target}
            }else {
                guard [S_IFREG,S_IFDIR].contains(entry.st_mode&S_IFMT),entry.st_mode&0o022==0 else{return "Unprotected installer item: "+file.path+" mode="+String(entry.st_mode & 0o7777,radix:8)}
            }
        }
        return complete ? nil:"Installer enumeration was incomplete"
    }
}
