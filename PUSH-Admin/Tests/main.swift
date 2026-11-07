// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
// Stand-in for the engine's I/O error enum; engine configuration parsing is real.
enum CLIError: Error {case configNotFound}
var checks = 0
func check(_ condition: @autoclosure ()->Bool,_ label:String){
    guard condition() else {fputs("FAIL: \(label)\n",stderr);exit(1)}
    checks += 1; print("PASS: " + label)
}
var fresh = ConfigDocument.fresh
check(fresh.problems.isEmpty,"new draft validates")
let engine = CLIConfig.parse(yaml:fresh.yaml)
check(engine.debug.dryRun && !engine.auto.enabled,"new YAML uses safe engine defaults")
check(!engine.update.autoInstallAfterDeadline && !engine.update.silentInstallAfterDeadline,"deadline installation disabled by default")
check(!engine.auto.autoInstallNonSystemUpdates,"background extras disabled in new draft")
check(!engine.uptime.enabled,"restart enforcement disabled in new draft")
let source = """
# keep my comment
# clientSecret: COMMENT-CREDENTIAL
ui:
  appName: "Existing title"
  customField: "keep this"
auth:
  localAccount: "managedadmin"
  localPassword: |
    PRIVATE-CREDENTIAL
laps:
  enabled: true
  clientId: "public-id"
  clientSecret: "PRIVATE-API-CREDENTIAL"
custom:
  flag: true
"""
var imported = ConfigDocument.load(source,name:"import.yaml")
check(imported.omittedCredentials==2,"counts omitted credentials")
check(!imported.yaml.contains("PRIVATE-CREDENTIAL") && !imported.yaml.contains("PRIVATE-API-CREDENTIAL") && !imported.yaml.contains("COMMENT-CREDENTIAL"),"secrets and credential comments excluded")
check(imported.yaml.contains("# keep my comment") && imported.yaml.contains("customField: \"keep this\"") && imported.yaml.contains("custom:\n  flag: true"),"unknown fields and unrelated comments preserved")
check(imported.value("auth.localAccount")=="managedadmin","managed account imported")
let importedEngine = CLIConfig.parse(yaml:imported.yaml)
check(importedEngine.jamf.laps.enabled && importedEngine.jamf.laps.clientId=="public-id","export uses engine-compatible top-level LAPS")
check(importedEngine.debug.dryRun && !importedEngine.update.autoInstallAfterDeadline,"missing imported values match the effective UI defaults")
imported.edits["ui.appName"]="PUSH Admin Test"
check(CLIConfig.parse(yaml:imported.yaml).ui.appName=="PUSH Admin Test","form change round-trips through engine parser")
let duplicates = ConfigDocument.load("ui:\n  appName: one\n  appName: two\n",name:"duplicates")
check(duplicates.yaml.components(separatedBy:"  appName:").count==2,"known duplicate fields are consolidated")
fresh.edits["update.targetVersion"]="27.1"
fresh.edits["schedule.alertStartHour"]="19";fresh.edits["schedule.alertEndHour"]="8"
check(!fresh.problems.isEmpty,"invalid schedule is rejected")
fresh.edits["schedule.alertEndHour"]="23"
fresh.edits["update.deadline"]="tomorrow"
check(!fresh.problems.isEmpty,"ambiguous deadline rejected")
fresh.edits["update.deadline"]="2026-12-01T18:00:00Z"
check(fresh.problems.isEmpty,"explicit ISO deadline accepted")
fresh.edits["jamf.url"]="http://example.com"
check(!fresh.problems.isEmpty,"plaintext management URLs rejected")
let malformed = ConfigDocument.load("this is not YAML",name:"bad.yaml")
check(!malformed.problems.isEmpty,"malformed import cannot be exported or applied")
let duplicateSections = ConfigDocument.load("ui:\n  appName: one\nui:\n  appName: two\n",name:"duplicate-sections.yaml")
check(!duplicateSections.problems.isEmpty,"ambiguous duplicate sections rejected")
let multiline = ConfigDocument.load("ui:\n  minorMessage: |\n    First line\n    Second line\n",name:"multiline.yaml")
check(multiline.value("ui.minorMessage")=="First line\nSecond line\n" || multiline.value("ui.minorMessage")=="First line\nSecond line","known multiline messages are read for form editing")
let json = """
[
 {"name":"macOS A","version":"27.1","build":"B1","compatible":true},
 {"name":"macOS B","version":"27.10","build":"B2","compatible":true},
 {"name":"macOS Beta","version":"28.0","build":"X","compatible":true},
 {"name":"macOS C","version":"29.0","build":"Y","beta":1},
 {"name":"macOS D","version":"30.0","build":"Z","compatible":false},
 {"name":"macOS B","version":"27.10","build":"B2","compatible":true}
]
"""
let releases=try CatalogRelease.parse(Data(json.utf8))
check(releases.count==2,"catalog excludes beta, incompatible, and duplicate entries")
check(releases.first?.version=="27.10","catalog uses numeric version sorting")
let mixed=try CatalogRelease.parse(Data("{\"installers\":[{\"Name\":\"macOS\",\"Version\":\"27.0\",\"Build\":\"A\",\"Compatible\":\"True\"}]}".utf8))
check(mixed.first?.version=="27.0","catalog handles wrapped exports and mixed-case fields")
check(versionParts("27.0") == [27,0,0] && versionParts("27.0;touch x")==nil,"versions reject executable text")
check(shellQuote("a'b")=="'a'\\''b'","admin command paths are shell-quoted")
for viewport in [0.0, 1, 320, 600, 1200, Double.infinity, Double.nan] {
    for width in [-1.0, 420, 540, 900, Double.infinity, Double.nan] {
        let sizing = PreviewSizing(cardWidth:width,viewportWidth:viewport,contentHeight:800)
        check(sizing.scaledWidth.isFinite && sizing.scaledWidth > 0 && sizing.scaledHeight.isFinite && sizing.scaledHeight > 0,"preview bounds stay positive and finite")
        check(sizing.scale > 0 && sizing.scale <= 1,"preview scale cannot grow beyond the card")
    }
}
check(PreviewSizing(cardWidth:540,viewportWidth:600,contentHeight:800).scale == 1,"full-width canvas keeps native popup size")
check(abs(PreviewSizing(cardWidth:900,viewportWidth:500,contentHeight:1000).scaledWidth - 460) < 0.001,"wide popup fits within canvas padding")
let imageURL = URL(fileURLWithPath:CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/Fixtures/red-pixel.png")
let normalizedLogo = try BrandingImage.normalizedPNG(Data(contentsOf:imageURL))
check(normalizedLogo.starts(with:[137,80,78,71,13,10,26,10]),"custom image is exported as a PNG")
check((try? BrandingImage.normalizedPNG(Data("not an image".utf8))) == nil,"invalid logo input is rejected")
var withLogo = ConfigDocument.fresh
withLogo.logoImageData = normalizedLogo; withLogo.logoImageName = "red-pixel.png"
withLogo.edits["ui.logoPath"] = deployedPopupLogoPath
check(!withLogo.yaml.contains("\\/"),"logo paths are emitted without escaped slashes for PUSH's minimal YAML reader")
let savedLogo = try JSONDecoder().decode(ConfigDocument.self,from:JSONEncoder().encode(withLogo))
check(savedLogo.logoImageData == normalizedLogo && savedLogo.logoImageName == "red-pixel.png","selected logo survives draft persistence")
check(CLIConfig.parse(yaml:withLogo.yaml).ui.logoPath == deployedPopupLogoPath,"custom logo deployment path round-trips through engine config")
withLogo.edits["ui.logoPath"] = ""
withLogo.edits["ui.sfSymbolName"] = "building.2.fill"
check(CLIConfig.parse(yaml:withLogo.yaml).ui.sfSymbolName == "building.2.fill","system symbol selection reaches engine config")
var legacyDraft = try JSONSerialization.jsonObject(with:JSONEncoder().encode(ConfigDocument.fresh)) as! [String:Any]
legacyDraft.removeValue(forKey:"logoImageData");legacyDraft.removeValue(forKey:"logoImageName")
check((try? JSONDecoder().decode(ConfigDocument.self,from:JSONSerialization.data(withJSONObject:legacyDraft))) != nil,"older drafts remain readable without logo fields")
var setup = ConfigDocument.fresh
setup.edits["update.deadline"] = "2026-12-01T18:00:00Z"
setup.edits["ui.orgName"] = "Sebastian Test"
setup.followReleases(allowMajorUpgrades: false)
let automaticMinor = CLIConfig.parse(yaml: setup.yaml)
check(automaticMinor.auto.enabled && automaticMinor.auto.trackLatest && automaticMinor.auto.minorOnly, "set-once current-major preset configures tracking")
check(automaticMinor.debug.dryRun && !automaticMinor.update.autoInstallAfterDeadline, "preset preserves test mode and installation choices")
check(automaticMinor.update.deadline == "2026-12-01T18:00:00Z" && automaticMinor.ui.orgName == "Sebastian Test", "preset preserves deadline override and branding")
setup.followReleases(allowMajorUpgrades: true)
check(!CLIConfig.parse(yaml: setup.yaml).auto.minorOnly, "major-upgrade preset permits newer majors")
let automaticYAML = """
update:
  targetVersion: "27.1"
  deadline: ""
  automaticDeadline: "2026-12-05T18:00:00Z"
  automaticDeadlineTarget: "27.1"
"""
let testFolder = FileManager.default.temporaryDirectory.appendingPathComponent("push-ui-policy-" + UUID().uuidString)
try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: testFolder) }
let yamlPath = testFolder.appendingPathComponent("config.yaml")
try automaticYAML.write(to: yamlPath, atomically: true, encoding: .utf8)
check(UIConfig.load(from: yamlPath.path).update.deadline == "2026-12-05T18:00:00Z", "popup uses matching generated deadline")
try automaticYAML.replacingOccurrences(of: "deadline: \"\"", with: "deadline: \"2026-12-01T18:00:00Z\"").write(to: yamlPath, atomically: true, encoding: .utf8)
check(UIConfig.load(from: yamlPath.path).update.deadline == "2026-12-01T18:00:00Z", "popup honors explicit YAML override")
try automaticYAML.replacingOccurrences(of: "targetVersion: \"27.1\"", with: "targetVersion: \"28.0\"").write(to: yamlPath, atomically: true, encoding: .utf8)
check(UIConfig.load(from: yamlPath.path).update.deadline.isEmpty, "popup rejects another target's generated deadline")


