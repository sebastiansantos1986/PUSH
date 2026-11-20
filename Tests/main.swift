// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation
import Security

let cliVersion = "test-only"
var count = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fputs("FAIL: \(name)\n", stderr); exit(1) }
    count += 1
    print("PASS: \(name)")
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("push-tests-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }

// Exercise the real save orchestration with an in-memory Security backend.
// No Keychain item or password is read, written, deleted or unlocked.
let keychainQuery:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"fixture-service",kSecAttrAccount as String:"fixture-user"]
let fixtureSecret=Data("fixture-only-password".utf8)
var updateCalls=0,addCalls=0,accessCalls=0
let changed=PushKeychain.writePassword(query:keychainQuery,password:fixtureSecret,update:{query,attributes in
    updateCalls+=1
    check(query[kSecAttrAccount as String] as? String=="fixture-user","credential update retains account scope")
    check(Set(attributes.keys)==[kSecValueData as String] && attributes[kSecValueData as String] as? Data==fixtureSecret,"existing credential updates only password data, never ACL or access groups")
    return errSecSuccess
},add:{_ in addCalls+=1;return errSecSuccess},newAccess:{accessCalls+=1;return "fixture-private-access"})
check(changed && updateCalls==1 && addCalls==0 && accessCalls==0,"existing credential keeps its ACL without creation or permission replacement")
for denied in [errSecAuthFailed,errSecInteractionNotAllowed,errSecUserCanceled] {
    var calls=0
    let saved=PushKeychain.writePassword(query:keychainQuery,password:fixtureSecret,update:{_,_ in denied},add:{_ in calls+=1;return errSecSuccess},newAccess:{calls+=1;return "forbidden"})
    check(!saved && calls==0,"denied credential save fails closed without ACL reset, deletion or retry: \(denied)")
}
var createdAccess=0
let created=PushKeychain.writePassword(query:keychainQuery,password:fixtureSecret,update:{_,_ in errSecItemNotFound},add:{item in
    check(item[kSecAttrAccess as String] as? String=="fixture-private-access" && item[kSecValueData as String] as? Data==fixtureSecret,"new credential alone receives private access settings and password")
    return errSecSuccess
},newAccess:{createdAccess+=1;return "fixture-private-access"})
check(created && createdAccess==1,"new item creates its private ACL once")
var duplicateAdds=0
let duplicate=PushKeychain.writePassword(query:keychainQuery,password:fixtureSecret,update:{_,_ in errSecItemNotFound},add:{_ in duplicateAdds+=1;return errSecDuplicateItem},newAccess:{"fixture-private-access"})
check(!duplicate && duplicateAdds==1,"concurrent item creation does not trigger a destructive replacement or retry")
var failedAccessAdds=0
check(!PushKeychain.writePassword(query:keychainQuery,password:fixtureSecret,update:{_,_ in errSecItemNotFound},add:{_ in failedAccessAdds+=1;return errSecSuccess},newAccess:{nil}) && failedAccessAdds==0,"private ACL creation failure cannot add an unprotected credential")

check(sameOSVersion("26.1", "26.1.0"), "normalize trailing zero")
check(!sameOSVersion("26.1", "26.10"), "reject version prefix collision")
for malformed in ["", "26", "26..1", "26.1beta", "26.1;touch x", "26.1.0.1", "２６.１"] {
    check(numericOSVersion(malformed) == nil, "reject malformed target \(malformed)")
}
check(versionGTE("27.0", "27") && versionGTE("27", "27.0"), "major-only and dotted versions are equally compliant")
check(!versionGTE("26.9", "27"), "older OS still counts as a pending update")
check(!allowsUserPasswordPrompts, "legacy password-saving popups remain disabled")
let listing = """
* Label: macOS-test-26.10
    Title: macOS, Version: 26.10, Size: 123KiB, Recommended: YES, Action: restart,
* Label: macOS-test-26.1
    Title: macOS, Version: 26.1, Size: 123KiB, Recommended: YES, Action: restart,
"""
check(nativeUpdateLabel(version: "26.1", output: listing, restartOnly: true) == "macOS-test-26.1", "native selection matches entire version")
check(nativeUpdateLabel(version: "26.2", output: listing) == nil, "unavailable native target rejected")
check(nativeUpdateLabel(version: "26.1", output: listing.replacingOccurrences(of: "Action: restart,", with: ""), restartOnly: true) == nil, "restart required for native install")

func fixture(_ name: String, version: String?) throws -> URL {
    let app = root.appendingPathComponent(name + ".app")
    let resources = app.appendingPathComponent("Contents/Resources")
    let support = app.appendingPathComponent("Contents/SharedSupport")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    // This fake executable is never run by version validation.
    let executable = resources.appendingPathComponent("startosinstall")
    try "#!/bin/sh\nexit 99\n".write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    if let version {
        let data = try PropertyListSerialization.data(fromPropertyList: ["System Image Info": ["version": version]], format: .xml, options: 0)
        try data.write(to: support.appendingPathComponent("InstallInfo.plist"))
    }
    return app
}
let wrong = try fixture("Install old macOS", version: "26.10")
let right = try fixture("Install correct macOS", version: "26.1.0")
let unknown = try fixture("Install unknown macOS", version: nil)
check(!InstallerValidation.matches(wrong.path, target: "26.1"), "wrong installer rejected")
check(InstallerValidation.matches(right.path, target: "26.1"), "matching product metadata accepted")
check(!InstallerValidation.matches(unknown.path, target: "26.1"), "unknown product metadata fails closed")
let foundInstaller = InstallerValidation.find(in: [root.path], target: "26.1")
check(foundInstaller.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == right.resolvingSymlinksInPath().path, "discovery skips wrong and unknown installers")
do {
    let managed=root.appendingPathComponent("managed"),apps=root.appendingPathComponent("Applications")
    let downloads=managed.appendingPathComponent("downloads")
    try FileManager.default.createDirectory(at:downloads,withIntermediateDirectories:true)
    try FileManager.default.createDirectory(at:apps,withIntermediateDirectories:false)
    let cached=downloads.appendingPathComponent("Install Mist macOS.app"),fallback=apps.appendingPathComponent("Install Software Update macOS.app")
    try FileManager.default.copyItem(at:right,to:cached)
    check(InstallerValidation.findForInstall(target:"26.1",managedRoot:managed.path,applications:apps.path).map { URL(fileURLWithPath:$0).resolvingSymlinksInPath().path }==cached.resolvingSymlinksInPath().path,"post-download discovery finds Mist output when Applications contains no installer")
    try FileManager.default.copyItem(at:right,to:fallback)
    check(InstallerValidation.findForInstall(target:"26.1",managedRoot:managed.path,applications:apps.path).map { URL(fileURLWithPath:$0).resolvingSymlinksInPath().path }==cached.resolvingSymlinksInPath().path,"existing and downloaded installers consistently prefer the managed cache")
    try FileManager.default.removeItem(at:cached)
    check(InstallerValidation.findForInstall(target:"26.1",managedRoot:managed.path,applications:apps.path).map { URL(fileURLWithPath:$0).resolvingSymlinksInPath().path }==fallback.resolvingSymlinksInPath().path,"softwareupdate output remains discoverable in Applications")
    check(InstallerValidation.findForInstall(target:"27.2.1",managedRoot:managed.path,applications:apps.path)==nil,"discovery never substitutes an installer for another OS target")
}
try FileManager.default.removeItem(at: right.appendingPathComponent("Contents/Resources/startosinstall"))
check(!InstallerValidation.matches(right.path, target: "26.1"), "missing installer tool rejected")
let metadata = root.appendingPathComponent("asset.xml")
try PropertyListSerialization.data(fromPropertyList: ["Assets": [["OSVersion": "26.1"]]], format: .xml, options: 0).write(to: metadata)
check(InstallerValidation.productVersion(in: metadata) == "26.1", "modern MobileAsset metadata parsed")
try PropertyListSerialization.data(fromPropertyList: ["Assets": [["OSVersion": "26.1"], ["OSVersion": "26.2"]]], format: .xml, options: 0).write(to: metadata)
check(InstallerValidation.productVersion(in: metadata) == nil, "ambiguous asset versions rejected")

// Run only the validation decision logic. None of these fixture paths or
// signature/image/Gatekeeper operations can execute an installer.
do {
    let app="/fixture/Install macOS.app",tool="/fixture/Install macOS.app/Contents/Resources/startosinstall"
    func assess(strict:Int32=0,relaxed:Int32=0,helper:Int32=0,id:String="com.apple.InstallAssistant.GoldenGate",gate:Int32=0,payload:Bool=true,owned:Bool=true,version:Bool=true,nestedOK:Bool=true)->(InstallerTrustResult,[String]) {
        var calls:[String]=[]
        let result=AppleInstallerTrust.validate(app,target:"27.2.1",protected:{_ in owned},matches:{_,_ in version},signature:{path,resources in
            calls.append(path+" resources="+String(resources))
            if path==tool {return .init(status:helper,identifier:"startosinstall")}
            return .init(status:resources ? relaxed:strict,identifier:id)
        },assess:{path in calls.append("Gatekeeper "+path);return gate},image:{path in calls.append("Image "+path);return payload},nested:{path in calls.append("Nested "+path);return nestedOK})
        return (result,calls)
    }
    let appleTool=AppleInstallerTrust.codeSignature("/usr/bin/true",allowInstallerResources:false)
    let baseline=runDirect("/usr/bin/codesign",["--verify","--strict","--all-architectures","-R=anchor apple","/usr/bin/true"]).1
    check((baseline==0 && appleTool.status==errSecSuccess && !appleTool.identifier.isEmpty) || (baseline != 0 && appleTool.status != errSecSuccess),"real Security.framework agrees with strict system codesign and fails closed when host trust is unavailable")
    let unsigned=root.appendingPathComponent("unsigned-installer-fixture")
    try "#!/bin/sh\nexit 99\n".write(to:unsigned,atomically:true,encoding:.utf8)
    check(AppleInstallerTrust.codeSignature(unsigned.path,allowInstallerResources:false).status != errSecSuccess,"real Security.framework rejects an unsigned executable fixture without running it")
    let standard=assess()
    check(standard.0.accepted && standard.1.contains("Gatekeeper "+app),"ordinary top-level Apple installer still requires its Gatekeeper app assessment")
    let custom=assess(strict:errSecCSWeakResourceRules)
    check(custom.0.accepted && custom.1.contains(app+" resources=true") && custom.1.contains("Image "+app+"/Contents/SharedSupport/SharedSupport.dmg"),"Apple custom-resource installer requires separately verified app code, helper and image")
    check(!custom.1.contains(where:{$0.hasPrefix("Gatekeeper ")}),"Apple installer resource format is not assessed as a top-level app or embedded CLI app")
    check(!assess(strict:errSecCSWeakResourceRules,relaxed:errSecCSUnsigned).0.accepted,"custom resource rules never authorize unsigned app code")
    check(!assess(strict:errSecCSWeakResourceRules,relaxed:errSecCSReqFailed).0.accepted,"non-Apple certificate cannot use the installer resource exception")
    check(!assess(strict:errSecCSWeakResourceRules,helper:errSecCSUnsigned).0.accepted,"a valid outer installer cannot authorize an unsigned startosinstall")
    check(!assess(strict:errSecCSWeakResourceRules,helper:errSecCSWeakResourceRules).0.accepted,"resource relaxation never applies to the executed helper")
    check(!assess(strict:errSecCSWeakResourceRules,id:"com.apple.Terminal").0.accepted,"unrelated Apple app cannot impersonate InstallAssistant")
    check(!assess(strict:errSecCSWeakResourceRules,id:"com.apple.InstallAssistantImposter").0.accepted,"installer identifier family is checked at an exact component boundary")
    let revoked=assess(gate:3)
    check(!revoked.0.accepted && !revoked.1.contains(where:{$0.hasPrefix("Image ")}),"ordinary-app Gatekeeper denial stops before image or credential handoff")
    check(!assess(strict:errSecCSWeakResourceRules,nestedOK:false).0.accepted,"the Apple resource exception cannot hide a modified nested executable")
    var nestedCalls=[Bool]()
    let nestedPath=app+"/Contents/Frameworks/OSInstallerSetup.framework/Versions/A/OSInstallerSetup"
    let nestedRules=AppleInstallerTrust.nestedSignature(nestedPath,signature:{_,resources in nestedCalls.append(resources);return .init(status:resources ? errSecSuccess:errSecCSWeakResourceRules,identifier:"com.apple.OSInstallerSetup")})
    check(nestedRules.status==errSecSuccess && nestedCalls==[false,true],"nested Apple omit-rule format is revalidated with Apple-anchored code hashes")
    for rejection in [errSecCSUnsigned,errSecCSReqFailed,errSecCSSignatureFailed,errSecCSResourcesNotFound] {
        nestedCalls=[]
        let rejected=AppleInstallerTrust.nestedSignature(nestedPath,signature:{_,resources in nestedCalls.append(resources);return .init(status:rejection)})
        check(rejected.status==rejection && nestedCalls==[false],"ordinary nested signature failure cannot enter resource-format handling: "+String(rejection))
    }
    nestedCalls=[]
    let strictHelper=AppleInstallerTrust.nestedSignature(tool,signature:{_,resources in nestedCalls.append(resources);return .init(status:errSecCSWeakResourceRules)})
    check(strictHelper.status==errSecCSWeakResourceRules && nestedCalls==[false],"startosinstall remains strict even when scanning nested code")
    let rejectedNested=AppleInstallerTrust.nestedSignature(nestedPath,signature:{_,resources in .init(status:resources ? errSecCSReqFailed:errSecCSWeakResourceRules)})
    check(rejectedNested.status==errSecCSReqFailed,"nested resource-format handling still rejects a non-Apple signer")
    let nestedFixture=root.appendingPathComponent("Nested-code-fixture").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at:nestedFixture,withIntermediateDirectories:false)
    try Data([0xcf,0xfa,0xed,0xfe,0,0,0,0]).write(to:nestedFixture.appendingPathComponent("FrameworkExecutable"))
    check(AppleInstallerTrust.checkNestedCode(nestedFixture.path,signature:{_,resources in .init(status:resources ? errSecSuccess:errSecCSWeakResourceRules,identifier:"com.apple.fixture")}),"real tree scan handles a nested omit-rule signature through the gated verifier")
    check(!AppleInstallerTrust.checkNestedCode(nestedFixture.path,signature:{_,resources in .init(status:resources ? errSecCSSignatureFailed:errSecCSWeakResourceRules)}),"nested tree scan stops when executable hashes fail after resource-format handling")
    check(!assess(strict:errSecCSWeakResourceRules,payload:false).0.accepted,"unsealed installer payload must pass separate disk-image integrity validation")
    let tampered=assess(strict:-67061)
    check(!tampered.0.accepted && !tampered.1.contains(app+" resources=true"),"a tampered app signature cannot enter the custom-resource exception")
    let obsolete=assess(strict:-67007)
    check(!obsolete.0.accepted && !obsolete.1.contains(app+" resources=true"),"obsolete v1 envelopes do not qualify for the narrow custom-rule exception")
    check(!assess(owned:false).0.accepted && assess(owned:false).1.isEmpty,"unprotected installer files fail before signature or executable assessment")
    check(!assess(version:false).0.accepted && assess(version:false).1.isEmpty,"a mismatched OS target fails before signature or executable assessment")
    check(!AppleInstallerTrust.protectedBundle(root.appendingPathComponent("Install missing.app").path),"an absent/unprotected installer cannot be staged or executed")
    check(AppleInstallerTrust.validImageResult("hdiutil: verify: checksum of image is VALID",status:0),"disk image verification requires a positive integrity result")
    check(!AppleInstallerTrust.validImageResult("no checksum; is VALID",status:0),"an image without a checksum cannot satisfy payload validation")
    check(!AppleInstallerTrust.validImageResult("",status:0),"an empty successful image command is insufficient evidence")
    check(!AppleInstallerTrust.validImageResult("is VALID",status:1),"a failed image command remains a failure despite reassuring text")
    let cacheFixture=root.appendingPathComponent("Install Cache Fixture.app")
    try FileManager.default.createDirectory(at:cacheFixture,withIntermediateDirectories:false)
    let payload=cacheFixture.appendingPathComponent("payload")
    try Data("unchanged installer bytes".utf8).write(to:payload)
    try FileManager.default.setAttributes([.posixPermissions:0o775],ofItemAtPath:payload.path)
    try FileManager.default.setAttributes([.posixPermissions:0o775],ofItemAtPath:cacheFixture.path)
    let link=cacheFixture.appendingPathComponent("internal-link")
    try FileManager.default.createSymbolicLink(atPath:link.path,withDestinationPath:"payload")
    check(AppleInstallerTrust.removeWritableModes(cacheFixture,owner:getuid()),"cache permission repair accepts internal links and owned writable files")
    let mode=(try FileManager.default.attributesOfItem(atPath:payload.path)[.posixPermissions] as! NSNumber).intValue
    let payloadBytes=try Data(contentsOf:payload)
    check(mode==0o755 && payloadBytes==Data("unchanged installer bytes".utf8),"cache repair removes write permissions without changing executable bits or payload bytes")
    let escaping=cacheFixture.appendingPathComponent("outside-link")
    try FileManager.default.createSymbolicLink(atPath:escaping.path,withDestinationPath:"/usr/bin/true")
    try FileManager.default.setAttributes([.posixPermissions:0o775],ofItemAtPath:payload.path)
    check(!AppleInstallerTrust.removeWritableModes(cacheFixture,owner:getuid()),"escaping links stop cache repair")
    let rejectedMode=(try FileManager.default.attributesOfItem(atPath:payload.path)[.posixPermissions] as! NSNumber).intValue
    check(rejectedMode==0o775,"unsafe tree is rejected before any permission changes")
    try FileManager.default.removeItem(at:escaping)
    check(!AppleInstallerTrust.removeWritableModes(cacheFixture,owner:getuid()+1),"cache repair refuses files owned by another account")
    var adopted=[String]()
    let adoption=AppleInstallerTrust.repairExtractedPayloadOwnership(cacheFixture,inspect:{path in (99,path.hasSuffix(".dmg") ? mode_t(S_IFREG):mode_t(S_IFDIR))},adopt:{adopted.append($0);return true})
    check(adoption && adopted.count==2 && adopted.allSatisfy{$0.hasPrefix(cacheFixture.path+"/Contents/SharedSupport")},"only the two extracted _unknown payload entries are adopted in the cache")
    adopted=[]
    check(!AppleInstallerTrust.repairExtractedPayloadOwnership(cacheFixture,inspect:{path in (path.hasSuffix(".dmg") ? 501:99,path.hasSuffix(".dmg") ? mode_t(S_IFREG):mode_t(S_IFDIR))},adopt:{adopted.append($0);return true}) && adopted.isEmpty,"user-owned payload fails before any ownership changes")
    check(!AppleInstallerTrust.repairExtractedPayloadOwnership(cacheFixture,inspect:{_ in (99,mode_t(S_IFLNK))},adopt:{_ in true}),"payload ownership repair refuses symlinks")
}

