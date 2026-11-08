// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit
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

// Guided setup policy tests: no UI, system query, Keychain or live action.
var setupDraft=ConfigDocument.fresh
check(setupDraft.setupIssues.isEmpty,"fresh setup draft passes wizard validation")
check(setupDraft.setupFlag("debug.dryRun") && setupDraft.setupStrategy == .disabled,"wizard preserves safe starting mode")
check(!setupDraft.setupFlag("apps.enabled") && !setupDraft.setupFlag("entra.enabled"),"wizard never enables optional modules just by reviewing them")
check(SetupWizardProgress(step:999).currentStep == .start,"unknown saved wizard step safely returns to start")
check(SetupWizardProgress(step:-1).currentStep == .start,"negative saved wizard step cannot index navigation")
setupDraft.edits["update.deadline"]="2026-12-01T18:00:00Z"
setupDraft.edits["update.autoInstallAfterDeadline"]="true"
setupDraft.edits["auth.localAccount"]="managed-example"
setupDraft.edits["ui.orgName"]="Example Organization"
setupDraft.edits["schedule.alertStartHour"]="9"
setupDraft.edits["update.targetVersion"]="27.2"
setupDraft.chooseSetupStrategy(.minor)
check(setupDraft.setupStrategy == .minor && setupDraft.setupValue("update.targetVersion").isEmpty,"minor tracking deliberately clears fixed target")
check(setupDraft.setupValue("update.deadline") == "2026-12-01T18:00:00Z","setup preset preserves YAML deadline override")
check(setupDraft.setupFlag("update.autoInstallAfterDeadline") && setupDraft.setupFlag("debug.dryRun"),"setup preset retains installation and dry-run choices")
check(setupDraft.setupValue("ui.orgName") == "Example Organization" && setupDraft.setupValue("auth.localAccount") == "managed-example" && setupDraft.setupValue("schedule.alertStartHour") == "9","setup preset preserves branding authorization reference and hours")
setupDraft.chooseSetupStrategy(.major)
check(setupDraft.setupStrategy == .major && !setupDraft.setupFlag("auto.minorOnly"),"major tracking remains an explicit draft choice")
setupDraft.chooseSetupStrategy(.fixed)
check(!setupDraft.setupIssues(for:.macOS).isEmpty,"fixed-target wizard choice requires a numeric target")
setupDraft.edits["update.targetVersion"]="27.2"
check(setupDraft.setupIssues(for:.macOS).isEmpty,"fixed target validates when configured")
setupDraft.chooseSetupStrategy(.disabled)
check(setupDraft.setupValue("update.targetVersion") == "27.2" && setupDraft.setupFlag("update.autoInstallAfterDeadline"),"disabling checks preserves target and enforcement choices")
var badSetup=ConfigDocument.fresh
badSetup.edits["debug.dryRun"]="maybe"
check(!badSetup.setupIssues.isEmpty,"wizard rejects malformed boolean values rather than treating them as false")
badSetup = .fresh;badSetup.edits["schedule.alertStartHour"]="18";badSetup.edits["schedule.alertEndHour"]="8"
check(!badSetup.setupIssues(for:.macOS).isEmpty,"wizard blocks reversed working hours")
badSetup = .fresh;badSetup.edits["update.deadline"]="next Tuesday"
check(!badSetup.setupIssues(for:.macOS).isEmpty,"wizard rejects non-ISO deadline override")
badSetup = .fresh;badSetup.edits["apps.enabled"]="true"
check(!badSetup.setupIssues(for:.apps).isEmpty,"enabled app policy requires explicit approval")
badSetup.approveApp("chrome",enabled:true)
check(badSetup.setupIssues(for:.apps).isEmpty,"approved supported app policy validates")
badSetup.edits["apps.approved"]="unsupported"
check(!badSetup.setupIssues(for:.apps).isEmpty,"wizard rejects unsupported app approvals")
badSetup = .fresh;badSetup.edits["entra.policyID"]="0"
check(!badSetup.setupIssues(for:.registration).isEmpty,"registration policy must be a positive ID")
badSetup = .fresh;badSetup.edits["ui.helpURL"]="http://example.invalid"
check(!badSetup.setupIssues(for:.branding).isEmpty,"wizard validates support URL before continuing")
badSetup = .fresh;badSetup.edits["ui.accentColorHex"]="blue"
check(!badSetup.setupIssues(for:.branding).isEmpty,"wizard validates branding color")
var coverageDraft=ConfigDocument.fresh
let originalFingerprint=coverageDraft.setupFingerprint
check(originalFingerprint == coverageDraft.setupFingerprint,"draft fingerprint is deterministic")
var setupProgress=SetupWizardProgress()
let toastInstall=SetupPreviewRequirement(state:"toast",code:0,title:"Install")
setupProgress.record(document:coverageDraft,state:"toast",code:0,automatic:true,now:readinessNow)
check(!toastInstall.exercised(document:coverageDraft,progress:setupProgress),"automatic events never count as exercised button choices")
setupProgress.record(document:coverageDraft,state:"toast",code:0,automatic:false,now:readinessNow)
check(toastInstall.exercised(document:coverageDraft,progress:setupProgress),"explicit simulated button choice counts for exact draft")
let scheduleChoice=SetupPreviewRequirement(state:"softNudge",code:3,title:"Schedule")
setupProgress.record(document:coverageDraft,state:"softNudge",code:nil,automatic:false)
check(!scheduleChoice.exercised(document:coverageDraft,progress:setupProgress),"opening scheduler does not certify schedule confirmation")
setupProgress.record(document:coverageDraft,state:"softNudge",code:3,automatic:false)
check(scheduleChoice.exercised(document:coverageDraft,progress:setupProgress),"confirming simulated reminder schedule counts distinctly")
setupProgress.markReviewed(coverageDraft,now:readinessNow)
check(setupProgress.reviewed(coverageDraft),"review attestation is scoped to exact valid draft")
coverageDraft.edits["ui.orgName"]="Changed Branding"
check(coverageDraft.setupFingerprint != originalFingerprint && !setupProgress.reviewed(coverageDraft),"changing draft invalidates its previous review attestation")
check(!toastInstall.exercised(document:coverageDraft,progress:setupProgress),"old button checks cannot certify changed draft")
let brandingFingerprint=coverageDraft.setupFingerprint
coverageDraft.logoImageData=Data([1,2,3])
check(coverageDraft.setupFingerprint != brandingFingerprint,"attached logo bytes participate in preview identity")
let historyData=try JSONEncoder().encode(setupProgress)
let historyText=String(data:historyData,encoding:.utf8)!
check(!historyText.contains("Changed Branding") && !historyText.contains("update:") && !historyText.contains("Example Organization"),"wizard progress stores hashes and choices rather than draft content")
let restoredSetup=try JSONDecoder().decode(SetupWizardProgress.self,from:historyData)
check(restoredSetup.previewEvents.count == setupProgress.previewEvents.count,"wizard progress round-trips independently of installed state")
let eventCount=setupProgress.previewEvents.count
setupProgress.record(document:coverageDraft,state:"unknown-state",code:0,automatic:false)
setupProgress.record(document:coverageDraft,state:"toast",code:99,automatic:false)
check(setupProgress.previewEvents.count == eventCount,"invalid state and failure codes cannot enter successful-choice history")
for _ in 0..<110 {setupProgress.record(document:coverageDraft,state:"toast",code:1,automatic:false)}
check(setupProgress.previewEvents.count == 100,"saved preview history remains bounded")
var hiddenButtons=ConfigDocument.fresh
hiddenButtons.edits["toast.showDeferButton"]="false";hiddenButtons.edits["toast.showCloseButton"]="false";hiddenButtons.edits["update.maxDeferrals"]="0"
check(!hiddenButtons.setupPreviewRequirements.contains{$0.code == 1 || $0.code == 2 || $0.code == 3},"preview checklist does not require hidden deferral or close buttons")
hiddenButtons.edits["apps.enabled"]="true";hiddenButtons.approveApp("chrome",enabled:true);hiddenButtons.edits["entra.enabled"]="true"
check(hiddenButtons.setupPreviewRequirements.contains{$0.state == "appUpdates"} && hiddenButtons.setupPreviewRequirements.contains{$0.state == "entraRegistration"},"enabled optional modules add relevant preview choices")
let missingSetupFindings=ConfigDocument.fresh.setupFindings(snapshot:nil,providerPresent:nil,now:readinessNow)
check(missingSetupFindings.contains{$0.id == "authorization" && $0.title.contains("not verified")},"wizard never certifies unattended authorization without evidence")
check(missingSetupFindings.contains{$0.id == "engine" && $0.title.contains("not loaded")},"no snapshot is not presented as installed readiness")
var riskyDraft=ConfigDocument.fresh
riskyDraft.edits["debug.dryRun"]="false";riskyDraft.edits["update.autoInstallAfterDeadline"]="true";riskyDraft.edits["update.deadline"]="2020-01-01T00:00:00Z"
riskyDraft.edits["apps.enabled"]="true";riskyDraft.approveApp("chrome",enabled:true);riskyDraft.edits["apps.autoUpdateClosed"]="true";riskyDraft.edits["entra.enabled"]="true";riskyDraft.edits["uptime.enabled"]="true"
var setupSnapshot=snap;setupSnapshot.entra=userFixture
let riskyFindings=riskyDraft.setupFindings(snapshot:setupSnapshot,providerPresent:false,now:readinessNow)
check(riskyFindings.contains{$0.id == "mode" && $0.level == .attention},"final review highlights live-policy implications")
check(riskyFindings.contains{$0.id == "deadline"} && riskyFindings.contains{$0.id == "automatic"},"expired override and automatic installation remain visible in final review")
check(riskyFindings.contains{$0.id == "closed"} && riskyFindings.contains{$0.id == "provider" && $0.level == .attention},"automatic app policy does not hide a missing provider")
check(riskyFindings.contains{$0.id == "enrollment"} && riskyFindings.contains{$0.id == "restart"},"saved unenrolled evidence and preserved restart policy are highlighted")
let presentProvider=riskyDraft.setupFindings(snapshot:nil,providerPresent:true)
check(presentProvider.first{$0.id == "provider"}?.title.contains("trust not verified") == true,"provider-file presence never claims trusted installation readiness")
var invalidAttestation=SetupWizardProgress();invalidAttestation.markReviewed(badSetup)
check(!invalidAttestation.reviewed(badSetup),"invalid draft cannot be marked reviewed")