var appDraft = ConfigDocument.fresh
appDraft.approveApp("chrome",enabled:true)
appDraft.approveApp("firefox",enabled:true)
appDraft.approveApp("chrome",enabled:true)
check(appDraft.value("apps.approved") == "chrome,firefox", "app selection writes one approved ID per app")
check(appDraft.value("apps.enabled") == "false" && appDraft.value("apps.autoUpdateClosed") == "false", "selecting apps alone cannot activate updates")
appDraft.approveApp("unknown",enabled:true)
check(appDraft.value("apps.approved") == "chrome,firefox", "UI cannot approve unknown catalog entries")
appDraft.edits["apps.enabled"] = "true"
appDraft.edits["apps.chromeDeadline"] = "2026-12-01T18:00:00Z"
let exportedApps = CLIConfig.parse(yaml:appDraft.yaml)
check(exportedApps.apps.enabled && exportedApps.apps.approved == "chrome,firefox", "approved app policy round-trips to engine")
check(exportedApps.apps.chromeDeadline == "2026-12-01T18:00:00Z" && appDraft.problems.isEmpty, "per-app deadline exports and validates")
appDraft.edits["apps.chromeDeadline"] = "next week"
check(!appDraft.problems.isEmpty, "ambiguous app deadline cannot apply")
appDraft.edits["apps.chromeDeadline"] = ""
appDraft.approveApp("chrome",enabled:false);appDraft.approveApp("firefox",enabled:false)
check(!appDraft.problems.isEmpty, "enabled app management requires explicit approval")
appDraft.edits["apps.enabled"] = "false"
check(appDraft.problems.isEmpty, "paused app management allows an empty list")
appDraft.edits["apps.approved"] = "unreviewed"
check(!appDraft.problems.isEmpty, "unreviewed script labels cannot enter exported policy")
let appContext = UIContext(config:UIConfig.preview(),state:.appUpdates,deferralCount:0)
appContext.exit(.install)
check(appContext.demoAction.contains("No apps were updated"), "app preview Update button remains simulated")
appContext.exit(.defer_)
check(appContext.demoAction.contains("deferred"), "app preview Later returns a deferral")
check(previewButtonTitle(state:"appUpdates",code:0) == "Update Closed Apps", "button audit identifies the app action correctly")
let appNoticeData = try JSONEncoder().encode(AppUpdateNotice.examples).base64EncodedString()
check(AppUpdateNotice.decodePayload(appNoticeData)?.count == 3, "preview and engine share grouped app payload format")