let secret = "  p'a\"ss\\word`literal`$(touch should-not-exist)$HOME  "
let (echoed, catStatus) = runDirect("/bin/cat", [], input: secret + "\n")
check(catStatus == 0 && echoed == secret + "\n", "password bytes and whitespace survive stdin exactly")
check(!FileManager.default.fileExists(atPath: "should-not-exist"), "password metacharacters never execute")
let (arguments, _) = runDirect("/bin/sh", ["-c", "/bin/ps -o args= -p $$; /bin/cat"], input: secret)
check(!String(arguments.split(separator: "\n").first ?? "").contains(secret), "password absent from process arguments")
check(runDirect("/bin/sh", ["-c", "exit 7"]).1 == 7, "child failure status preserved")
check(runDirect("/nonexistent/push-test", []).1 == -1, "launch failure reported")
let (large, largeStatus) = runDirect("/usr/bin/awk", ["BEGIN { for (i=0; i<200000; i++) print \"progress\" }"])
check(largeStatus == 0 && large.utf8.count <= 1_048_576, "large output drains without deadlock and retained output is bounded")
let quoted = shellArgument("a'b\"$(printf unexpected)")
check(runDirect("/bin/sh", ["-c", "printf %s " + quoted]).0 == "a'b\"$(printf unexpected)", "UI error quoting keeps shell syntax literal")

var state = CLIDeferralState()
state.beginInstallation(target: "26.1", running: "26.0", boot: 100)
check(state.installStarted && !state.installCompleted, "begin is pending")
check(!state.reconcileInstallation(running: "26.1", boot: 100, fallbackTarget: "26.1") && state.installStarted, "same boot cannot mark completion")
check(state.reconcileInstallation(running: "26.1", boot: 200, fallbackTarget: "26.2") && state.installCompleted && !state.installStarted, "post-reboot verification uses original install target")
check(!state.reconcileInstallation(running: "26.1", boot: 200, fallbackTarget: "26.1"), "completion only emitted once")
state.beginInstallation(target: "26.1", running: "26.0", boot: 100)
check(!state.reconcileInstallation(running: "26.0", boot: 200, fallbackTarget: "26.1") && !state.installStarted && !state.installCompleted, "failed reboot clears pending and permits retry")
state.beginInstallation(target: "26.2", running: "26.0", boot: 100)
check(!state.reconcileInstallation(running: "26.1", boot: 200, fallbackTarget: "26.2") && !state.installCompleted, "partial upgrade never marks target complete")
state.beginInstallation(target: "26.1", running: "26.0", boot: 100)
state.failInstallation()
check(!state.installStarted && !state.installCompleted && state.installTargetVersion == nil, "launch and nonzero failure reset state")
var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CLIDeferralState())) as! [String: Any]
legacy.removeValue(forKey: "installTargetVersion")
legacy.removeValue(forKey: "installBootTimestamp")
check((try? JSONDecoder().decode(CLIDeferralState.self, from: JSONSerialization.data(withJSONObject: legacy))) != nil, "existing state JSON remains readable")
let before = FileManager.default.contents(atPath: statePath)
var config = CLIConfig()
config.update.targetVersion = "99.1"
config.debug.dryRun = true
InstallWorkflow(config: config).run()
check(FileManager.default.contents(atPath: statePath) == before, "dry-run installation leaves state untouched")
check(!verifyLocalPassword(account: "", password: ""), "missing account validation fails closed")
let originalYAML = """
# keep this comment
jamf:
  clientSecret: "unrelated-secret"
  laps:
    enabled: true
    clientSecret: "old-laps-secret"
auth:
  localAccount: "oldadmin"
  localPassword: |
    old-password-continuation
update:
  targetVersion: "26.1"
"""
let cleanLAPS = updatingYAMLString(originalYAML, section: ["jamf", "laps"], field: "clientSecret", value: "")
check(!cleanLAPS.contains("old-laps-secret") && cleanLAPS.contains("unrelated-secret"), "LAPS migration removes only nested credential")
let cleanPassword = updatingYAMLString(cleanLAPS, section: ["auth"], field: "localPassword", value: "")
check(!cleanPassword.contains("old-password-continuation") && cleanPassword.contains("# keep this comment") && cleanPassword.contains("targetVersion: \"26.1\""), "password migration removes multiline scalar and preserves unrelated settings")
let withAccount = updatingYAMLString(cleanPassword, section: ["auth"], field: "localAccount", value: "newadmin")
check(withAccount.contains("localAccount: \"newadmin\"") && !withAccount.contains("oldadmin"), "credential account is persisted")
let missingSection = updatingYAMLString("update:\n  targetVersion: \"26.1\"\n", section: ["jamf", "laps"], field: "clientSecret", value: "")
check(missingSection.contains("jamf:\n  laps:\n    clientSecret: \"\""), "migration creates missing nested section")
let duplicates = updatingYAMLString("auth:\n  localPassword: first\n  localPassword: second\n", section: ["auth"], field: "localPassword", value: "")
check(!duplicates.contains("first") && !duplicates.contains("second") && duplicates.components(separatedBy: "localPassword:").count == 2, "migration eliminates duplicate plaintext credential fields")
AutoCheckCommand(args: ["--dry-run"]).run()
check(FileManager.default.contents(atPath: statePath) == before, "auto-check dry-run leaves state untouched")
check(popupResultMessage(state:"toast",exitCode:1)=="User chose Later", "toast Later reports the actual response")
check(!toastRequestedInstall(exitCode:1) && !toastRequestedInstall(exitCode:2) && !toastRequestedInstall(exitCode:5), "toast Later, dismiss, and timeout never request install")
check(popupResultMessage(state:"toast",exitCode:0)=="User chose Install" && toastRequestedInstall(exitCode:0), "toast install requires explicit zero exit code")
check(popupResultMessage(state:"toast",exitCode:100).contains("without a user response"), "UI timeout is distinguished from a user choice")

// Set-once policy: a compliant saved target cannot suppress discovery in tracking mode.
check(AutoCheckCommand(args: ["--check-only"]).checkOnly && AutoCheckCommand(args: ["--check-only"]).isForced, "check-now overrides timing only")
check(AutoCheckCommand(args: ["--notify-only"]).notifyOnly && !AutoCheckCommand(args: ["--notify-only"]).installNow, "notify-now cannot select automatic installation mode")
check(AutoCheckCommand(args: ["--install-now"]).installNow && AutoCheckCommand(args: ["--install-now"]).isForced, "install-now is an explicit forced action")
var policy = CLIConfig.parse(yaml: "auto:\n  trackLatest: true\n  minorOnly: true\n  useMist: true\n")
check(policy.auto.trackLatest && policy.auto.useMist, "tracking and Mist options parse")
check(!CLIConfig.parse(yaml:"auto:\n  enabled: true\n").auto.trackLatest, "existing deployments require opt-in to follow newer targets")
check(DiscoveryPolicy.eligible(version:"27.1",beta:false,current:"27.0",config:policy), "current-major policy accepts newer minor")
check(!DiscoveryPolicy.eligible(version:"28.0",beta:false,current:"27.0",config:policy), "current-major policy rejects major upgrade")
check(!DiscoveryPolicy.eligible(version:"27.0",beta:false,current:"27.0",config:policy), "equal version is never an update")
check(!DiscoveryPolicy.eligible(version:"26.9",beta:false,current:"27.0",config:policy), "older version never becomes a target")
check(!DiscoveryPolicy.eligible(version:"27.2",beta:true,current:"27.0",config:policy), "beta excluded")
check(!DiscoveryPolicy.eligible(version:"27.2;touch x",beta:false,current:"27.0",config:policy), "invalid version excluded")
policy.auto.skipVersions = ["27.1"]
check(!DiscoveryPolicy.eligible(version:"27.1",beta:false,current:"27.0",config:policy), "excluded version honored")
policy.auto.minorOnly = false
check(DiscoveryPolicy.eligible(version:"28.0",beta:false,current:"27.0",config:policy), "major-upgrade policy accepts eligible major")
policy.auto.minorOnly = true; policy.auto.enforceMinimumMajorVersion = 28
check(DiscoveryPolicy.eligible(version:"28.1",beta:false,current:"27.0",config:policy) && !DiscoveryPolicy.eligible(version:"29.0",beta:false,current:"27.0",config:policy), "minimum major enforcement has a bounded exception")
check(!DiscoveryPolicy.eligible(version:"27.2",beta:false,current:"27.0",config:policy), "minimum-major policy cannot select another below-minimum target")
let first = ISO8601DateFormatter().date(from:"2026-01-15T12:00:00Z")!
policy.auto.minorDeadlineDays = 7
let calculated = DiscoveryPolicy.deadline(config:policy,target:"27.1",isMajor:false,firstSeen:first)
check(calculated == "2026-01-22T12:00:00Z", "deadline starts from first detection")
policy.update.targetVersion = "27.1"; policy.update.automaticDeadlineTarget = "27.1"; policy.update.automaticDeadline = calculated
check(DiscoveryPolicy.deadline(config:policy,target:"27.1.0",isMajor:false,firstSeen:Date()) == calculated, "repeat checks and normalized versions cannot slide deadline")
check(policy.effectiveDeadline == calculated, "computed deadline used without override")
policy.update.deadline = "2026-02-01T18:00:00Z"
check(policy.effectiveDeadline == policy.update.deadline, "YAML override wins")
check(DiscoveryPolicy.deadline(config:policy,target:"28.0",isMajor:true,firstSeen:Date()) == policy.update.deadline, "override survives new targets")
policy.update.deadline = ""; policy.update.targetVersion = "28.0"
check(policy.effectiveDeadline.isEmpty, "old target's generated deadline cannot apply to a new target")
policy.update.targetVersion = "27.1"
check(policy.effectiveDeadline == calculated, "clearing override restores automatic deadline")
var legacyPending = CLIDeferralState(); legacyPending.installStarted = true; legacyPending.installCompleted = true
check(legacyPending.recoverInstallation(running:"27.0",boot:100,target:"27",active:false) != nil && !legacyPending.installStarted && legacyPending.installCompleted, "legacy contradictory completion flags recover")
var legacyBusy = CLIDeferralState(); legacyBusy.installStarted = true
check(legacyBusy.recoverInstallation(running:"27.0",boot:100,target:"27.1",active:true) == nil && legacyBusy.installStarted, "active installer protects legacy flags")
check(legacyBusy.recoverInstallation(running:"27.0",boot:100,target:"27.1",active:nil) == nil && legacyBusy.installStarted, "unknown activity fails closed")
check(legacyBusy.recoverInstallation(running:"27.0",boot:100,target:"27.1",active:false) != nil && !legacyBusy.installStarted, "orphaned legacy flags can retry")
var modernPending = CLIDeferralState(); modernPending.beginInstallation(target:"27.1",running:"27.0",boot:100)
check(modernPending.recoverInstallation(running:"27.0",boot:100,target:"28.0",active:false) == nil && modernPending.installStarted, "modern staged install is not reset before reboot")
check(modernPending.recoverInstallation(running:"27.1",boot:200,target:"28.0",active:false) != nil && modernPending.installCompleted && !modernPending.installStarted, "reboot verification keeps original installation target")
let catalog = try parseMistUpdates(Data("""
[{"Name":"macOS Stable","Version":"27.1","Compatible":true},
 {"name":"macOS Beta","version":"28.0","compatible":true},
 {"name":"macOS Other","version":"29.0","compatible":false},
 {"name":"macOS Old","version":"26.0","compatible":true},
 {"name":"Malformed","version":"27.2;whoami"}]
""".utf8), current:"27.0")
check(catalog.count == 2 && catalog.first?.version == "27.1", "Mist parser excludes incompatible, old, and malformed records")
check(catalog.last?.isBeta == true, "Mist beta marker reaches policy filter")
check((try? parseMistUpdates(Data("{}".utf8),current:"27.0")) == nil, "unknown catalog schema fails closed")
let restored = try JSONDecoder().decode(CLIDeferralState.self,from:JSONEncoder().encode(legacyBusy))
check(!restored.installStarted && restored.lastRecoveryMessage != nil, "recovered installation state round-trips")