riskyDraft.edits["ui.hardBlockFullscreen"]="true";riskyDraft.edits["update.forceRestartAfterInstall"]="true"
let escalationFindings=riskyDraft.setupFindings(snapshot:nil,providerPresent:nil)
check(escalationFindings.contains{$0.id == "fullscreen"} && escalationFindings.contains{$0.id == "installRestart"}, "review exposes preserved full-screen and post-install restart choices")
var changedMode=ConfigDocument.fresh
var modeProgress=SetupWizardProgress();modeProgress.record(document:changedMode,state:"toast",code:0,automatic:false)
changedMode.edits["debug.dryRun"]="false"
check(!toastInstall.exercised(document:changedMode,progress:modeProgress), "switching from rehearsal to live draft requires new preview evidence")

let roundClockDraft=ConfigDocument.fresh
let roundClockEngine=CLIConfig.parse(yaml:roundClockDraft.yaml)
check(!roundClockEngine.schedule.respectAlertWindow && roundClockEngine.update.prepareAtDeadlineWhenLoggedOut,"fresh wizard writes explicit 24/7 and logged-out preparation policies")
check(roundClockEngine.debug.dryRun && !roundClockEngine.auto.enabled,"24/7 defaults do not activate monitoring or bypass dry-run setup")
let unrestricted=DashboardHours(start:8,end:18,weekdays:true,restricted:false)
let weekendEligibility=ISO8601DateFormatter().date(from:"2026-11-07T23:00:00Z")!
check(unrestricted.nextAllowed(weekendEligibility,calendar:utc)==weekendEligibility,"readiness honors disabled hours on weekends and evenings")
var restrictedDraft=roundClockDraft;restrictedDraft.edits["schedule.respectAlertWindow"]="true"
check(CLIConfig.parse(yaml:restrictedDraft.yaml).schedule.respectAlertWindow,"admins can opt back into preserved working hours")
let preservedHours=CLIConfig.parse(yaml:restrictedDraft.yaml)
check(preservedHours.schedule.alertStartHour==8 && preservedHours.schedule.skipWeekends,"re-enabling the restriction retains stored hours and weekdays")
let summary24=InstalledPolicySummary(DashboardConfig.parse(yaml:roundClockDraft.yaml))
check(!summary24.macHours.restricted && summary24.entraHours.restricted,"macOS/app hours toggle does not change independent registration hours")
let informationalContext=UIContext(config:UIConfig(),state:.toast)
informationalContext.informationalToastMessage="Informational test; no update running"
informationalContext.exit(.dismiss)
check(informationalContext.demoAction.contains("Dismissed"),"informational toast dismiss remains a simulated non-install action")
let preparationFixture=try JSONSerialization.data(withJSONObject:["target":"27.2","phase":"downloaded","reason":"Download only; no installation requested","checkedAt":readinessNow.timeIntervalSinceReferenceDate])
try preparationFixture.write(to:readinessFolder.appendingPathComponent("preparation.json"))
let preparationSnapshot=reader.load()
check(preparationSnapshot.preparation?.phase == "downloaded", "passive readiness reads saved preparation without running a download")