var appPreviewDraft = ConfigDocument.fresh
appPreviewDraft.approveApp("vscode",enabled:true)
appPreviewDraft.edits["apps.vscodeDeadline"] = "2026-12-01T18:00:00Z"
check(appPreviewDraft.appPreviewNotices().count == 1 && appPreviewDraft.appPreviewNotices().first?.id == "vscode", "app preview reflects selected app")
check(appPreviewDraft.appPreviewNotices().first?.deadline == "2026-12-01T18:00:00Z", "app preview reflects per-app YAML deadline override")

var entraDraft = ConfigDocument.fresh
check(entraDraft.value("entra.enabled") == "false", "Entra draft is opt-in")
entraDraft.edits["entra.enabled"] = "true"; entraDraft.edits["entra.policyID"] = "876"
let exportedEntra = CLIConfig.parse(yaml:entraDraft.yaml)
check(exportedEntra.entra.enabled && exportedEntra.entra.policyID == "876", "Entra setup round-trips into engine policy")
check(exportedEntra.entra.startHour == 8 && exportedEntra.entra.endHour == 18 && exportedEntra.entra.weekdaysOnly, "Entra business-hour defaults are explicit")
check(entraDraft.problems.isEmpty, "default Entra workflow validates")
entraDraft.edits["entra.policyID"] = "876&action=execute"
check(!entraDraft.problems.isEmpty, "unsafe policy deep-link input cannot apply")
entraDraft.edits["entra.policyID"] = "876"; entraDraft.edits["entra.endHour"] = "7"
check(!entraDraft.problems.isEmpty, "inverted Entra hours rejected")
entraDraft.edits["entra.endHour"] = "18"; entraDraft.edits["entra.jamfBinaryPath"] = "/bin/sh"
check(!entraDraft.problems.isEmpty, "arbitrary root recon executable cannot be configured")
entraDraft.edits["entra.jamfBinaryPath"] = "/usr/local/bin/jamf"
entraDraft.edits["entra.message"] = "Fixture registration message"
check(entraDraft.entraPreviewNotice(stage:3).message == "Fixture registration message" && entraDraft.entraPreviewNotice(stage:3).laterCount == 8, "registration preview reflects draft text and escalation stage")
let registrationContext = UIContext(config:UIConfig.preview(),state:.entraRegistration,deferralCount:0)
registrationContext.exit(.install)
check(registrationContext.demoAction.contains("Self Service was not opened"), "Register Now preview cannot launch registration")
registrationContext.exit(.defer_)
check(registrationContext.demoAction.contains("deferred"), "registration Later preview is simulated")
check(previewButtonTitle(state:"entraRegistration",code:0) == "Register Now", "button audit distinguishes registration from app/OS installation")
let originalModuleDefaults = CLIConfig.parse(yaml:ConfigDocument.fresh.yaml)
check(!originalModuleDefaults.entra.enabled && !originalModuleDefaults.apps.enabled && !originalModuleDefaults.auto.enabled && originalModuleDefaults.debug.dryRun, "adding Entra never enables other automation in a fresh draft")