var serialized = CLIConfig()
serialized.update.targetVersion = "27.1"
serialized.update.macOSName = "macOS Example"
serialized.update.automaticDeadline = "2026-12-05T18:00:00Z"
serialized.update.automaticDeadlineTarget = "27.1"
let sourceYAML = "# retained\ncustom:\n  deadline: \"untouched\"\nupdate:\n  deadline: \"2026-12-01T18:00:00Z\"\n  customFlag: true\n"
serialized.update.deadline = "2026-12-01T18:00:00Z"
let updated = serialized.updatingDetectionYAML(sourceYAML)
let parsedUpdated = CLIConfig.parse(yaml: updated)
check(updated.contains("# retained") && updated.contains("  customFlag: true") && updated.contains("  deadline: \"untouched\""), "discovery writes preserve comments, unknown settings, and other sections")
check(parsedUpdated.update.deadline == serialized.update.deadline && parsedUpdated.effectiveDeadline == serialized.update.deadline, "discovery serialization preserves explicit override")
check(parsedUpdated.update.automaticDeadline == serialized.update.automaticDeadline && parsedUpdated.update.targetVersion == "27.1", "generated target and deadline round-trip")


let stateFixture = root.appendingPathComponent("corrupt-state.json")
try Data("{broken".utf8).write(to: stateFixture)
check((try? loadStateForAction(from: stateFixture.path)) == nil, "corrupt state cannot appear idle to action commands")
try JSONEncoder().encode(CLIDeferralState()).write(to: stateFixture)
check((try? loadStateForAction(from: stateFixture.path)) != nil, "valid action state loads")
check((try? loadStateForAction(from: root.appendingPathComponent("absent.json").path))?.installStarted == false, "fresh installation without state starts idle")


// Approved application policy fixtures — no installed apps or vendor services are accessed.
check(ApprovedApp.catalog.count == 3 && Set(ApprovedApp.catalog.map(\.id)).count == 3, "initial app catalog is explicit and unique")
check(AppUpdatePolicy.ids(" firefox,chrome,chrome, ") == ["chrome","firefox"], "approved IDs normalize without duplicate updates")
for invalid in ["", "1..2", "1.2beta", "1.2;whoami", "１.２", "-1.2", "1.2.3.4.5.6.7"] {
    check(AppUpdatePolicy.version(invalid) == nil, "reject invalid app version " + invalid)
}
check(AppUpdatePolicy.newer("142.0.7444.10",than:"142.0.7444.9"), "Chrome four-part versions compare numerically")
check(!AppUpdatePolicy.newer("142.0.7444.9",than:"142.0.7444.10"), "app versions never downgrade")
check(AppUpdatePolicy.same("1.2","1.2.0") && !AppUpdatePolicy.same("", ""), "equivalent app versions keep first-detection identity")
let appFirst = Date(timeIntervalSince1970:1_800_000_000)
let appDeadline = AppUpdatePolicy.deadline(override:"",firstSeen:appFirst,days:7)
check(appDeadline == appFirst.addingTimeInterval(7*86400), "app grace period anchors to first detection")
check(AppUpdatePolicy.deadline(override:"2026-12-01T18:00:00Z",firstSeen:appFirst,days:7) == ISO8601DateFormatter().date(from:"2026-12-01T18:00:00Z"), "explicit app deadline wins")
check(AppUpdatePolicy.deadline(override:"tomorrow",firstSeen:appFirst,days:7) == nil, "invalid app deadline fails closed")
for enabled in [false,true] {
    for approved in ["", "chrome"] {
        for running in [false,true] {
            let decision = AppUpdatePolicy.shouldInstall(id:"chrome",approved:approved,enabled:enabled,installed:"140.0.1.1",target:"140.0.2.1",running:running)
            check(decision == (enabled && approved == "chrome" && !running), "install requires approval, enabled policy, newer version, and a closed app")
        }
    }
}
check(!AppUpdatePolicy.shouldInstall(id:"unreviewed",approved:"unreviewed",enabled:true,installed:"1.0",target:"2.0",running:false), "an unreviewed label can never execute")
check(!AppUpdatePolicy.shouldInstall(id:"chrome",approved:"chrome",enabled:true,installed:"142.0.1.1",target:"140.0.2.1",running:false), "newer installed app is never replaced by older stable")
for app in ApprovedApp.catalog {
    let arguments = AppUpdatePolicy.installArguments(app)
    check(arguments.first == app.label && arguments.contains("DEBUG=0"), "approved provider label is fixed")
    check(arguments.contains("BLOCKING_PROCESS_ACTION=silent_fail") && arguments.contains("REOPEN=no"), "provider never forces app closure or reopening")
    check(arguments.contains("IGNORE_APP_STORE_APPS=no"), "provider retains App Store exclusion")
}
check((try? AppUpdatePolicy.latest(appID:"chrome",data:Data("{\"releases\":[{\"version\":\"142.0.7444.10\"}]}".utf8))) == "142.0.7444.10", "Chrome serving-release feed parses")
check((try? AppUpdatePolicy.latest(appID:"firefox",data:Data("{\"LATEST_FIREFOX_VERSION\":\"145.0.1\",\"FIREFOX_ESR\":\"128.0esr\"}".utf8))) == "145.0.1", "Firefox uses release feed, not ESR")
check((try? AppUpdatePolicy.latest(appID:"vscode",data:Data("[\"1.105.2\",\"1.105.1\"]".utf8))) == "1.105.2", "VS Code stable feed parses")
check((try? AppUpdatePolicy.latest(appID:"chrome",data:Data("{\"releases\":[{\"version\":\"1.2;id\"}]}".utf8))) == nil, "malformed vendor version cannot become an app target")
check((try? AppUpdatePolicy.latest(appID:"other",data:Data("{}".utf8))) == nil, "unknown app feed fails closed")
let notices = try JSONEncoder().encode(AppUpdateNotice.examples).base64EncodedString()
check(AppUpdateNotice.decodePayload(notices)?.count == 3 && AppUpdateNotice.decodePayload("invalid") == nil, "grouped toast payload validates")
check(AppUpdateNotice.decodePayload(String(repeating:"A",count:9000)) == nil, "oversized toast payload rejected")
let unknownNotice = AppUpdateNotice(id:"unknown",name:"Unknown",installed:"1.0",target:"2.0",deadline:"")
let unknownPayload = try JSONEncoder().encode([unknownNotice]).base64EncodedString()
check(AppUpdateNotice.decodePayload(unknownPayload) == nil, "toast cannot carry unapproved catalog identities")
check(popupResultMessage(state:"appUpdates",exitCode:0) == "User chose Update Closed Apps", "app preview reports the actual update button")
check(popupResultMessage(state:"appUpdates",exitCode:1) == "User chose Later", "app Later stays distinct from an update request")
check(!AppUpdatePolicy.toastDue(appFirst.addingTimeInterval(3600),now:appFirst), "app toast cannot immediately repeat")
check(AppUpdatePolicy.toastDue(appFirst.addingTimeInterval(30),now:appFirst), "hourly polling tolerates small catalog-duration differences")
let appPolicy = CLIConfig.parse(yaml:"apps:\n  enabled: true\n  approved: \"chrome,firefox\"\n  graceDays: 9\n  deadline: \"2026-12-01T18:00:00Z\"\n  chromeDeadline: \"2026-11-20T18:00:00Z\"\n")
check(appPolicy.apps.enabled && appPolicy.apps.approved == "chrome,firefox" && appPolicy.apps.graceDays == 9, "app policy reads YAML")
check(appPolicy.apps.deadlineOverride(for:"chrome") == "2026-11-20T18:00:00Z" && appPolicy.apps.deadlineOverride(for:"firefox") == "2026-12-01T18:00:00Z", "per-app override precedes all-app override")
check(!CLIConfig().apps.enabled && !CLIConfig().apps.autoUpdateClosed && CLIConfig().apps.approved.isEmpty, "existing deployments opt in to app updates")
check(!trustedAppProvider("/bin/zsh") && !trustedAppProvider("relative/Installomator.sh"), "arbitrary provider executables are rejected")
var appState = ManagedAppsState()
appState.apps["chrome"] = ManagedAppRecord(installed:"140.0.1.1",target:"140.0.2.1",firstSeen:appFirst,deadline:appDeadline)
let appStateRoundTrip = try JSONDecoder().decode(ManagedAppsState.self,from:JSONEncoder().encode(appState))
check(appStateRoundTrip.apps["chrome"]?.firstSeen == appFirst, "app discovery survives state persistence independently from macOS state")

check(AppUpdatePolicy.firefoxReleaseChannel("pref(\"app.update.channel\", \"release\");"), "Firefox release channel must be explicitly set")
check(!AppUpdatePolicy.firefoxReleaseChannel("// pref(\"app.update.channel\", \"release\");\npref(\"app.update.channel\", \"esr\");"), "release text in comments cannot convert ESR policy")
check(!AppUpdatePolicy.firefoxReleaseChannel("pref(\"app.update.channel\", \"release\");\npref(\"app.update.channel\", \"esr\");"), "ambiguous Firefox channels fail closed")