// Staged wallpaper and notification-history fixtures. No desktop APIs or engine commands.
let wallpaperFresh=ConfigDocument.fresh
check(!wallpaperFresh.setupFlag("compliance.wallpaperEnabled"),"new admin drafts leave visual enforcement opt-in")
let wallpaperEngine=CLIConfig.parse(yaml:wallpaperFresh.yaml)
check(!wallpaperEngine.compliance.wallpaperEnabled && wallpaperEngine.compliance.nonCompliantWallpaper==WallpaperPolicy.defaultImage,"wallpaper config round-trips through the real engine parser")
var enabledWallpaper=wallpaperFresh;enabledWallpaper.edits["compliance.wallpaperEnabled"]="true"
check(!enabledWallpaper.problems.isEmpty,"wallpaper enablement requires an automatic macOS policy")
enabledWallpaper.followReleases(allowMajorUpgrades:false)
check(enabledWallpaper.problems.isEmpty,"wallpaper works with a valid setup-once tracking policy")
enabledWallpaper.edits["compliance.nonCompliantWallpaper"]="/Users/example/private.jpg"
check(!enabledWallpaper.problems.isEmpty,"deployed wallpaper references stay in managed working storage")
let fixturePNG=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
let wallpaperPNG=try WallpaperAssetImage.normalizedPNG(fixturePNG)
check(NSImage(data:wallpaperPNG) != nil,"wallpaper upload normalizes a supported image into PNG")
let wallpaperDigest=WallpaperAssetImage.digest(wallpaperPNG)
let wallpaperRef=WallpaperAssetReference(role:"noncompliant",digest:wallpaperDigest,originalName:"private-original-name.png")
check(wallpaperRef.valid && wallpaperRef.deployedPath.hasPrefix(WallpaperPolicy.managedDirectory+"/noncompliant-"),"normalized wallpaper gets a managed content-addressed deployment path")
let stagedWallpaperFolder=FileManager.default.temporaryDirectory.appendingPathComponent("push-wallpaper-fixture-"+UUID().uuidString)
try FileManager.default.createDirectory(at:stagedWallpaperFolder,withIntermediateDirectories:false)
defer{try? FileManager.default.removeItem(at:stagedWallpaperFolder)}
try wallpaperPNG.write(to:stagedWallpaperFolder.appendingPathComponent(wallpaperRef.fileName))
let verifiedWallpaperBytes=try WallpaperAssetImage.read(wallpaperRef,folder:stagedWallpaperFolder)
check(verifiedWallpaperBytes==wallpaperPNG,"staged image bytes are verified against the recorded digest")
try Data("changed".utf8).write(to:stagedWallpaperFolder.appendingPathComponent(wallpaperRef.fileName))
var changedAssetRejected=false
do {_ = try WallpaperAssetImage.read(wallpaperRef,folder:stagedWallpaperFolder)}catch{changedAssetRejected=true}
check(changedAssetRejected,"changed staged image is rejected rather than silently deployed")
let invalidRef=WallpaperAssetReference(role:"../",digest:wallpaperDigest,originalName:"example")
check(!invalidRef.valid,"asset references reject role traversal")
var attachedWallpaper=wallpaperFresh;attachedWallpaper.wallpaperAssets=["noncompliant":wallpaperRef];attachedWallpaper.edits["compliance.nonCompliantWallpaper"]=wallpaperRef.deployedPath
let attachmentWire=try JSONEncoder().encode(attachedWallpaper)
check(!String(data:attachmentWire,encoding:.utf8)!.contains(wallpaperPNG.base64EncodedString()),"draft keeps wallpaper references instead of embedding large image data")
let attachmentRoundTrip=try JSONDecoder().decode(ConfigDocument.self,from:attachmentWire)
check(attachmentRoundTrip.wallpaperAssets?["noncompliant"]?.digest==wallpaperDigest,"draft resumes staged wallpaper references")
let priorWallpaperHash=attachedWallpaper.setupFingerprint
attachedWallpaper.edits["compliance.nonCompliantWallpaper"]=WallpaperPolicy.defaultImage
check(attachedWallpaper.setupFingerprint != priorWallpaperHash,"changing deployed wallpaper invalidates the old draft review fingerprint")
let historyTime=readinessNow
var requestedEvent=NotificationHistoryEvent(attempt:"attempt-a",date:historyTime,state:"toast",mode:"scheduled",outcome:"requested",reason:"Requested",code:nil,userUID:501,target:"27.2",retryAt:nil)
var displayedEvent=requestedEvent;displayedEvent.id=UUID().uuidString;displayedEvent.date=historyTime.addingTimeInterval(1);displayedEvent.outcome="displayed"
var laterEvent=displayedEvent;laterEvent.id=UUID().uuidString;laterEvent.date=historyTime.addingTimeInterval(2);laterEvent.outcome="response";laterEvent.code=1;laterEvent.reason="Later selected"
let groupedHistory=NotificationTimelineEntry.group([requestedEvent,displayedEvent,laterEvent])
check(groupedHistory.count==1 && groupedHistory[0].displayed && groupedHistory[0].status=="User response","timeline correlates request, visibility and response without confusing them")
check(NotificationTimelineEntry.group([requestedEvent])[0].status=="Delivery unconfirmed" && !NotificationTimelineEntry.group([requestedEvent])[0].displayed,"a nonblocking request does not become confirmed delivery")
let historyFixturePath=stagedWallpaperFolder.appendingPathComponent("history.json")
try JSONEncoder().encode(NotificationHistoryDocument(events:[requestedEvent,displayedEvent,laterEvent])).write(to:historyFixturePath)
let loadedHistoryFixture=try NotificationHistoryReader.read(historyFixturePath.path)
check(loadedHistoryFixture.events.count==3,"history refresh reads saved fixture events only")
try Data("broken".utf8).write(to:historyFixturePath)
var badHistoryRejected=false
do {_ = try NotificationHistoryReader.read(historyFixturePath.path)}catch{badHistoryRejected=true}
check(badHistoryRejected,"corrupt saved history stays an error instead of fabricated delivery evidence")
let emptyHistoryFixture=try NotificationHistoryReader.read(stagedWallpaperFolder.appendingPathComponent("missing.json").path)
check(emptyHistoryFixture.events.isEmpty,"missing history is empty rather than a health success")
let timelineWallpaper=NotificationHistoryEvent(attempt:"wallpaper",date:historyTime,state:"wallpaper",mode:"scheduled",outcome:"applied",reason:"Managed image reapplied",code:nil,userUID:501,target:"27.2",retryAt:nil)
check(NotificationTimelineEntry.group([timelineWallpaper])[0].status=="Wallpaper changed" && !NotificationTimelineEntry.group([timelineWallpaper])[0].displayed,"wallpaper application is not mislabeled as notification delivery")
var oldDraftObject=try JSONSerialization.jsonObject(with:attachmentWire) as! [String:Any]
oldDraftObject.removeValue(forKey:"wallpaperAssets")
let oldDraftDecoded=try JSONDecoder().decode(ConfigDocument.self,from:JSONSerialization.data(withJSONObject:oldDraftObject))
check(oldDraftDecoded.wallpaperAssets == nil,"older saved drafts decode without wallpaper attachments")