// Readiness uses fixture files and an injected service reader. No live checks.
let readinessNow=ISO8601DateFormatter().date(from:"2026-11-06T20:00:00Z")!
let missingService=LaunchdObservation(loaded:false,detail:"Absent fixture")
let loadedService=LaunchdObservation(loaded:true,detail:"Loaded fixture")
func readinessMonitor(_ observed:LaunchdObservation,_ definition:Bool? = false,_ intent:ObservedIntent? = nil,_ health:ObservedHealth? = nil)->MonitorReadiness {
    .evaluate(definition:definition,observed:observed,intent:intent,health:health,interval:3600,now:readinessNow,expected:true,dryRun:false)
}
check(readinessMonitor(missingService).title == "Missing","readiness distinguishes missing monitoring")
let pause=ObservedIntent(desired:"paused",changedAt:readinessNow,reason:"Fixture pause")
check(readinessMonitor(missingService,false,pause).title == "Paused","readiness distinguishes explicit pause")
check(readinessMonitor(missingService,true).title == "Installed, not loaded","plist presence does not prove service loaded")
check(readinessMonitor(.init(loaded:nil,detail:"Denied"),true).title == "State unknown","unreadable service is not declared stopped")
check(readinessMonitor(loadedService,true).title == "Loaded · not yet verified","loaded service without heartbeat is not called healthy")
check(readinessMonitor(loadedService,false,pause).title == "Loaded · review setup","loaded service wins over a saved pause request")
var heartbeat=ObservedHealth(module:"macos",source:"scheduled",startedAt:readinessNow.addingTimeInterval(-10),updatedAt:readinessNow,finishedAt:readinessNow,phase:"completed",reason:"Completed fixture")
check(readinessMonitor(loadedService,true,nil,heartbeat).title == "Monitor loaded","recent scheduled result confirms loaded service")
heartbeat.updatedAt=readinessNow.addingTimeInterval(-8000)
check(readinessMonitor(loadedService,true,nil,heartbeat).title == "Overdue","stale scheduled result becomes overdue")
heartbeat.updatedAt=readinessNow;heartbeat.finishedAt=nil;heartbeat.phase="waitingForUser"
check(readinessMonitor(.init(loaded:true,running:true,detail:"Fixture"),true,nil,heartbeat).title == "Waiting for response","live prompt is distinguished from stalled service")
heartbeat.updatedAt=readinessNow.addingTimeInterval(-200)
check(readinessMonitor(loadedService,true,nil,heartbeat).title == "Last check unfinished","unfinished stopped check is actionable")
check(LaunchdObservation.parse(exit:113,text:"Could not find service com.push.autoupdate").loaded == false,"known missing-service response is classified")
check(LaunchdObservation.parse(exit:1,text:"Operation not permitted").loaded == nil,"permission failure stays unknown")
check(LaunchdObservation.parse(exit:0,text:" state = running\n").running,"launchd running state parses")
var utc=Calendar(identifier:.gregorian);utc.timeZone=TimeZone(secondsFromGMT:0)!
let hours=DashboardHours(start:8,end:18,weekdays:true)
let lateFriday=ISO8601DateFormatter().date(from:"2026-11-06T19:00:00Z")!
let monday=ISO8601DateFormatter().date(from:"2026-11-09T08:00:00Z")!
check(hours.nextAllowed(lateFriday,calendar:utc) == monday,"next eligibility skips weekend")
check(DashboardHours(start:18,end:8,weekdays:false).nextAllowed(readinessNow,calendar:utc) == nil,"invalid working hours have no inferred eligibility")
let readinessFolder=FileManager.default.temporaryDirectory.appendingPathComponent("push-readiness-fixture-"+UUID().uuidString)
try FileManager.default.createDirectory(at:readinessFolder.appendingPathComponent("health"),withIntermediateDirectories:true)
defer{try? FileManager.default.removeItem(at:readinessFolder)}
let fixturePolicy="""
auto:
  enabled: true
update:
  targetVersion: "27.2"
  deadline: "2026-11-11T03:01:30Z"
apps:
  enabled: false
entra:
  enabled: true
debug:
  dryRun: false
"""
try Data(fixturePolicy.utf8).write(to:readinessFolder.appendingPathComponent("config.yaml"))
try Data("fixture only; never executed".utf8).write(to:readinessFolder.appendingPathComponent("push-cli"))
try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:readinessFolder.appendingPathComponent("push-cli").path)
var queryLabels:[String]=[]
var reader=ReadinessReader(base:readinessFolder.path,daemonFolder:readinessFolder.appendingPathComponent("daemons").path,uid:501,user:"fixture",now:readinessNow,query:{label in queryLabels.append(label);return missingService})
var snap=reader.load();snap.runningOS="27.0";snap.calendar=utc
check(Set(queryLabels) == Set(["com.push.autoupdate","com.push.entra-registration"]),"passive reader only queries the two known services")
check(snap.policy?.dryRun == false && snap.policy?.macEnabled == true,"installed policy uses engine defaults and saved values")
check(snap.modules[0].status == "Missing","due toast does not imply delivery without a monitor")
check(snap.modules[2].status == "Missing","enabled Entra without saved evidence needs monitoring")
var userFixture=EntraUserState();userFixture.userName="fixture";userFixture.status = .notApplicable;userFixture.checkedAt=readinessNow
try JSONEncoder().encode(EntraNudgeState(users:["501":userFixture])).write(to:readinessFolder.appendingPathComponent("entra-state.json"))
snap=reader.load()
check(snap.modules[2].status == "Inactive on this Mac","unenrolled result stays inactive without a misleading enable-monitor recommendation")
reader.user="other";snap=reader.load()
check(snap.entra == nil,"saved registration evidence is scoped to current UID and name")
reader.user="fixture";reader.query={_ in loadedService}
try FileManager.default.createDirectory(at:readinessFolder.appendingPathComponent("daemons"),withIntermediateDirectories:true)
try PropertyListSerialization.data(fromPropertyList:["StartInterval":3600],format:.xml,options:0).write(to:readinessFolder.appendingPathComponent("daemons/com.push.autoupdate.plist"))
try JSONEncoder().encode(ObservedHealth(module:"macos",source:"manual",startedAt:readinessNow,updatedAt:readinessNow,finishedAt:readinessNow,phase:"completed",reason:"Manual fixture")).write(to:readinessFolder.appendingPathComponent("health/macos-manual.json"))
snap=reader.load()
check(snap.mainMonitor.title == "Loaded · not yet verified","manual result never counts as scheduled heartbeat")
snap.runningOS="27.2";snap.os=nil
check(snap.modules[0].status == "At the saved target","macOS semantic version comparison handles minor compliance")
try Data("invalid json".utf8).write(to:readinessFolder.appendingPathComponent("state.json"));snap=reader.load()
check(snap.modules[0].status == "State needs attention","corrupt saved state does not imply a pending actionable prompt")
try Data("auto: {enabled: true}".utf8).write(to:readinessFolder.appendingPathComponent("config.yaml"));snap=reader.load()
check(snap.configIssue != nil && snap.policy == nil,"unsupported policy format never becomes a default live policy")
try Data("update:\n  targetVersion: \"27.2\"\n".utf8).write(to:readinessFolder.appendingPathComponent("config.yaml"));snap=reader.load()
check(snap.policy?.macEnabled == DashboardConfig().auto.enabled && snap.policy?.dryRun == DashboardConfig().debug.dryRun,"omitted values match engine defaults rather than companion draft defaults")
check(!snap.summaryText.contains("fixture only; never executed"),"dashboard does not read executable contents into summary")

heartbeat.updatedAt=readinessNow.addingTimeInterval(500)
check(readinessMonitor(loadedService,true,nil,heartbeat).title == "Check time needs attention", "future heartbeat does not falsely prove freshness")
var noHistory=reader.load();noHistory.os=nil;noHistory.osIssue=nil;noHistory.runningOS="27.0";noHistory.policy?.target="27.2"
check(noHistory.modules[0].status == "Not checked", "missing macOS history does not become a due-toast claim")
check(noHistory.modules[0].facts.first{$0.label == "Toast eligible"}?.value == "Not recorded", "absent toast date is not invented")

print("Passed \(checks) offline checks. No app, Mist query, Keychain operation, admin action, upgrade, or restart was executed.")