// Entra reminder checks use fixtures only: no profiles, Jamf, Company Portal, or user preferences are queried.
check(!CLIConfig().entra.enabled, "Entra module is opt-in for existing deployments")
let entraConfig = CLIConfig.parse(yaml:"entra:\n  enabled: true\n  policyID: 876\n  startHour: 9\n  endHour: 17\n  reconOnRegistration: false\n")
check(entraConfig.entra.enabled && entraConfig.entra.policyID == "876" && entraConfig.entra.startHour == 9 && !entraConfig.entra.reconOnRegistration, "Entra YAML policy parses")
check(EntraNudgeCommand.valid(entraConfig.entra), "valid Entra policy accepted")
var badEntra = entraConfig.entra; badEntra.policyID = "876;whoami"
check(!EntraNudgeCommand.valid(badEntra), "policy ID cannot inject a command or deep link")
for id in ["", "0", "-1", "abc", "876&action=execute", "１２３", "99999999999"] {
    check(EntraPolicy.selfServiceURL(policyID:id) == nil, "reject malformed Self Service policy " + id)
}
check(EntraPolicy.selfServiceURL(policyID:"876")?.absoluteString == "jamfselfservice://content?entity=policy&id=876&action=view", "registration opens the configured policy view only")
check(EntraPolicy.jamfAAD(data:nil,exists:false).status == .needsRegistration, "missing user registration preference requires registration after prerequisite checks")
let truePlist = try PropertyListSerialization.data(fromPropertyList:["have_an_Azure_id":true],format:.binary,options:0)
let falsePlist = try PropertyListSerialization.data(fromPropertyList:["have_an_Azure_id":false],format:.xml,options:0)
check(EntraPolicy.jamfAAD(data:truePlist,exists:true).status == .localRegistered, "current local flag yields local registration, not compliance")
check(EntraPolicy.jamfAAD(data:falsePlist,exists:true).status == .needsRegistration, "explicit current false flag requests registration")
check(EntraPolicy.jamfAAD(data:nil,exists:true).status == .verificationUnavailable, "unreadable preference is not treated as unregistered")
check(EntraPolicy.jamfAAD(data:Data("broken".utf8),exists:true).status == .verificationUnavailable, "corrupt preference cannot suppress or trigger reminders")
let wrongKey = try PropertyListSerialization.data(fromPropertyList:["someOtherProvider":true],format:.xml,options:0)
check(EntraPolicy.jamfAAD(data:wrongKey,exists:true).status == .verificationUnavailable, "unrelated SSO signals cannot confirm Jamf registration")
let wrongType = try PropertyListSerialization.data(fromPropertyList:["have_an_Azure_id":"true"],format:.xml,options:0)
check(EntraPolicy.jamfAAD(data:wrongType,exists:true).status == .verificationUnavailable, "ambiguous registration data fails closed")
check(EntraPolicy.bool(NSNumber(value:2)) == nil && EntraPolicy.bool(NSNumber(value:1.5)) == nil, "nonboolean numeric states are not registration")
for (later,stage,cap,gap) in [(0,1,2,14400),(3,1,2,14400),(4,2,3,10800),(7,2,3,10800),(8,3,4,7200),(11,3,4,7200),(12,4,6,5400),(100,4,6,5400)] {
    let policy = EntraPolicy.stage(laterCount:later)
    check(policy.number == stage && policy.cap == cap && policy.gap == Double(gap), "stage thresholds match the supplied escalation policy")
    check(EntraPolicy.stage(laterCount:later,test:true).gap == Double(gap)/60, "test timing scales gaps without changing production")
}
let entraNow = ISO8601DateFormatter().date(from:"2026-11-06T12:00:00Z")!
var entraUser = EntraUserState(); entraUser.userName = "fixture-user"
check(EntraPolicy.dueReason(entraUser,now:entraNow) == nil, "first eligible reminder is due")
entraUser.lastPromptAt = entraNow
check(EntraPolicy.dueReason(entraUser,now:entraNow.addingTimeInterval(3600)) != nil, "hourly checks cannot break the four-hour initial gap")
check(EntraPolicy.dueReason(entraUser,now:entraNow.addingTimeInterval(14400)) == nil, "minimum gap boundary permits reminder")
entraUser.promptsToday = 2
check(EntraPolicy.dueReason(entraUser,now:entraNow.addingTimeInterval(20000)) == "Daily prompt limit reached", "daily limit still applies after gap")
EntraPolicy.recordResponse(100,state:&entraUser)
check(entraUser.timedOutCount == 1 && entraUser.laterCount == 0, "timeout cannot be recorded as Later")
EntraPolicy.recordResponse(2,state:&entraUser)
check(entraUser.closedCount == 1 && entraUser.laterCount == 0, "close cannot be recorded as Later")
EntraPolicy.recordResponse(0,state:&entraUser)
check(entraUser.registerClicks == 1 && entraUser.openedCount == 0 && entraUser.lastRegistered == nil, "Register Now is an intent, not completed registration or a successful app launch")
EntraPolicy.recordResponse(1,state:&entraUser)
check(entraUser.laterCount == 1, "explicit Later increments escalation")
EntraPolicy.recordResponse(-5,state:&entraUser)
check(entraUser.laterCount == 1 && entraUser.registerClicks == 1, "crash signal cannot become a user action")
var utc = Calendar(identifier:.gregorian); utc.timeZone = TimeZone(secondsFromGMT:0)!
check(EntraPolicy.withinHours(now:entraNow,start:8,end:18,weekdaysOnly:true,calendar:utc), "Friday business hours are eligible")
let saturday = ISO8601DateFormatter().date(from:"2026-11-07T12:00:00Z")!
check(!EntraPolicy.withinHours(now:saturday,start:8,end:18,weekdaysOnly:true,calendar:utc), "weekend reminders are suppressed")
let endHour = ISO8601DateFormatter().date(from:"2026-11-06T18:00:00Z")!
check(!EntraPolicy.withinHours(now:endHour,start:8,end:18,weekdaysOnly:true,calendar:utc), "business end hour is exclusive")
check(EntraPolicy.dayKey(now:entraNow,calendar:utc) == "20261106" && EntraPolicy.dayKey(now:entraNow,test:true,calendar:utc) == "2026110612", "daily and test-hour caps use separate period keys")
let noticeData = try JSONEncoder().encode(EntraNotice.preview(stage:4)).base64EncodedString()
check(EntraNotice.decode(noticeData)?.stage == 4 && EntraNotice.decode(noticeData)?.laterCount == 12, "preview stages carry correct thresholds")
check(EntraNotice.decode("invalid") == nil && EntraNotice.decode(String(repeating:"A",count:9000)) == nil, "invalid or oversized live payload rejected")
let invalidNotice = EntraNotice(stage:0,laterCount:-1,message:"invalid")
let invalidNoticeData = try JSONEncoder().encode(invalidNotice).base64EncodedString()
check(EntraNotice.decode(invalidNoticeData) == nil, "invalid stages and counts cannot reach the live view")
var users = EntraNudgeState(); users.users["501"] = entraUser; users.users["502"] = .init()
let restoredUsers = try JSONDecoder().decode(EntraNudgeState.self,from:JSONEncoder().encode(users))
check(restoredUsers.users["501"]?.laterCount == 1 && restoredUsers.users["502"]?.laterCount == 0, "per-user counters remain independent")
check((try? JSONDecoder().decode(EntraNudgeState.self,from:Data("broken".utf8))) == nil, "corrupt Entra state is not an empty ready-to-prompt state")
check(popupResultMessage(state:"entraRegistration",exitCode:0) == "User chose Register Now", "manual registration preview reports Register Now, never Install")
check(popupResultMessage(state:"entraRegistration",exitCode:100).contains("without a user response"), "registration timeout stays distinct from Later")
check(!trustedEntraBinary("/bin/sh") && !trustedEntraBinary("relative/jamf"), "root recon rejects arbitrary executables")
let userLink = root.appendingPathComponent("jamf")
try FileManager.default.createSymbolicLink(atPath:userLink.path,withDestinationPath:"/bin/ls")
check(!trustedEntraBinary(userLink.path), "a user-writable symlink chain cannot authorize root execution")

for code: Int32 in [0,1,2,3,4,5,6,99] {
    check(popupWindowResult(status:code,reason:.exit,visible:false) == 103, "a GUI startup failure cannot masquerade as a button response")
    check(popupWindowResult(status:code,reason:.exit,visible:true) == code, "a shown window preserves real button responses")
}
check(popupWindowResult(status:5,reason:.uncaughtSignal,visible:true) == -5, "a crash after display remains a crash")
check(popupResultMessage(state:"entraRegistration",exitCode:103).contains("No user choice"), "failed startup explains that no action was chosen")
var startupFailureUser = EntraUserState()
EntraPolicy.recordResponse(103,state:&startupFailureUser)
check(startupFailureUser.laterCount == 0 && startupFailureUser.registerClicks == 0, "failed preview cannot escalate or register a user")

let oldConfig = "# preserve this configuration\nupdate:\n  targetVersion: \"27.2\"\n  deadline: \"2026-11-11T03:01:30Z\"\ncustom:\n  value: keep-me\n"
let withEntra = try ConfigCommand.upsertingConfig(oldConfig,key:"entra.enabled",value:"true")
check(CLIConfig.parse(yaml:withEntra).entra.enabled, "old YAML without Entra section accepts enabled setting")
check(withEntra.contains("  enabled: true") && !withEntra.contains("enabled: \"true\""), "booleans retain native YAML type")
check(withEntra.hasPrefix(oldConfig) && withEntra.contains("# preserve this configuration") && withEntra.contains("  value: keep-me"), "missing-section upsert preserves original policy and unknown settings")
let withPolicy = try ConfigCommand.upsertingConfig(withEntra,key:"entra.policyID",value:"987")
check(CLIConfig.parse(yaml:withPolicy).entra.policyID == "987" && CLIConfig.parse(yaml:withPolicy).entra.enabled, "missing field added within an existing section")
let disabledEntra = try ConfigCommand.upsertingConfig(withPolicy,key:"entra.enabled",value:"false")
check(!CLIConfig.parse(yaml:disabledEntra).entra.enabled && disabledEntra.components(separatedBy:"entra:").count == 2, "existing field changes without creating duplicate sections")
let commentedSection = "entra: # organization registration policy\n  policyID: \"876\"\nupdate:\n  targetVersion: \"27.2\"\n"
let commentedEdit = try ConfigCommand.upsertingConfig(commentedSection,key:"entra.enabled",value:"true")
check(commentedEdit.components(separatedBy:"entra:").count == 2 && commentedEdit.contains("# organization registration policy") && commentedEdit.contains("  enabled: true") && CLIConfig.parse(yaml:commentedEdit).entra.enabled, "commented header is reused rather than duplicated")
let typedHour = try ConfigCommand.upsertingConfig(withEntra,key:"entra.startHour",value:"9")
check(CLIConfig.parse(yaml:typedHour).entra.startHour == 9 && typedHour.contains("startHour: 9"), "integer settings keep YAML type")
let newModule = try ConfigCommand.upsertingConfig(oldConfig,key:"apps.enabled",value:"false")
check(newModule.contains("apps:\n  enabled: false") && !CLIConfig.parse(yaml:newModule).apps.enabled, "other supported missing module sections can be created")
check((try? ConfigCommand.upsertingConfig(oldConfig,key:"entra.enabeld",value:"true")) == nil, "unknown or mistyped settings cannot create unused policy keys")
check((try? ConfigCommand.upsertingConfig(oldConfig,key:"entra.enabled",value:"tru")) == nil, "mistyped boolean cannot silently disable or enable policy")
check((try? ConfigCommand.upsertingConfig(oldConfig,key:"entra.startHour",value:"tomorrow")) == nil, "integer setting rejects text")
check((try? ConfigCommand.upsertingConfig(oldConfig,key:"entra.endHour",value:"7")) == nil, "invalid Entra working hours are not committed")
check((try? ConfigCommand.upsertingConfig("entra:\n  enabled: false\nentra:\n  enabled: true\n",key:"entra.enabled",value:"true")) == nil, "duplicate target sections fail closed")
check((try? ConfigCommand.upsertingConfig("entra: {}\n",key:"entra.enabled",value:"true")) == nil, "unsupported inline section cannot become duplicate block YAML")
let duplicatesCleaned = try ConfigCommand.upsertingConfig("entra:\n  enabled: false\n  enabled: true\n",key:"entra.enabled",value:"false")
check(duplicatesCleaned.components(separatedBy:"  enabled:").count == 2, "duplicate target fields are consolidated")
let safeMessage = try ConfigCommand.upsertingConfig(oldConfig,key:"entra.message",value:"Reminder\napps:\n  enabled: true")
check(!CLIConfig.parse(yaml:safeMessage).apps.enabled && safeMessage.components(separatedBy:"\napps:").count == 1, "string content cannot inject a new YAML section")
let appPath = try ConfigCommand.upsertingConfig(oldConfig,key:"entra.selfServicePath",value:"/Applications/Self Service.app")
check(appPath.contains("/Applications/Self Service.app") && !appPath.contains("\\/"), "paths stay compatible with the PUSH YAML reader")

check(RuntimeHealthScope.clean("Password=private-value").contains("omitted"), "health observation redacts credential assignments")
check(RuntimeHealthScope.clean("Bearer private-value").contains("omitted"), "health observation redacts bearer tokens")
check(RuntimeHealthScope.clean("Failed https://example.invalid/path?token=private").contains("omitted"), "health observation omits URL query credentials")
check(RuntimeHealthScope.clean("Meeting detected\nRetry later") == "Meeting detectedRetry later", "health observations remove control characters")
check(RuntimeHealthScope.clean(String(repeating:"a",count:1000)).count == 600, "health observations are bounded")
check(RuntimeHealthScope.clean("Next toast is not due") == "Next toast is not due", "ordinary skip reasons remain useful")
let healthWire = RuntimeHealthRecord(module:"macos",source:"scheduled",startedAt:Date(),updatedAt:Date(),phase:"checking",reason:"Fixture")
check((try? JSONDecoder().decode(RuntimeHealthRecord.self,from:JSONEncoder().encode(healthWire)))?.source == "scheduled", "health records round-trip without invoking a monitor")