let recoveryPolicy=CLIConfig.parse(yaml:"update:\n  deadlineRecoveryEnabled: true\n  retryCountdownMinutes: 12\n  retryBackoffMinutes: 45\n  maxAutomaticRetriesPerDay: 2\nui:\n  menuBarEnabled: false\n")
check(recoveryPolicy.update.retryCountdownMinutes==12 && recoveryPolicy.update.retryBackoffMinutes==45,"recovery countdown and backoff parse from YAML")
check(recoveryPolicy.update.maxAutomaticRetriesPerDay==2 && !recoveryPolicy.ui.menuBarEnabled,"retry budget and menu preference parse from YAML")
check(RecoveryFailureKind.authorization.allowsAutomaticRetry == false,"IT authorization blockers cannot receive an automatic retry bypass")
check(RecoveryFailureKind.network.allowsAutomaticRetry,"temporary network failure can be retried after checks")
let adminRecovery=RecoveryNotice.preview()
check(adminRecovery.automatic && adminRecovery.remaining(at:Date())>0,"recovery preview contains a future countdown")
check(!adminRecovery.countdownDue(at:Date()),"preview does not expire early")
check(previewButtonTitle(state:"updateRecovery",code:7)=="Automatic recovery retry due","automatic expiry is not reported as user consent")
check(!UserUpdateRequest.allowed(policyAvailable:true,enabled:true,dryRun:true,requestsEnabled:true,pending:false,monitor:true,target:"27.2",running:"27.0"),"menu requests stay disabled under dry-run policy")

