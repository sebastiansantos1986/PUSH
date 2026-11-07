// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation

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

check(sameOSVersion("26.1", "26.1.0"), "normalize trailing zero")
check(!sameOSVersion("26.1", "26.10"), "reject version prefix collision")
for malformed in ["", "26", "26..1", "26.1beta", "26.1;touch x", "26.1.0.1", "２６.１"] {
    check(numericOSVersion(malformed) == nil, "reject malformed target \(malformed)")
}
check(versionGTE("27.0", "27") && versionGTE("27", "27.0"), "major-only and dotted versions are equally compliant")
check(!versionGTE("26.9", "27"), "older OS still counts as a pending update")
check(!allowsUserPasswordPrompts, "managed policy disables end-user password prompts")
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
try FileManager.default.removeItem(at: right.appendingPathComponent("Contents/Resources/startosinstall"))
check(!InstallerValidation.matches(right.path, target: "26.1"), "missing installer tool rejected")
let metadata = root.appendingPathComponent("asset.xml")
try PropertyListSerialization.data(fromPropertyList: ["Assets": [["OSVersion": "26.1"]]], format: .xml, options: 0).write(to: metadata)
check(InstallerValidation.productVersion(in: metadata) == "26.1", "modern MobileAsset metadata parsed")
try PropertyListSerialization.data(fromPropertyList: ["Assets": [["OSVersion": "26.1"], ["OSVersion": "26.2"]]], format: .xml, options: 0).write(to: metadata)
check(InstallerValidation.productVersion(in: metadata) == nil, "ambiguous asset versions rejected")

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

print("Passed \(count) safe regression checks. No macOS installation commands were executed.")