// Around-the-clock reminder and download-only policy fixtures. No live actions.
var alwaysConfig=CLIConfig.parse(yaml:"schedule:\n  alertStartHour: 8\n  alertEndHour: 18\n  skipWeekends: true\n")
check(!alwaysConfig.schedule.respectAlertWindow,"preserved hours do not restrict reminders unless explicitly enabled")
let reminderSaturday=ISO8601DateFormatter().date(from:"2026-11-07T23:00:00Z")!
var utcHours=Calendar(identifier:.gregorian);utcHours.timeZone=TimeZone(secondsFromGMT:0)!
check(ReminderDeliveryPolicy.withinHours(restricted:false,start:8,end:18,weekdays:true,now:reminderSaturday,calendar:utcHours),"24/7 reminders allow weekends and evenings")
check(!ReminderDeliveryPolicy.withinHours(restricted:true,start:8,end:18,weekdays:true,now:reminderSaturday,calendar:utcHours),"optional saved working-hours policy still blocks weekend reminders")
let weekday=ISO8601DateFormatter().date(from:"2026-11-09T09:00:00Z")!
check(ReminderDeliveryPolicy.withinHours(restricted:true,start:8,end:18,weekdays:true,now:weekday,calendar:utcHours),"enabled working-hours policy permits eligible weekday session")
check(!ReminderDeliveryPolicy.withinHours(restricted:true,start:18,end:8,weekdays:false,now:weekday,calendar:utcHours),"invalid restricted hours fail closed")
let explicitHours=CLIConfig.parse(yaml:"schedule:\n  respectAlertWindow: true\n")
check(explicitHours.schedule.respectAlertWindow,"YAML can explicitly re-enable saved working hours")
var queued=CLIDeferralState();queued.nextToastDate=reminderSaturday;queued.queueAwareness(now:reminderSaturday)
let originalQueue=queued.notificationPendingSince
queued.queueAwareness(now:reminderSaturday.addingTimeInterval(300))
check(queued.notificationPendingSince == originalQueue,"repeated logged-out checks retain the original awareness queue")
for failure:Int32 in [99,101,103,-9,3,4] {
 check(!queued.recordToastResult(failure,interval:3600,now:weekday) && queued.nextToastDate == reminderSaturday && queued.notificationPendingSince == originalQueue,"failed or mismatched toast result leaves awareness due: \(failure)")
}
for response:Int32 in [0,1,2,5,100] {
 var delivered=queued
 check(delivered.recordToastResult(response,interval:3600,now:weekday) && delivered.notificationPendingSince == nil && delivered.nextToastDate == weekday.addingTimeInterval(3600) && delivered.lastToastShownAt == weekday,"confirmed visible toast advances only its own interval: \(response)")
}
let stateRoundTrip=try JSONDecoder().decode(CLIDeferralState.self,from:JSONEncoder().encode(queued))
check(stateRoundTrip.notificationPendingSince == reminderSaturday,"queued awareness survives state persistence")
var overdue=CLIConfig();overdue.debug.dryRun=false;overdue.update.targetVersion="27.2";overdue.update.deadline="2020-01-01T00:00:00Z"
check(BackgroundPreparation.eligible(config:overdue,loggedIn:false,installPending:false,activity:false),"overdue logged-out Mac can prepare downloads without user authorization prompts")
check(!BackgroundPreparation.eligible(config:overdue,loggedIn:true,installPending:false,activity:false),"headless preparation does not replace a logged-in workflow")
check(!BackgroundPreparation.eligible(config:overdue,loggedIn:false,installPending:true,activity:false),"pending reboot verification blocks background preparation")
check(!BackgroundPreparation.eligible(config:overdue,loggedIn:false,installPending:false,activity:nil),"unknown installer activity blocks background preparation")
check(!BackgroundPreparation.eligible(config:overdue,loggedIn:false,installPending:false,activity:true),"active installer blocks competing downloads")
var disabledPreparation=overdue;disabledPreparation.update.prepareAtDeadlineWhenLoggedOut=false
check(!BackgroundPreparation.eligible(config:disabledPreparation,loggedIn:false,installPending:false,activity:false),"administrator can disable logged-out preparation")
disabledPreparation=overdue;disabledPreparation.debug.dryRun=true
check(!BackgroundPreparation.eligible(config:disabledPreparation,loggedIn:false,installPending:false,activity:false),"dry run never enables headless downloads")
disabledPreparation=overdue;disabledPreparation.update.deadline="2099-01-01T00:00:00Z"
check(!BackgroundPreparation.eligible(config:disabledPreparation,loggedIn:false,installPending:false,activity:false),"logged-out preparation waits for the actual deadline")
let nativePlan=PreparationPlan.native(label:"macOS Update-27.2")!
let fullPlan=PreparationPlan.fullInstaller(target:"27.2")!
check(nativePlan.arguments == ["--download","macOS Update-27.2","--agree-to-license"],"native preparation plan downloads only")
check(fullPlan.arguments == ["--fetch-full-installer","--full-installer-version","27.2"],"full preparation plan fetches installer without executing it")
check([nativePlan,fullPlan].allSatisfy{$0.executable == "/usr/sbin/softwareupdate" && !$0.arguments.contains("--install") && !$0.arguments.contains("--restart") && !$0.arguments.contains("--stdinpass")},"preparation plans contain no OS install, restart, or password arguments")
check(PreparationPlan.fullInstaller(target:"27.2;reboot") == nil && PreparationPlan.native(label:"--install") == nil,"preparation plans reject invalid targets and option-like labels")
let migratedWindow=try ConfigCommand.upsertingConfig("schedule:\n  alertStartHour: 8\n  alertEndHour: 18\n  skipWeekends: true\n",key:"schedule.respectAlertWindow",value:"false")
let migratedPolicy=CLIConfig.parse(yaml:migratedWindow)
check(!migratedPolicy.schedule.respectAlertWindow && migratedPolicy.schedule.alertStartHour == 8 && migratedPolicy.schedule.skipWeekends,"disabling the alert restriction preserves the saved hours and weekday settings")
let oldWire=try JSONEncoder().encode(CLIDeferralState())
var oldDictionary=try JSONSerialization.jsonObject(with:oldWire) as! [String:Any]
for key in ["lastToastShownAt","notificationPendingSince","deadlineNoticeShownAt"] {oldDictionary.removeValue(forKey:key)}
let oldDecoded=try JSONDecoder().decode(CLIDeferralState.self,from:JSONSerialization.data(withJSONObject:oldDictionary))
check(oldDecoded.lastToastShownAt == nil && oldDecoded.notificationPendingSince == nil,"older state files decode without the new awareness fields")

var targetScopedNotice=CLIDeferralState()
check(targetScopedNotice.recordToastResult(2,interval:3600,now:weekday,target:"27.2") && targetScopedNotice.lastToastTarget == "27.2", "awareness evidence is tied to the target that was actually displayed")
check(!sameOSVersion(targetScopedNotice.lastToastTarget ?? "","27.3"), "an old target's toast cannot suppress awareness for a newly configured target")

check(ReminderDeliveryPolicy.ordinaryAwarenessFirst(pending:true,pastDeadline:false,automaticInstall:true), "before deadline the first awareness toast is delivered ahead of the full nudge")
check(ReminderDeliveryPolicy.ordinaryAwarenessFirst(pending:true,pastDeadline:true,automaticInstall:false), "manual deadline policy also receives the queued awareness toast")
check(!ReminderDeliveryPolicy.ordinaryAwarenessFirst(pending:true,pastDeadline:true,automaticInstall:true), "forced deadline policy uses bounded informational awareness instead of asking for consent")
check(!ReminderDeliveryPolicy.ordinaryAwarenessFirst(pending:false,pastDeadline:false,automaticInstall:false), "ordinary schedule resumes after queued awareness is confirmed")

// Wallpaper decisions and delivery history are pure fixtures: no desktop is changed.
check(WallpaperPolicy.action(enabled:false,running:"27.0",target:"27.2") == nil,"wallpaper is opt-in")
check(WallpaperPolicy.action(enabled:true,running:"27.0",target:"27.2") == "enforce","non-compliant macOS selects continuous enforcement")
check(WallpaperPolicy.action(enabled:true,running:"27.0",target:"27.2") == WallpaperPolicy.action(enabled:true,running:"27.0",target:"27.2"),"wallpaper decision has no transition-only suppression")
check(WallpaperPolicy.action(enabled:true,running:"27.2",target:"27.2") == "restore","meeting the configured target ends non-compliant wallpaper enforcement")
check(WallpaperPolicy.action(enabled:true,running:"27.3",target:"27.2") == "restore","newer running macOS remains compliant")
check(WallpaperPolicy.action(enabled:true,running:"27.0",target:"") == nil && WallpaperPolicy.action(enabled:true,running:"unknown",target:"27.2") == nil,"unknown compliance never selects a managed background")
let capturedWallpaper=WallpaperDisplayRecord(priorURL:"/Users/example/Pictures/original.jpg",managedURL:WallpaperPolicy.defaultImage,scaling:0,clipping:false)
check(WallpaperPolicy.shouldRestore(current:WallpaperPolicy.defaultImage,record:capturedWallpaper),"personal baseline is restored only while managed image is still active")
check(!WallpaperPolicy.shouldRestore(current:"/Users/example/Pictures/new.jpg",record:capturedWallpaper),"compliant user changes are preserved rather than overwritten")
let missingBaseline=WallpaperDisplayRecord(priorURL:nil,managedURL:WallpaperPolicy.defaultImage,scaling:nil,clipping:nil)
check(!WallpaperPolicy.shouldRestore(current:WallpaperPolicy.defaultImage,record:missingBaseline),"missing personal baseline is not invented")
let wallConfig=CLIConfig.parse(yaml:"compliance:\n  wallpaperEnabled: true\n  nonCompliantWallpaper: \"/Library/Management/PUSH/assets/wallpapers/custom.png\"\n")
check(wallConfig.compliance.wallpaperEnabled && wallConfig.compliance.nonCompliantWallpaper.hasSuffix("custom.png"),"legacy compliance field names load into native wallpaper policy")
check(CLIConfig().compliance.compliantWallpaper.isEmpty && !CLIConfig().compliance.wallpaperEnabled,"fresh engine keeps personal restoration and opt-in enforcement")
let restoredWallpaper=try JSONDecoder().decode(WallpaperUserDocument.self,from:JSONEncoder().encode(WallpaperUserDocument(displays:["fixture":capturedWallpaper])))
check(restoredWallpaper.displays["fixture"]?.priorURL == capturedWallpaper.priorURL,"per-display baseline persists without macOS installation state")
check(NotificationHistoryPolicy.state(in:"'/path/push-ui' --state \"softNudge\" --manual-test") == "softNudge","history recognizes quoted UI states")
check(NotificationHistoryPolicy.result(0,visible:false).0 == "failed","process success without a visible window is never called delivered")
check(NotificationHistoryPolicy.result(101,visible:false).0 == "delayed","no desktop session is recorded as delayed")
check(NotificationHistoryPolicy.result(103,visible:false).0 == "failed","startup visibility failure is separate from dismissal")
check(NotificationHistoryPolicy.result(1,visible:true).1 == "Later selected","explicit Later is preserved in delivery history")
check(NotificationHistoryPolicy.result(2,visible:true).1 == "Closed or dismissed","closing is separate from Install")
check(NotificationHistoryPolicy.result(3,visible:true).1.contains("schedule confirmed"),"history distinguishes schedule confirmation")
check(NotificationHistoryPolicy.result(5,visible:true).0 == "timeout" && NotificationHistoryPolicy.result(100,visible:true).0 == "timeout","toast and controller timeouts remain distinct from user choices")
check(NotificationHistoryPolicy.result(-9,visible:true).0 == "failed","process signals do not become a user response")
check(NotificationHistoryPolicy.result(0,visible:true,state:"entraRegistration").1 == "Register Now selected","registration primary choice is not mislabeled Install")
let fixtureEvent=NotificationHistoryEvent(attempt:"test",date:Date(),state:"toast",mode:"preview",outcome:"displayed",reason:"Fixture",code:nil,userUID:501,target:"27.2",retryAt:nil)
check(NotificationHistoryPolicy.retaining(Array(repeating:fixtureEvent,count:650)).count==600,"local history is bounded")
let historyRoundTrip=try JSONDecoder().decode(NotificationHistoryDocument.self,from:JSONEncoder().encode(NotificationHistoryDocument(events:[fixtureEvent])))
check(historyRoundTrip.events.first?.mode == "preview","manual previews stay distinguishable from live delivery")
let digestFixture=String(repeating:"a",count:64)
check(WallpaperPolicy.assetName(digest:digestFixture,role:"noncompliant") == "noncompliant-"+digestFixture+".png","managed asset names are content-addressed")
check(WallpaperPolicy.assetName(digest:"../private",role:"noncompliant") == nil && WallpaperPolicy.assetName(digest:digestFixture,role:"../") == nil,"wallpaper names reject traversal and unsupported roles")

check(NotificationHistoryPolicy.result(0,visible:true,state:"preflightPower").0 == "completed", "power detection is not invented as user installation consent")
check(NotificationHistoryPolicy.result(0,visible:true,state:"rebootForce").0 == "completed", "restart countdown completion is not invented as a button click")