let generatedProfiles=try DeploymentProfiles.files(teamID:"")
check(generatedProfiles.count==2,"export contains notification and background profiles only")
let notifyProfile=try PropertyListSerialization.propertyList(from:generatedProfiles["JamfCheckIn-Notifications.mobileconfig"]!,format:nil) as! [String:Any]
let notifyPayload=(notifyProfile["PayloadContent"] as! [[String:Any]])[0]
let notifySettings=(notifyPayload["NotificationSettings"] as! [[String:Any]])[0]
check(notifyPayload["PayloadType"] as? String == "com.apple.notificationsettings","notification profile uses the Apple payload type")
check(notifySettings["BundleIdentifier"] as? String == DeploymentProfiles.jamfID,"notification profile matches the existing JamfCheckIn identity")
check(notifySettings["ShowInLockScreen"] as? Bool == false,"export avoids exposing notification content on the lock screen")
let teamProfiles=try DeploymentProfiles.files(teamID:"A1B2C3D4E5")
let managedProfile=try PropertyListSerialization.propertyList(from:teamProfiles["PUSH-Background-Items.mobileconfig"]!,format:nil) as! [String:Any]
let managedPayload=(managedProfile["PayloadContent"] as! [[String:Any]])[0]
let managedRules=managedPayload["Rules"] as! [[String:Any]]
check(managedPayload["PayloadType"] as? String == "com.apple.servicemanagement","background approval uses Apple's Service Management payload")
check(managedRules.count==4 && managedRules.allSatisfy{$0["TeamIdentifier"] as? String == "A1B2C3D4E5"},"production Team ID constrains every exact background rule")
check(!managedRules.contains{($0["RuleType"] as? String)?.contains("Prefix")==true || $0["RuleType"] as? String == "TeamIdentifier"},"no broad prefix or team-wide approval is generated")
check(!managedRules.contains{$0["RuleValue"] as? String == "com.push.status"},"retired standalone menu gets no managed approval")
var malformedTeam=false
do {_ = try DeploymentProfiles.files(teamID:"bad team")}catch{malformedTeam=true}
check(malformedTeam,"malformed Team IDs are rejected rather than placed in a profile")
check(DeploymentBundle.allowedAsset("assets/popup-logo.png") && DeploymentBundle.allowedAsset("assets/wallpapers/noncompliant-ab12.png"),"deployment allows only managed PNG assets")
check(!DeploymentBundle.allowedAsset("../config.yaml") && !DeploymentBundle.allowedAsset("assets/wallpapers/../../evil.png") && !DeploymentBundle.allowedAsset("/Library/evil.png"),"asset paths cannot escape the staged managed directory")
let exportFixture=FileManager.default.temporaryDirectory.appendingPathComponent("push-bundle-test-"+UUID().uuidString)
try FileManager.default.createDirectory(at:exportFixture,withIntermediateDirectories:false)
defer {try? FileManager.default.removeItem(at:exportFixture)}
let fixtureClient=exportFixture.appendingPathComponent("fixture.pkg")
try Data("OFFLINE FIXTURE — NOT AN INSTALLER".utf8).write(to:fixtureClient)
let fixtureExport=exportFixture.appendingPathComponent("bundle")
try DeploymentBundle.write(.init(yaml:ConfigDocument.fresh.yaml,assets:["assets/popup-logo.png":Data("fixture image".utf8)],teamID:""),client:fixtureClient,to:fixtureExport)
check(FileManager.default.fileExists(atPath:fixtureExport.appendingPathComponent("PUSH-Client-1.11.0.pkg").path),"bundle includes the supplied client artifact")
check(FileManager.default.fileExists(atPath:fixtureExport.appendingPathComponent("PolicyPayload/Library/Management/PUSH/assets/popup-logo.png").path),"bundle stages images at their managed destinations")
let exportManifest=try JSONSerialization.jsonObject(with:Data(contentsOf:fixtureExport.appendingPathComponent("manifest.json"))) as! [String:Any]
check(exportManifest["adminIncludedOnClients"] as? Bool == false,"manifest explicitly excludes the admin app from clients")
check((exportManifest["signingReadiness"] as? String)?.contains("Local testing")==true,"export does not claim production signing without a verified release")
let manifestFiles=exportManifest["files"] as! [[String:String]]
check(manifestFiles.allSatisfy{entry in (try? Data(contentsOf:fixtureExport.appendingPathComponent(entry["path"]!))).map{DeploymentBundle.digest($0)==entry["sha256"]} == true},"every manifest hash matches the staged artifact")
var refusedOverwrite=false
do {try DeploymentBundle.write(.init(yaml:ConfigDocument.fresh.yaml,assets:[:],teamID:""),client:fixtureClient,to:fixtureExport)}catch{refusedOverwrite=true}
check(refusedOverwrite,"existing deployment bundles are never overwritten")
let unsafeExport=exportFixture.appendingPathComponent("unsafe")
var refusedUnsafeAsset=false
do {try DeploymentBundle.write(.init(yaml:ConfigDocument.fresh.yaml,assets:["../escape.png":Data()],teamID:""),client:fixtureClient,to:unsafeExport)}catch{refusedUnsafeAsset=true}
check(refusedUnsafeAsset && !FileManager.default.fileExists(atPath:unsafeExport.path),"invalid assets leave no published partial bundle")
check(DeploymentBundle.enableMonitor.contains("--enable-reviewed-policy") && DeploymentBundle.buildPolicy.contains("pkgbuild"),"activation is deliberate and separate from building policy")
check(!DeploymentBundle.buildPolicy.contains("install-daemon") && !DeploymentBundle.buildPolicy.contains("installer -pkg"),"building a policy package neither installs it nor starts a monitor")

let fixtureRestart=RestartProfileIdentity(teamID:"A1B2C3D4E5",requirement:"identifier \"push-cli\" and anchor apple generic",sha256:String(repeating:"a",count:64))
let restartProfiles=try DeploymentProfiles.files(teamID:"A1B2C3D4E5",restartIdentity:fixtureRestart)
check(restartProfiles.count==3,"restart approval is conditional on a supplied signing identity")
let restartProfile=try PropertyListSerialization.propertyList(from:restartProfiles["PUSH-Gentle-Restart-PPPC.mobileconfig"]!,format:nil) as! [String:Any]
let restartPayload=(restartProfile["PayloadContent"] as! [[String:Any]])[0]
let restartServices=restartPayload["Services"] as! [String:Any]
check(Set(restartServices.keys)==["AppleEvents"],"restart profile does not grant Full Disk Access or unrelated privacy services")
let restartEntry=(restartServices["AppleEvents"] as! [[String:Any]])[0]
check(restartEntry["Identifier"] as? String == "/Library/Management/PUSH/push-cli" && restartEntry["IdentifierType"] as? String == "path","restart sender is bound to the managed executable path")
check(restartEntry["AEReceiverIdentifier"] as? String == "com.apple.systemevents" && restartEntry["AEReceiverCodeRequirement"] as? String == "identifier \"com.apple.systemevents\" and anchor apple","restart automation is limited to Apple's signed System Events")
check(restartEntry["Allowed"] as? Bool == true && restartEntry["Authorization"] == nil,"PPPC uses one supported authorization representation")
var mismatchedSigningRejected=false
do {_ = try DeploymentProfiles.files(teamID:"Z1B2C3D4E5",restartIdentity:fixtureRestart)}catch{mismatchedSigningRejected=true}
check(mismatchedSigningRejected,"signing-team mismatches cannot generate a misleading approval")
check(!RestartProfileIdentity(teamID:"A1B2C3D4E5",requirement:"cdhash abc",sha256:String(repeating:"a",count:64)).valid(for:"A1B2C3D4E5"),"unstable hash-only requirements are rejected")