// Deadline recovery fixtures. No installer, UI, requests to the real channel, or reboot.
let retryNow=Date()
var recoveryFixture=InstallRecoveryRecord(target:"27.2",reason:"Network unavailable",kind:.network,failedAt:retryNow)
check(RecoveryFailureKind.classify("Valid authorization is required before installing macOS") == .authorization,"authorization failures do not enter a pretend download-retry loop")
check(!RecoveryFailureKind.authorization.allowsAutomaticRetry && !RecoveryFailureKind.verification.allowsAutomaticRetry && !RecoveryFailureKind.state.allowsAutomaticRetry,"IT-only blockers cannot get an automatic bypass countdown")
check(RecoveryFailureKind.power.allowsAutomaticRetry && RecoveryFailureKind.download.allowsAutomaticRetry,"temporary power and download problems can be rechecked automatically")
check(RetryPolicy.automaticAllowed(recoveryFixture,enabled:true,pastDeadline:true,dryRun:false,automaticInstall:true,limit:3,now:retryNow),"temporary failure can retry only under enabled live deadline policy")
for condition in 0..<4 {
 check(!RetryPolicy.automaticAllowed(recoveryFixture,enabled:condition != 0,pastDeadline:condition != 1,dryRun:condition == 2,automaticInstall:condition != 3,limit:3,now:retryNow),"recovery cannot bypass disabled policy, future deadline, dry-run or manual installation mode: \(condition)")
}
check(RetryPolicy.nextTime(recoveryFixture,countdownMinutes:10,backoffMinutes:30,now:retryNow)==retryNow.addingTimeInterval(600),"first recovery countdown defaults to ten minutes")
recoveryFixture.automaticAttempts=[retryNow.addingTimeInterval(-60)]
check(RetryPolicy.nextTime(recoveryFixture,countdownMinutes:10,backoffMinutes:30,now:retryNow)==retryNow.addingTimeInterval(1740),"subsequent automatic attempts retain minimum spacing")
recoveryFixture.automaticAttempts=[retryNow.addingTimeInterval(-100),retryNow.addingTimeInterval(-200),retryNow.addingTimeInterval(-300)]
check(!RetryPolicy.automaticAllowed(recoveryFixture,enabled:true,pastDeadline:true,dryRun:false,automaticInstall:true,limit:3,now:retryNow),"rolling attempt budget stops repetitive automatic retries")
recoveryFixture.automaticAttempts=[retryNow.addingTimeInterval(-90000)]
check(RetryPolicy.attempts(recoveryFixture,now:retryNow).isEmpty,"old retry attempts age out of the rolling budget")
recoveryFixture.retryAt=retryNow.addingTimeInterval(10);recoveryFixture.noticeShownAt=retryNow
check(!RetryPolicy.canRetryNow(recoveryFixture,automatic:true,now:retryNow),"a UI signal cannot trigger an automatic retry before the saved deadline")
check(RetryPolicy.canRetryNow(recoveryFixture,automatic:true,now:retryNow.addingTimeInterval(10)),"automatic retry becomes eligible at the saved absolute time")
recoveryFixture.noticeShownAt=nil
check(!RetryPolicy.canRetryNow(recoveryFixture,automatic:true,now:retryNow.addingTimeInterval(20)),"a clock without a displayed recovery notice cannot silently become user awareness")
check(RetryPolicy.canRetryNow(recoveryFixture,automatic:false,now:retryNow),"explicit Update now does not wait for the automatic clock")
let recoveryNotice=RecoveryNotice(target:"27.2",reason:"Fixture",retryAt:retryNow.addingTimeInterval(0.5),automatic:true,explanation:"Fixture only")
check(recoveryNotice.remaining(at:retryNow)==1 && !recoveryNotice.countdownDue(at:retryNow),"sub-second countdown rounding cannot make the UI fire early")
check(recoveryNotice.countdownDue(at:retryNow.addingTimeInterval(0.5)),"UI countdown uses the real absolute retry time")
let noticePayload=try JSONEncoder().encode(recoveryNotice).base64EncodedString()
check(RecoveryNotice.decode(noticePayload)?.target=="27.2","recovery notice payload round-trips without command content")
let noTimeNotice=RecoveryNotice(target:"27.2",reason:"Fixture",retryAt:nil,automatic:true,explanation:"Fixture")
let missingTimePayload=try JSONEncoder().encode(noTimeNotice).base64EncodedString()
check(RecoveryNotice.decode(missingTimePayload) == nil,"automatic recovery notice requires an actual retry time")
var requestFixture=UserUpdateRequest(userUID:Int(getuid()),target:"27.2",action:.install,issuedAt:retryNow)
check(UserUpdateRequest.valid(requestFixture,owner:Int(getuid()),target:"27.2.0",now:retryNow),"user update requests are version-bound with numeric equivalence")
check(!UserUpdateRequest.valid(requestFixture,owner:Int(getuid())+1,target:"27.2",now:retryNow),"request body cannot impersonate another console owner")
check(!UserUpdateRequest.valid(requestFixture,owner:Int(getuid()),target:"27.3",now:retryNow),"a stale target request cannot install a newly discovered version")
check(!UserUpdateRequest.valid(requestFixture,owner:Int(getuid()),target:"27.2",now:retryNow.addingTimeInterval(901)),"old user requests expire")
requestFixture.issuedAt=retryNow.addingTimeInterval(61)
check(!UserUpdateRequest.valid(requestFixture,owner:Int(getuid()),target:"27.2",now:retryNow),"future-dated user requests do not extend validity")
let privateRequestFolder=root.appendingPathComponent("request-fixture")
try FileManager.default.createDirectory(at:privateRequestFolder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
requestFixture.issuedAt=retryNow
let privateRequestFile=privateRequestFolder.appendingPathComponent("request.json")
try JSONEncoder().encode(requestFixture).write(to:privateRequestFile)
try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:privateRequestFile.path)
let consumedRequest=try UserRequestChannel.consume(uid:Int(getuid()),folder:privateRequestFolder)
check(consumedRequest?.id==requestFixture.id && !FileManager.default.fileExists(atPath:privateRequestFile.path),"descriptor-based request channel consumes only its fixed, owned file")
try FileManager.default.createSymbolicLink(at:privateRequestFile,withDestinationURL:root.appendingPathComponent("state.json"))
var rejectedLink=false
do {_ = try UserRequestChannel.consume(uid:Int(getuid()),folder:privateRequestFolder)}catch{rejectedLink=true}
check(rejectedLink,"request channel refuses symlinks rather than following user-selected paths")
try FileManager.default.removeItem(at:privateRequestFile)
try JSONEncoder().encode(requestFixture).write(to:privateRequestFile)
try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:privateRequestFile.path)
var rejectedPublic=false
do {_ = try UserRequestChannel.consume(uid:Int(getuid()),folder:privateRequestFolder)}catch{rejectedPublic=true}
check(rejectedPublic,"request channel requires private request permissions")
check(UserUpdateRequest.allowed(policyAvailable:true,enabled:true,dryRun:false,requestsEnabled:true,pending:false,monitor:true,target:"27.2",running:"27.0"),"status menu permits only a live eligible configured target request")
check(!UserUpdateRequest.allowed(policyAvailable:true,enabled:true,dryRun:false,requestsEnabled:true,pending:true,monitor:true,target:"27.2",running:"27.0"),"status menu does not offer duplicate installation while verification is pending")
check(!UserUpdateRequest.allowed(policyAvailable:true,enabled:true,dryRun:false,requestsEnabled:true,pending:false,monitor:nil,target:"27.2",running:"27.0"),"unknown monitor state never becomes an available update service")
check(!UserUpdateRequest.allowed(policyAvailable:true,enabled:true,dryRun:false,requestsEnabled:true,pending:false,monitor:true,target:"27.2",running:"27.2"),"compliant status does not request unnecessary updates")
check(NotificationHistoryPolicy.result(7,visible:true,state:"updateRecovery").0=="completed","automatic recovery expiry stays separate from a user Update choice")
let recoveryDefaults=CLIConfig.parse(yaml:"update:\n  deadlineRecoveryEnabled: true\n  retryCountdownMinutes: 12\nui:\n  menuBarEnabled: false\n")
check(recoveryDefaults.update.retryCountdownMinutes==12 && !recoveryDefaults.ui.menuBarEnabled,"recovery and menu policy are configurable in preserved YAML")

let majorSample=MajorUpgradeDemoOptions.sample
check(majorSample.current=="26.0" && majorSample.target=="27.0","major demo uses explicitly illustrative version data")
let parsedMajorDefault=try MajorUpgradeDemoOptions.parse(["--debug"])
check(parsedMajorDefault == majorSample,"explicit debug flag enables only the sample parser")
func rejectsMajorOptions(_ args:[String])->Bool {do {_ = try MajorUpgradeDemoOptions.parse(args);return false}catch{return true}}
check(rejectsMajorOptions([]),"major offer cannot open a live path without explicit debug mode")
check(rejectsMajorOptions(["--debug","--live"]) && rejectsMajorOptions(["--debug","--install"]),"live and installation flags are rejected by the debug command")
check(rejectsMajorOptions(["--debug","--config","/Library/Management/PUSH/config.yaml"]),"demo parser cannot read a live config path")
check(rejectsMajorOptions(["--debug","--from","27.0","--to","27.2"]),"minor updates cannot be offered by the major-only demo")
check(rejectsMajorOptions(["--debug","--from","27.0","--to","26.0"]),"downgrades are rejected")
check(rejectsMajorOptions(["--debug","--from","26.0","--to","27beta"]),"non-numeric example targets are rejected")
check(rejectsMajorOptions(["--debug","--duration","nan"]) && rejectsMajorOptions(["--debug","--duration","0"]),"nonfinite and out-of-range demo timing cannot enter the state machine")
check(rejectsMajorOptions(["--debug","--debug"]),"duplicate debug arguments do not change capabilities")
let roundTripMajor=try MajorUpgradeDemoOptions.parse(majorSample.launchArguments)
check(roundTripMajor==majorSample,"typed launch arguments preserve validated sample options")
var majorFlow=MajorUpgradeSimulation()
majorFlow.advance(seconds:100)
check(majorFlow.phase == .offer,"time alone never accepts the optional offer")
majorFlow.restartNow()
check(majorFlow.phase == .offer,"restart cannot be selected before the ready stage")
majorFlow.chooseUpdate();majorFlow.advance(seconds:5)
check(majorFlow.phase == .downloading && majorFlow.progress>0 && majorFlow.progress<1,"Update begins simulated download progress")
majorFlow.togglePause();let frozenProgress=majorFlow.progress;majorFlow.advance(seconds:5)
check(majorFlow.progress==frozenProgress,"paused demo time does not advance progress")
majorFlow.togglePause();majorFlow.advance(seconds:8)
check(majorFlow.phase == .preparing,"one simulation changes from download into preparation")
majorFlow.advance(seconds:7)
check(majorFlow.phase == .restartReady,"preparation ends at a deliberate restart choice")
majorFlow.restartLater();majorFlow.advance(seconds:1000)
check(majorFlow.phase == .restartReady && majorFlow.message.contains("No real schedule"),"Later never starts an automatic or scheduled restart")
majorFlow.restartNow()
check(majorFlow.phase == .finished && majorFlow.message.contains("not restarted"),"Restart now completes the demo with a simulated result")
majorFlow.reset();majorFlow.notNow();majorFlow.advance(seconds:120)
check(majorFlow.phase == .declined,"Not now prevents all later simulated progress")
majorFlow.reset();majorFlow.chooseUpdate();majorFlow.keepWorking();majorFlow.advance(seconds:1)
check(majorFlow.phase == .downloading && majorFlow.progress>0,"Keep working continues the in-memory simulation")
majorFlow.fail("Authorization is not configured")
check(majorFlow.phase == .failed && majorFlow.message.contains("No system action"),"failure simulation cannot escalate into authentication or installation")
majorFlow.advance(seconds:120)
check(majorFlow.phase == .failed,"a failed demo does not retry automatically")
majorFlow.reset();majorFlow.chooseUpdate();majorFlow.skipStage()
check(majorFlow.phase == .preparing,"debug skip moves to preparation in the same state machine")
majorFlow.skipStage()
check(majorFlow.phase == .restartReady,"debug skip ends at ready rather than restarting")

var personal=PopupPresentation()
check(personal.greeting(fullName:"Sebastian Santos",username:"sebastian")=="Hello Sebastian Santos","greeting resolves the full name at display time")
personal.greetingTemplate="Hello {firstName} ({username})"
check(personal.greeting(fullName:"Sebastian Santos",username:"sebastian")=="Hello Sebastian (sebastian)","greeting tokens are plain substitutions, not executable templates")
check(personal.greeting(fullName:"",username:"someone")=="Hello someone (someone)","missing directory name falls back to the local account")
var badSize=personal;badSize.width=Double.nan
var sizeRejected=false;do{_=try badSize.validated()}catch{sizeRejected=true}
check(sizeRejected,"invalid/nonfinite window dimensions cannot reach the native window")
var badBanner=personal;badBanner.bannerImage=Data("not a PNG".utf8)
var bannerRejected=false;do{_=try badBanner.validated()}catch{bannerRejected=true}
check(bannerRejected,"banner payloads must be normalized PNG data")
let settingsWire=try JSONEncoder().encode(MajorOfferSettings())
check(String(data:settingsWire,encoding:.utf8)!.contains("{fullName}") && !String(data:settingsWire,encoding:.utf8)!.contains("Sebastian Santos"),"packages store the greeting template rather than the admin's name")
var noticeFixture=SinglePopupNotice(title:"IT message",message:"Literal text: $(do-not-execute)")
noticeFixture.debug=true
let noticeRoundTrip=try SinglePopupNotice.decode(noticeFixture.payload())
check(noticeRoundTrip.message==noticeFixture.message && noticeRoundTrip.debug,"standalone notices preserve literal message text without shell evaluation")
noticeFixture.style="unsupported-style"
var badNotice=false;do{_=try noticeFixture.payload()}catch{badNotice=true}
check(badNotice,"unsupported standalone notice styles fail validation")
let hardwareNow=Date(timeIntervalSince1970:1_800_000_000)
let currentList=AppleHardwareCatalog(fetchedAt:hardwareNow,releases:[.init(version:"27.0",posted:hardwareNow.addingTimeInterval(-86400),expires:hardwareNow.addingTimeInterval(86400),devices:["NEWBOARD"]),.init(version:"26.0",posted:hardwareNow.addingTimeInterval(-86400),expires:hardwareNow.addingTimeInterval(86400),devices:["OLDBOARD","NEWBOARD"])])
check(currentList.assess(.init(model:"Example new Mac",deviceKeys:["newboard"]),target:"27.0",now:hardwareNow).state == .supported,"exact Apple device identifiers establish major-family support")
check(currentList.assess(.init(model:"Example older Mac",deviceKeys:["OLDBOARD"]),target:"27",now:hardwareNow).state == .unsupported,"known older hardware absent from a fresh target list is unsupported for that major")
check(currentList.assess(.init(model:"Unfamiliar Mac",deviceKeys:["FUTUREBOARD"]),target:"27",now:hardwareNow).state == .unknown,"unfamiliar hardware is not falsely labeled unsupported")
check(currentList.assess(.init(model:"Example",deviceKeys:["NEWBOARD"]),target:"28",now:hardwareNow).state == .unknown,"unpublished major lists cannot create compatibility verdicts")
check(currentList.assess(.init(model:"Example",deviceKeys:[]),target:"27",now:hardwareNow).state == .unknown,"missing device identity stays unverified")
check(currentList.assess(.init(model:"MacBookPro16,1",deviceKeys:[],appleSilicon:false),target:"27",now:hardwareNow).state == .unknown,"missing identities do not become a generic CPU-only verdict")
check(currentList.assess(.init(model:"MacBookPro16,1",deviceKeys:["UNMAPPED-INTEL"],appleSilicon:false),target:"27",now:hardwareNow).state == .unsupported,"Apple's major-27 Apple-silicon requirement covers a verified Intel Mac family")
check(currentList.assess(.init(model:"Unknown PC",deviceKeys:["UNMAPPED"],appleSilicon:false),target:"27",now:hardwareNow).state == .unknown,"unknown non-Mac identities are not classified by the Intel Mac rule")
check(currentList.assess(.init(model:"Example",deviceKeys:["NEWBOARD"]),target:"27",now:hardwareNow.addingTimeInterval(31*86400)).state == .unknown,"expired/stale Apple evidence is never reported as current support")
var futureCatalog=currentList;futureCatalog.fetchedAt=hardwareNow.addingTimeInterval(1000)
check(futureCatalog.assess(.init(model:"Example",deviceKeys:["NEWBOARD"]),target:"27",now:hardwareNow).state == .unknown,"future-dated catalog metadata fails closed")
check(!RecoveryFailureKind.hardware.allowsAutomaticRetry,"unsupported hardware cannot get an automatic install retry countdown")


let shortNoticeSize=NoticeWindowLayout.size(width:480,heightLimit:680,measuredHeight:316,screenWidth:1440,screenHeight:900)
check(shortNoticeSize.height==316 && shortNoticeSize.width==480,"short notices fit content instead of retaining empty configured height")
let longNoticeSize=NoticeWindowLayout.size(width:480,heightLimit:400,measuredHeight:950,screenWidth:1440,screenHeight:900)
check(longNoticeSize.height==400,"long notices respect the configured height ceiling")
let smallScreenNotice=NoticeWindowLayout.size(width:900,heightLimit:1000,measuredHeight:900,screenWidth:800,screenHeight:600)
check(smallScreenNotice.width==760 && smallScreenNotice.height==520,"notice sizing leaves room for screen margins and window chrome")
let toastNoticeSize=NoticeWindowLayout.size(width:420,heightLimit:320,measuredHeight:245,screenWidth:1440,screenHeight:900)
check(toastNoticeSize.height==245,"short toast content shrinks below its height limit")
let markdownBlocks=NoticeMarkdown.blocks("# Heading\n\nSave **your work**.\n\n- First\n- Second\n1. Then this\n> Note\n```\nliteral *code*\n```")
check(markdownBlocks == [.heading(1,"Heading"),.paragraph("Save **your work**."),.bullet("First"),.bullet("Second"),.numbered("1.","Then this"),.quote("Note"),.code("literal *code*")],"Markdown preserves headings, separate list items, quotes and literal code")
check(NoticeMarkdown.blocks("One\nline\n\nTwo") == [.paragraph("One\nline"),.paragraph("Two")],"Markdown preserves line breaks and separate paragraphs")
check(NoticeMarkdown.blocks("```\nunclosed") == [.code("unclosed")],"an unfinished code fence remains readable")
let boldInline=NoticeMarkdown.inline("Save **your work** and *close apps*.")
check(String(boldInline.characters)=="Save your work and close apps.","inline Markdown removes formatting markers from rendered text")
check(NoticeMarkdown.allowsLink(URL(string:"https://example.com/help")!) && NoticeMarkdown.allowsLink(URL(string:"mailto:help@example.com")!),"web and email links can be opened by an explicit user click")
check(!NoticeMarkdown.allowsLink(URL(string:"file:///tmp/example")!) && !NoticeMarkdown.allowsLink(URL(string:"jamfselfservice://example")!),"local files and app-command URL schemes are blocked in notice Markdown")
let unsafeInline=NoticeMarkdown.inline("[Unsafe](file:///tmp/example) and [Safe](https://example.com)")
check(unsafeInline.runs.compactMap{$0.link}.allSatisfy{NoticeMarkdown.allowsLink($0)} && unsafeInline.runs.compactMap{$0.link}.count==1,"unsafe link targets are removed while safe links retain their attributes")
var laterResponse=NoticeResponseState()
check(laterResponse.respond(2) && !laterResponse.respond(0) && laterResponse.result==2,"close/secondary response cannot later become primary acknowledgement")
var acknowledgedResponse=NoticeResponseState(),ackRemaining=1
check(acknowledgedResponse.respond(0) && !acknowledgedResponse.tick(remaining:&ackRemaining,timeout:1) && acknowledgedResponse.result==0,"timer cannot overwrite a primary button response")
var timedResponse=NoticeResponseState(),testRemaining=2
check(!timedResponse.tick(remaining:&testRemaining,timeout:2) && timedResponse.tick(remaining:&testRemaining,timeout:2) && timedResponse.result==5 && !timedResponse.respond(0),"timeout returns its own result exactly once without claiming consent")
var noTimeoutResponse=NoticeResponseState(),zeroRemaining=0
check(!noTimeoutResponse.tick(remaining:&zeroRemaining,timeout:0) && noTimeoutResponse.result==nil,"never-close notices do not generate an automatic response")


var compact200=SinglePopupNotice(title:"Compact test",message:"Safe **Markdown** message")
compact200.presentation.height=200
check((try? compact200.payload()) != nil,"a 200-point popup passes validation and payload encoding")
let at200=NoticeWindowLayout.size(width:480,heightLimit:200,measuredHeight:500,screenWidth:1440,screenHeight:900)
check(at200.height==200,"a 200-point height limit is respected without a hidden 240-point clamp")
compact200.presentation.height=199
check((try? compact200.payload()) == nil,"heights below the documented 200-point minimum are rejected")


let defaultAuth=CLIConfig.parse(yaml:"auth:\n  localAccount: \"\"\n")
check(!defaultAuth.auth.promptUserForInstall,"installation credential prompts remain opt-in")
let optInAuth=CLIConfig.parse(yaml:"auth:\n  promptUserForInstall: true\n")
check(optInAuth.auth.promptUserForInstall,"YAML explicitly enables ephemeral installation authorization")
let fixtureReply=try JSONEncoder().encode(InstallAuthorizationReply(account:"fixture-user",password:"fixture-not-a-real-password"))
check(InstallAuthorizationReply.decode(fixtureReply,expectedAccount:"fixture-user") != nil,"private credential frame accepts the expected local account")
check(InstallAuthorizationReply.decode(fixtureReply,expectedAccount:"different-user") == nil,"credential replies cannot switch the authorizing account")
let invalidReply=try JSONEncoder().encode(InstallAuthorizationReply(account:"fixture-user",password:"invalid\npassword"))
check(InstallAuthorizationReply.decode(invalidReply,expectedAccount:"fixture-user") == nil,"credential frames reject newline-delimited extra input")
check(InstallAuthorizationReply.decode(Data(repeating:65,count:16385),expectedAccount:"fixture-user") == nil,"credential reply size is bounded before JSON decoding")
check(InstallAuthorizationReply.decode(Data("invalid".utf8),expectedAccount:"fixture-user") == nil,"malformed credential replies fail closed")


if let path=ProcessInfo.processInfo.environment["PUSH_CAMPAIGN_YAML"] {
    let campaignSource=try String(contentsOfFile:path,encoding:.utf8)
    let policy=CLIConfig.parse(yaml:campaignSource)
    check(policy.auth.promptUserForInstall && policy.auto.enabled && !policy.debug.dryRun,"campaign explicitly enables installation-only user authorization and monitoring")
    check(policy.auto.trackLatest && policy.auto.minorOnly && policy.auto.enforceMinimumMajorVersion==26,"campaign tracks Tahoe while enforcing its major version on older Macs")
    check(DiscoveryPolicy.eligible(version:"26.7.2",beta:false,current:"15.7",config:policy),"older supported Macs may upgrade into Tahoe")
    check(!DiscoveryPolicy.eligible(version:"27.0",beta:false,current:"15.7",config:policy) && !DiscoveryPolicy.eligible(version:"27.0",beta:false,current:"26.7",config:policy),"Tahoe campaign never promotes older or Tahoe Macs to macOS 27")
    check(!DiscoveryPolicy.eligible(version:"26.8",beta:true,current:"26.7",config:policy),"campaign excludes beta updates")
    check(!DiscoveryPolicy.eligible(version:"15.8",beta:false,current:"15.7",config:policy),"an older-major security update does not satisfy the Tahoe campaign")
    check(DiscoveryPolicy.eligible(version:"26.8",beta:false,current:"26.7",config:policy),"stable Tahoe point updates remain eligible")
    check(policy.update.deadline=="2026-11-16T23:00:00Z" && policy.update.autoInstallAfterDeadline && !policy.update.silentInstallAfterDeadline,"deadline enforcement starts at the reviewed explicit UTC timestamp with visible awareness")
    let central=DateFormatter();central.timeZone=TimeZone(identifier:"America/Chicago");central.dateFormat="yyyy-MM-dd HH:mm"
    check(central.string(from:ISO8601DateFormatter().date(from:policy.update.deadline)!)=="2026-11-16 17:00","deadline is Monday November 16 at 5 PM Central, accounting for standard time")
    check(policy.toastIntervalSeconds==3600 && policy.nudgeIntervalSeconds==86400 && !policy.schedule.respectAlertWindow && !policy.schedule.skipWeekends,"campaign has hourly toasts and daily reminders without weekday/hour restrictions")
    check(!policy.apps.enabled && !policy.entra.enabled && !policy.uptime.enabled && !policy.compliance.wallpaperEnabled,"campaign leaves unrelated modules disabled")
    var preserving="auth:\n  localAccount: \"fixture-managed-account\"\nui:\n  orgName: \"Fixture Org\"\n"
    preserving=try ConfigCommand.upsertingConfig(preserving,key:"auth.promptUserForInstall",value:"true")
    preserving=try ConfigCommand.upsertingConfig(preserving,key:"update.deadline",value:policy.update.deadline)
    check(CLIConfig.parse(yaml:preserving).auth.localAccount=="fixture-managed-account" && CLIConfig.parse(yaml:preserving).ui.orgName=="Fixture Org","overlay scalar changes preserve endpoint account and branding")
}


check(InstallAuthorizationReply.trustedRequester(uid:0,realUID:0,path:"/usr/bin/sudo",pipe:true),"root installation launcher may request a private authorization prompt")
check(!InstallAuthorizationReply.trustedRequester(uid:501,realUID:501,path:"/usr/bin/sudo",pipe:true),"unprivileged processes cannot request installation password UI")
check(!InstallAuthorizationReply.trustedRequester(uid:0,realUID:501,path:"/usr/bin/sudo",pipe:true),"a user-initiated setuid launcher is not the root installation worker")
check(!InstallAuthorizationReply.trustedRequester(uid:0,realUID:0,path:"/sbin/launchd",pipe:true),"generic LaunchAgent ancestry cannot unlock the credential prompt")
check(!InstallAuthorizationReply.trustedRequester(uid:0,realUID:0,path:"/usr/bin/sudo",pipe:false),"credential replies cannot be written to a terminal or regular file")


var boundedOS=CLIConfig.parse(yaml:"auto:\n  enabled: true\n  trackLatest: true\n  minorOnly: true\n  enforceMinimumMajorVersion: 26\n  maximumMajorVersion: 26\n")
check(boundedOS.auto.maximumMajorVersion==26,"workflow generation ceiling round-trips through engine YAML")
check(DiscoveryPolicy.eligible(version:"26.7.2",beta:false,current:"15.7",config:boundedOS),"generation-scoped workflows can upgrade older supported systems")
check(!DiscoveryPolicy.eligible(version:"27.1",beta:false,current:"27.0",config:boundedOS),"a Tahoe workflow stays quiet if a Mac independently moves above its selected generation")
check(!DiscoveryPolicy.eligible(version:"27.0",beta:false,current:"26.7",config:boundedOS),"generation ceiling cannot become a major upgrade")
boundedOS.auto.maximumMajorVersion=0;boundedOS.auto.minorOnly=false
check(DiscoveryPolicy.eligible(version:"27.1",beta:false,current:"26.7",config:boundedOS),"zero generation ceiling preserves existing unrestricted discovery behavior")


let pipeOnly=runDirect("/bin/sh",["-c","printf fixture-cache-value; printf fixture-warning >&2"],discardStderr:true)
check(pipeOnly.1==0 && pipeOnly.0=="fixture-cache-value","credential readers keep diagnostic stderr out of cached password bytes")

// Popup launches use LaunchServices, while attempt-bound receipts preserve choices.
let popupSession="push-ui-session-TEST"
for code:Int32 in [0,1,2,3,4,5,6,7,99] {
    let bytes=try JSONEncoder().encode(PopupResultReceipt(version:1,session:popupSession,code:code))
    check(PopupResultReceipt.decode(bytes,session:popupSession)==code,"popup receipt retains response \(code) without interpreting launch success as consent")
}
let receiptBytes=try JSONEncoder().encode(PopupResultReceipt(version:1,session:popupSession,code:0))
check(PopupResultReceipt.decode(receiptBytes,session:"another-attempt")==nil,"stale popup receipts cannot authorize a later attempt")
check(PopupResultReceipt.decode(Data(),session:popupSession)==nil,"successful app opening without a response is not Install")
check(PopupResultReceipt.decode(Data(repeating:32,count:4097),session:popupSession)==nil,"popup receipts are bounded before parsing")
let invalidReceipt=try JSONEncoder().encode(PopupResultReceipt(version:2,session:popupSession,code:0))
check(PopupResultReceipt.decode(invalidReceipt,session:popupSession)==nil,"unknown receipt protocols fail closed")
let uiPath="/Library/Management/PUSH/push-ui.app/Contents/MacOS/push-ui"
for command in ["'"+uiPath+"' --state toast", "\""+uiPath+"\" --state softNudge",uiPath+" --state rebootNudge"] {
    let openCommand=PopupLaunchProtocol.openCommand(command:command,binary:uiPath,ready:"/private/tmp/example/ready",result:"/private/tmp/example/result")
    check(openCommand?.contains("/usr/bin/open -n ")==true && openCommand?.contains(" -W ")==false && openCommand?.contains("--result-file")==true,"existing quoted UI commands launch through macOS with a result receipt")
}
check(PopupLaunchProtocol.openCommand(command:"/unrelated/app --state toast",binary:uiPath,ready:"r",result:"s")==nil,"a mismatched UI executable is rejected")

check(PopupSessionPolicy.decision(visible:false,receipt:nil,launcherFailure:false,startupExpired:false,responseExpired:false) == .wait,"launcher success before visibility continues waiting instead of implying Install")
check(PopupSessionPolicy.decision(visible:true,receipt:nil,launcherFailure:false,startupExpired:true,responseExpired:false) == .wait,"a visible popup keeps waiting for its receipt after the launcher exits")
check(PopupSessionPolicy.decision(visible:true,receipt:1,launcherFailure:false,startupExpired:true,responseExpired:false) == .finish(1),"Later receipt completes the independent controller as Later")
check(PopupSessionPolicy.decision(visible:false,receipt:0,launcherFailure:false,startupExpired:false,responseExpired:false) == .finish(103),"an Install receipt without visibility remains rejected")
check(PopupSessionPolicy.decision(visible:false,receipt:nil,launcherFailure:false,startupExpired:true,responseExpired:false) == .finish(103),"missing visibility times out even after a successful launcher exit")
check(PopupSessionPolicy.decision(visible:true,receipt:nil,launcherFailure:false,startupExpired:true,responseExpired:true) == .finish(100),"missing popup responses time out without installation consent")
check(PopupSessionPolicy.decision(visible:false,receipt:nil,launcherFailure:true,startupExpired:false,responseExpired:false) == .finish(99),"a failed launch is never treated as a user choice")