var advisorDraft=ConfigDocument.fresh
let advisorNow=Date(timeIntervalSince1970:2_000_000_000)
let basicAdvice=SetupAdvisor.evaluate(advisorDraft,catalogDate:nil,catalogCached:false,providerPresent:nil,mistPresent:nil,now:advisorNow)
check(basicAdvice.contains{$0.id=="discovery" && !$0.changes.isEmpty},"disabled discovery gets an actionable setup suggestion")
check(basicAdvice.contains{$0.id=="support"} && basicAdvice.contains{$0.id=="catalog"},"missing support contact and release evidence get concrete suggestions")
check(SetupAdvisor.smartDefaults["debug.dryRun"]==nil && SetupAdvisor.smartDefaults["update.autoInstallAfterDeadline"]==nil && SetupAdvisor.smartDefaults["update.deadline"]==nil,"recommended defaults never silently activate installs or erase deadline overrides")
for (key,value) in SetupAdvisor.smartDefaults {advisorDraft.edits[key]=value}
check(advisorDraft.setupFlag("auto.trackLatest") && advisorDraft.setupFlag("auto.minorOnly") && advisorDraft.setupFlag("debug.dryRun"),"smart defaults follow stable minor releases while preserving dry-run")
advisorDraft.edits["update.deadline"]="2026-01-01T00:00:00Z"
advisorDraft.edits["update.toastIntervalSeconds"]="7200"
advisorDraft.edits["schedule.respectAlertWindow"]="true"
let restrictedAdvice=SetupAdvisor.evaluate(advisorDraft,catalogDate:advisorNow,catalogCached:false,providerPresent:true,mistPresent:true,now:advisorNow)
check(restrictedAdvice.contains{$0.id=="deadline" && $0.changes["update.deadline"]==""},"expired deadline receives an explicit clear-override choice")
check(advisorDraft.setupValue("update.deadline")=="2026-01-01T00:00:00Z","evaluating suggestions does not mutate the draft")
check(restrictedAdvice.contains{$0.id=="hourly"} && restrictedAdvice.contains{$0.id=="hours"},"nonhourly and restricted reminders explain missing toasts")
check(!restrictedAdvice.contains{$0.id=="catalog"},"fresh catalog evidence is not falsely labeled stale")
var rejectedDryActivation=false
do {try ConfiguredClientBuilder.validate(.fresh,activation:.monitor)}catch{rejectedDryActivation=true}
check(rejectedDryActivation,"live package activation rejects dry-run policies")
try ConfiguredClientBuilder.validate(.fresh,activation:.paused)
check(true,"safe fresh policy can be packaged with monitoring paused")
var noPolicy=ConfigDocument.fresh;noPolicy.edits["debug.dryRun"]="false"
var rejectedEmptyActivation=false
do {try ConfiguredClientBuilder.validate(noPolicy,activation:.monitor)}catch{rejectedEmptyActivation=true}
check(rejectedEmptyActivation,"activation requires an enabled managed workflow")
var liveDraft=ConfigDocument.fresh
for (key,value) in SetupAdvisor.smartDefaults {liveDraft.edits[key]=value}
liveDraft.edits["debug.dryRun"]="false"
try ConfiguredClientBuilder.validate(liveDraft,activation:.monitor)
check(true,"reviewed live discovery policy permits explicit monitoring activation")
let pausedInstallScript=ConfiguredClientBuilder.postinstall(activation:.paused,main:true,entra:false,yamlHash:String(repeating:"a",count:64))
check(!pausedInstallScript.contains("install-daemon") && !pausedInstallScript.contains("launchctl"),"paused configured installer has no activation commands")
let activeInstallScript=ConfiguredClientBuilder.postinstall(activation:.monitor,main:true,entra:true,yamlHash:String(repeating:"b",count:64))
check(activeInstallScript.contains("shasum") && activeInstallScript.range(of:"shasum")!.lowerBound<activeInstallScript.range(of:"launchctl bootstrap")!.lowerBound,"reviewed YAML hash is checked before future service activation")
check(activeInstallScript.contains("launchctl print \"system/$label\""),"configured activation verifies loaded service rather than assuming CLI success")
let combinedPreflight=ConfiguredClientBuilder.preinstall(assetPaths:["assets/popup-logo.png"])
check(combinedPreflight.contains("engine-preinstall") && combinedPreflight.contains("jamf-preinstall") && combinedPreflight.contains("symbolic link"),"configured package retains both backup preflights and protects policy/image paths")
check(SetupAdvisor.evaluate(liveDraft,catalogDate:advisorNow,catalogCached:true,providerPresent:nil,mistPresent:false,now:advisorNow).contains{$0.id=="catalog"},"cached catalog data is identified even when its timestamp is recent")