// Same-generation updates use Apple's offered point release, never a full fallback.
let pointReleaseOffer="""
Software Update Tool
Finding available software
Software Update found the following new or updated software:
* Label: macOS 27.2.1-26B131
    Title: macOS 27.2.1, Version: 27.2.1, Size: 6069131KiB, Recommended: YES, Action: restart,
"""
let pointOffer=NativeOSUpdate.parse(pointReleaseOffer).first!
check(pointOffer.label=="macOS 27.2.1-26B131" && pointOffer.version=="27.2.1" && pointOffer.restart,"native parser retains Apple's complete label, version and restart action")
check(MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:pointReleaseOffer) == .native(pointOffer),"27.2 minimum accepts Apple's native 27.2.1 offer")
check(MacOSUpdateRouting.route(running:"27.0",target:"27.2.1",listing:pointReleaseOffer) == .native(pointOffer),"an exact point-release target remains eligible for native update")
check(MacOSUpdateRouting.route(running:"15.7",target:"26.0",listing:pointReleaseOffer) == .fullInstaller,"15 to 26 remains a full-installer major upgrade")
check(MacOSUpdateRouting.route(running:"27.2.1",target:"27.2",listing:pointReleaseOffer) == .compliant,"an already-compliant Mac does not download an older target")
check(MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:"") != .fullInstaller,"an empty same-generation catalog never triggers a full-image fallback")
if case .unavailable = MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:pointReleaseOffer,catalogSucceeded:false) {check(true,"a failed Apple catalog query is blocked even when partial output contains an offer")}else{check(false,"a failed Apple catalog query is blocked even when partial output contains an offer")}
let majorOnlyOffer=pointReleaseOffer.replacingOccurrences(of:"27.2.1",with:"28.0")
if case .unavailable = MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:majorOnlyOffer) {check(true,"native point-update selection cannot cross to a newer generation")}else{check(false,"native point-update selection cannot cross to a newer generation")}
let oldOnlyOffer=pointReleaseOffer.replacingOccurrences(of:"27.2.1",with:"27.1")
if case .unavailable = MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:oldOnlyOffer) {check(true,"an offered native update below the minimum is rejected")}else{check(false,"an offered native update below the minimum is rejected")}
let betaOffer=pointReleaseOffer.replacingOccurrences(of:"27.2.1",with:"27.3").replacingOccurrences(of:"Title: macOS 27.3",with:"Title: macOS 27.3 Beta")
check(MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:betaOffer+"\n"+pointReleaseOffer) == .native(pointOffer),"default routing skips newer beta offers in favor of stable native updates")
let betaParsed=NativeOSUpdate.parse(betaOffer).first!
check(MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:betaOffer,skipBetas:false) == .native(betaParsed),"an explicitly beta-enabled policy retains its opt-in behavior")
let newerOffer=pointReleaseOffer.replacingOccurrences(of:"27.2.1",with:"27.10")
check(MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:pointReleaseOffer+"\n"+newerOffer) == .native(NativeOSUpdate.parse(newerOffer).first!),"numeric native offer ordering selects 27.10 above 27.2.1")
let safariOffer=pointReleaseOffer.replacingOccurrences(of:"Title: macOS",with:"Title: Safari")
check(NativeOSUpdate.parse(safariOffer).isEmpty,"unrelated app updates cannot masquerade as macOS updates by version")
check(NativeOSUpdate.parse(pointReleaseOffer.replacingOccurrences(of:"27.2.1",with:"27.x")).isEmpty,"malformed native versions cannot enter the install route")
if case .unavailable = MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:pointReleaseOffer,maximumMajor:26) {check(true,"native routing honors the selected generation ceiling")}else{check(false,"native routing honors the selected generation ceiling")}
let noRestartOffer=pointReleaseOffer.replacingOccurrences(of:"Action: restart,",with:"")
if case .unavailable = MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:noRestartOffer) {check(true,"installation routing retains its restart-qualified macOS offer requirement")}else{check(false,"installation routing retains its restart-qualified macOS offer requirement")}
check(MacOSUpdateRouting.route(running:"27.0",target:"27.2",listing:noRestartOffer,restartOnly:false) == .native(NativeOSUpdate.parse(noRestartOffer).first!),"download-only preparation can use an eligible native offer without invoking restart")
let rejectedLabel=pointReleaseOffer.replacingOccurrences(of:"Label: macOS 27.2.1-26B131",with:"Label: --all")
check(NativeOSUpdate.parse(rejectedLabel).isEmpty,"option-like native labels cannot alter softwareupdate arguments")
if case .unavailable = MacOSUpdateRouting.route(running:"27.0",target:"bad",listing:pointReleaseOffer) {check(true,"invalid policy targets fail before any route is selected")}else{check(false,"invalid policy targets fail before any route is selected")}
var nativeVersionState=CLIDeferralState()
nativeVersionState.beginInstallation(target:pointOffer.version,running:"27.0",boot:100)
check(nativeVersionState.installTargetVersion=="27.2.1","reboot verification records the actual selected native point release")

// Self Service selection uses fixtures only; no live catalog or authorization.
let offerCandidates:[AutoCheckCommand.DetectedUpdate]=[
    .init(version:"26.9",name:"macOS",isMajor:true,isBeta:false),
    .init(version:"26.10",name:"macOS",isMajor:true,isBeta:false),
    .init(version:"26.11",name:"macOS Beta",isMajor:true,isBeta:true),
    .init(version:"27.2",name:"macOS",isMajor:true,isBeta:false)]
check(SelfServiceOfferPolicy.latest(major:26,running:"15.7",updates:offerCandidates)?.version=="26.10","offer selects highest stable exact generation numerically")
check(SelfServiceOfferPolicy.latest(major:26,running:"27.0",updates:offerCandidates)==nil,"offer never downgrades a newer generation")
check(SelfServiceOfferPolicy.latest(major:26,running:"26.10",updates:offerCandidates)==nil,"offer does not reinstall the current release")
check(SelfServiceOfferPolicy.latest(major:28,running:"26.0",updates:offerCandidates)==nil,"offer rejects unsupported generation selector")
check(SelfServiceOfferPolicy.popupStates==Set(["downloading","preflightDisk","preflightPower","rebooting"]),"offer popup allowlist has only the four requested stages")
var campaign=CLIConfig();campaign.update.deadline="2026-01-01T00:00:00Z";campaign.update.autoInstallAfterDeadline=true;campaign.auto.enabled=true;campaign.entra.enabled=true
let isolated=SelfServiceOfferPolicy.isolated(campaign,major:26,version:"26.10",running:"15.7")!
check(isolated.update.deadline.isEmpty && !isolated.update.autoInstallAfterDeadline && !isolated.auto.enabled && !isolated.entra.enabled && !isolated.apps.enabled && !isolated.uptime.enabled && !isolated.compliance.wallpaperEnabled,"offer disables all campaign enforcement and unrelated tasks")
check(isolated.auth.promptUserForInstall && !isolated.debug.dryRun && isolated.auto.maximumMajorVersion==26,"offer permits existing user authorization within a fixed generation")
check(campaign.auto.enabled && campaign.entra.enabled && !campaign.update.deadline.isEmpty,"offer isolation leaves original campaign intact")
check(SelfServiceOfferPolicy.isolated(campaign,major:26,version:"27.0",running:"15.7")==nil,"offer rejects a mismatched selected version")
var offerState=CLIDeferralState();offerState.deferralCount=3;offerState.beginInstallation(target:"26.10",running:"15.7",boot:1,origin:"selfService")
check(offerState.installOrigin=="selfService" && offerState.deferralCount==3,"offer records install origin without resetting campaign deferrals")
var installedAuthorization=CLIConfig();installedAuthorization.auth.localAccount="managed-admin";installedAuthorization.auth.localPassword="fixture-only";installedAuthorization.auto.enabled=true;installedAuthorization.update.deadline="2026-01-01T00:00:00Z"
let authorizedOffer=SelfServiceOfferPolicy.withManagedAuthorization(isolated,installed:installedAuthorization)
check(authorizedOffer.auth.localAccount=="managed-admin" && authorizedOffer.auth.localPassword.isEmpty && authorizedOffer.auth.promptUserForInstall,"offer prefers configured managed account with existing prompt as fallback, without importing plaintext local password")
check(!authorizedOffer.auto.enabled && authorizedOffer.update.deadline.isEmpty,"authorization inheritance cannot reactivate campaign settings")
check(installedAuthorization.auth.localPassword=="fixture-only" && installedAuthorization.auto.enabled,"authorization inheritance preserves installed policy")
SelfServiceUpgradeCommand(args:["--major","26","--dry-run"]).run()
check(true,"offer dry-run returns before root, configuration, catalog, Keychain and installer access")
for (name,version,expected) in [("macOS 26","26","macOS 26"),("macOS 26","26.2.1","macOS 26.2.1"),("macOS Tahoe 26.0","26.2","macOS Tahoe 26.2"),("macOS Tahoe","26.2","macOS Tahoe 26.2"),("macOS","27.0","macOS 27.0"),("","27.1","macOS 27.1"),("macOS Tahoe","","macOS Tahoe")] {
    check(DownloadWording.label(name:name,version:version)==expected,"download label avoids repeated generation: \(name) / \(version)")
}
check(DownloadWording.render("Preparing {macOS} · {version} · {osName}",name:"macOS Tahoe",version:"26.2")=="Preparing macOS Tahoe 26.2 · 26.2 · macOS Tahoe","download wording resolves supported release tokens")
check(DownloadWording.render(" ",name:"macOS 26",version:"26",fallback:DownloadWording.title)=="Downloading macOS 26","blank download title falls back without duplicating the version")
check(DownloadWording.render("Hello {unknown} $(touch /tmp/no) `none`",name:"macOS",version:"26")=="Hello {unknown} $(touch /tmp/no) `none`","download copy preserves unknown tokens and shell-like text as literal display content")
check(DownloadWording.render("{osName} / {version}",name:"IT {version}",version:"26")=="IT {version} / 26","download tokens are expanded once without recursion")
check(DownloadWording.render("🚀 {macOS} — {version}",name:"macOS",version:"26.2")=="🚀 macOS 26.2 — 26.2","download wording preserves Unicode with multiple replacements")
let downloadConfiguration=CLIConfig.parse(yaml:"ui:\n  downloadHeader: \"From IT\"\n  downloadTitle: \"Preparing {macOS}\"\n  downloadingMessage: \"Continue working.\"\n  downloadFooter: \"Stay connected.\"\n")
check(downloadConfiguration.ui.downloadHeader=="From IT" && downloadConfiguration.ui.downloadTitle=="Preparing {macOS}" && downloadConfiguration.ui.downloadingMessage=="Continue working." && downloadConfiguration.ui.downloadFooter=="Stay connected.","engine reads all editable download copy fields")

// Quoted YAML scalars with trailing comments must not become deadline values.
let quotedBlank="update:\n  deadline: \"\"  # Explicit ISO 8601 override; blank uses automatic\n"
check(CLIConfig.parse(yaml:quotedBlank).update.deadline.isEmpty,"quoted blank deadline with trailing comment remains empty")
check(CLIConfig.parse(yaml:"update:\n  deadline: '' # blank\n").update.deadline.isEmpty,"single-quoted blank deadline with comment remains empty")
let commentedDate="2026-12-01T23:00:00Z"
check(CLIConfig.parse(yaml:"update:\n  deadline: \"\(commentedDate)\" # IT deadline\n").update.deadline==commentedDate,"quoted explicit deadline retains exact timestamp and drops comment")
let scalarEdges="""
ui:
  appName: "Team #1 \\"quoted\\"" # display name
  orgName: 'Don''t remove # inside' # outside
  helpURL: https://example.invalid/help#install # outside
  accentColorHex: "#0A84FF" # color
update:
  deadline: "not-a-date" # still invalid
"""
let scalarConfig=CLIConfig.parse(yaml:scalarEdges)
check(scalarConfig.ui.appName=="Team #1 \"quoted\"","hashes and escaped quotes inside strings survive comment stripping")
check(scalarConfig.ui.orgName=="Don't remove # inside","doubled single quotes and embedded hashes are preserved")
check(scalarConfig.ui.helpURL=="https://example.invalid/help#install","unquoted URL fragment survives a trailing YAML comment")
check(scalarConfig.ui.accentColorHex=="#0A84FF","quoted color hash survives trailing comment")
check(scalarConfig.update.deadline=="not-a-date","invalid nonblank deadlines remain invalid instead of silently cleared")
let shippedTemplate=try String(contentsOfFile:"Packaging/default-config.yaml",encoding:.utf8)
check(CLIConfig.parse(yaml:shippedTemplate).update.deadline.isEmpty,"actual shipped default config has an empty valid deadline override")
let repairedBlank=try ConfigCommand.upsertingConfig(quotedBlank,key:"update.deadline",value:"")
check(CLIConfig.parse(yaml:repairedBlank).update.deadline.isEmpty && !repairedBlank.contains("deadline: \"\"  #"),"config set empty deadline repairs the affected legacy scalar")
check(CLIConfig.parse(yaml:"update:\n  targetVersion: \"26.10\" # preserve version\n").update.targetVersion=="26.10","quoted version strings preserve trailing digits instead of numeric coercion")
// A harmless child drives the real prepare-complete signal path. It is not an
// installer, uses no password, and cannot restart the computer.
let observedRestartLock=NSLock()
var observedRestarts=0,observedLiveChild=false
let observedRestart=PreparedRestartObserver { process in
    observedRestartLock.lock();observedRestarts+=1;observedLiveChild=process.isRunning;observedRestartLock.unlock()
}
let fixtureSignalScript="printf 'Preparing: 45.0%%\\n'; /bin/sleep 0.2; kill -USR1 \"$1\"; /bin/sleep 0.2; kill -USR1 \"$1\"; /bin/sleep 0.2"
let observedProcess=runDirectStarted("/bin/sh",["-c",fixtureSignalScript,"fixture",String(getpid())],onStart:{process in observedRestart.started(process:process)})
observedRestart.stop()
observedRestartLock.lock();let restartCount=observedRestarts,liveAtRestart=observedLiveChild;observedRestartLock.unlock()
check(observedProcess.1==0 && observedProcess.0.contains("Preparing: 45.0%"),"harmless child output is streamed while observing prepare-complete signal")
check(restartCount==1,"duplicate preparation signals announce restart only once")
check(liveAtRestart,"restart announcement is associated with a still-running child")

print("Passed \(count) safe regression checks. No macOS installation commands were executed.")