if let clientPath=ProcessInfo.processInfo.environment["PUSH_TEST_CLIENT"],let folder=ProcessInfo.processInfo.environment["PUSH_TEST_BUILD_FOLDER"] {
    let client=URL(fileURLWithPath:clientPath),output=URL(fileURLWithPath:folder)
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:false)
    var pilot=ConfigDocument.fresh
    pilot.edits["ui.logoPath"]=deployedPopupLogoPath
    let image=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
    let paused=output.appendingPathComponent("paused")
    try ConfiguredClientBuilder.build(.init(yaml:pilot.yaml,assets:["assets/popup-logo.png":image],teamID:""),client:client,activation:.paused,to:paused)
    check(FileManager.default.fileExists(atPath:paused.appendingPathComponent("PUSH-Configured-Client.pkg").path),"real embedded client builds into one paused configured installer")
    let active=output.appendingPathComponent("active")
    try ConfiguredClientBuilder.build(.init(yaml:liveDraft.yaml,assets:[:],teamID:""),client:client,activation:.monitor,to:active)
    let activeManifest=try JSONSerialization.jsonObject(with:Data(contentsOf:active.appendingPathComponent("manifest.json"))) as! [String:Any]
    check(activeManifest["activation"] as? String == "monitor" && activeManifest["adminIncludedOnClients"] as? Bool == false,"real active-package build records explicit activation and excludes Admin")
    var blockedRestart=liveDraft;blockedRestart.edits["uptime.enabled"]="true"
    var refusedUnmatchedRestart=false
    do {try ConfiguredClientBuilder.build(.init(yaml:blockedRestart.yaml,assets:[:],teamID:"A1B2C3D4E5",restartIdentity:fixtureRestart),client:client,activation:.monitor,to:output.appendingPathComponent("blocked-restart"))}catch{refusedUnmatchedRestart=true}
    check(refusedUnmatchedRestart && !FileManager.default.fileExists(atPath:output.appendingPathComponent("blocked-restart").path),"ad-hoc embedded client cannot be published with a misleading production restart approval")
    var rejectedInstallerCommand=false
    do {try ConfiguredClientBuilder.command("/usr/sbin/installer",[],folder:output)}catch{rejectedInstallerCommand=true}
    check(rejectedInstallerCommand,"builder command boundary rejects running an installer")
}

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

if let clientPath=ProcessInfo.processInfo.environment["PUSH_TEST_CLIENT"],let folder=ProcessInfo.processInfo.environment["PUSH_TEST_BUILD_FOLDER"] {
    let output=URL(fileURLWithPath:folder).appendingPathComponent("major-only")
    let input=DeploymentBundleInput(yaml:ClientPackageScope.majorPolicy.yaml,assets:[:],teamID:"",majorSettings:MajorOfferSettings(),hardwareCatalog:currentList)
    try ConfiguredClientBuilder.build(input,client:URL(fileURLWithPath:clientPath),activation:.paused,scope:.majorOfferOnly,to:output)
    check(FileManager.default.fileExists(atPath:output.appendingPathComponent("PUSH-Major-Offer-Only.pkg").path),"major-only profile builds its dedicated installer")
    let majorManifest=try JSONSerialization.jsonObject(with:Data(contentsOf:output.appendingPathComponent("manifest.json"))) as! [String:Any]
    check(majorManifest["scope"] as? String == "majorOfferOnly" && majorManifest["majorOfferIsSimulationOnly"] as? Bool == true,"major-only manifest reports its scope and preview limitation")
    check(!FileManager.default.fileExists(atPath:output.appendingPathComponent("Profiles").path),"major-only profile excludes unrelated Jamf/background permission profiles")
    let preference=try JSONDecoder().decode(MajorOfferSettings.self,from:Data(contentsOf:output.appendingPathComponent("PolicyPayload/Library/Management/PUSH/major-offer.json")))
    check(preference.presentation.greetingTemplate=="Hello {fullName}","major-only installer includes the runtime-resolved greeting template")
    check(!ClientPackageScope.majorPolicy.setupFlag("auto.enabled") && ClientPackageScope.majorPolicy.setupFlag("debug.dryRun") && !ClientPackageScope.majorPolicy.setupFlag("update.allowUserUpdateRequests"),"major-only policy disables enforcement and live update requests")
}

if let clientPath=ProcessInfo.processInfo.environment["PUSH_READY_CLIENT"],let catalogPath=ProcessInfo.processInfo.environment["PUSH_READY_CATALOG"],let folder=ProcessInfo.processInfo.environment["PUSH_READY_FOLDER"] {
    let catalog=try JSONDecoder().decode(AppleHardwareCatalog.self,from:Data(contentsOf:URL(fileURLWithPath:catalogPath)))
    let input=DeploymentBundleInput(yaml:ClientPackageScope.majorPolicy.yaml,assets:[:],teamID:"",majorSettings:MajorOfferSettings(),hardwareCatalog:catalog)
    try ConfiguredClientBuilder.build(input,client:URL(fileURLWithPath:clientPath),activation:.paused,scope:.majorOfferOnly,to:URL(fileURLWithPath:folder))
    check(catalog.source=="https://gdmf.apple.com/v2/pmv" && !catalog.releases.isEmpty,"ready package uses the actual normalized Apple catalog")
}

print("Passed \(checks) offline checks. No app, Mist query, Keychain operation, admin action, upgrade, or restart was executed.")
