// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import CryptoKit

enum DeploymentBundleError:LocalizedError {
    case invalid(String)
    var errorDescription:String? {switch self {case .invalid(let text):return text}}
}
enum DeploymentProfiles {
    static let jamfID="com.sebastianitconsulting.jamfcheckin"
    static func payload(_ type:String,_ suffix:String,_ title:String,_ contents:[String:Any])->[String:Any] {
        var value=contents
        value.merge(["PayloadType":type,"PayloadVersion":1,"PayloadIdentifier":"com.push.deployment."+suffix,"PayloadUUID":UUID().uuidString,"PayloadDisplayName":title]){$1}
        return value
    }
    static func profile(_ suffix:String,_ title:String,_ content:[[String:Any]])throws->Data {
        let value:[String:Any]=["PayloadType":"Configuration","PayloadVersion":1,"PayloadIdentifier":"com.push.deployment."+suffix+".profile","PayloadUUID":UUID().uuidString,"PayloadDisplayName":title,"PayloadOrganization":"Sebastian Santos — PUSH","PayloadScope":"System","PayloadContent":content]
        return try PropertyListSerialization.data(fromPropertyList:value,format:.xml,options:0)
    }
    static func files(teamID:String,restartIdentity:RestartProfileIdentity?=nil)throws->[String:Data] {
        let team=teamID.trimmingCharacters(in:.whitespacesAndNewlines)
        guard team.isEmpty || (team.count==10 && team.utf8.allSatisfy{(48...57).contains($0)||(65...90).contains($0)}) else {throw DeploymentBundleError.invalid("Use a 10-character uppercase Apple Developer Team ID, or leave it blank for local testing.")}
        let notifications=payload("com.apple.notificationsettings","notifications","JamfCheckIn Notifications",["NotificationSettings":[["BundleIdentifier":jamfID,"NotificationsEnabled":true,"AlertType":1,"BadgesEnabled":true,"SoundsEnabled":true,"ShowInNotificationCenter":true,"ShowInLockScreen":false]]])
        // Exact identities only: no broad team/prefix rule. Team constraints are
        // optional for local fixtures and must match production signing at deployment.
        var rules:[[String:Any]]=[]
        for (type,value) in [("BundleIdentifier",jamfID),("Label",jamfID),("Label","com.push.autoupdate"),("Label","com.push.entra-registration")] {
            var rule:[String:Any]=["RuleType":type,"RuleValue":value,"Comment":"PUSH / JamfCheckIn — Sebastian Santos"]
            if !team.isEmpty {rule["TeamIdentifier"]=team}
            rules.append(rule)
        }
        let background=payload("com.apple.servicemanagement","background","PUSH and JamfCheckIn Background Items",["Rules":rules])
        var files=["JamfCheckIn-Notifications.mobileconfig":try profile("notifications","JamfCheckIn Notifications",[notifications]),"PUSH-Background-Items.mobileconfig":try profile("background","PUSH Background Items",[background])]
        if let identity=restartIdentity {
            guard identity.valid(for:team) else {throw DeploymentBundleError.invalid("The restart approval must match the verified signing team. Select the production-signed executable again.")}
            let entry:[String:Any]=["Identifier":"/Library/Management/PUSH/push-cli","IdentifierType":"path","CodeRequirement":identity.requirement,"Allowed":true,"AEReceiverIdentifier":"com.apple.systemevents","AEReceiverIdentifierType":"bundleID","AEReceiverCodeRequirement":"identifier \"com.apple.systemevents\" and anchor apple"]
            let approval=payload("com.apple.TCC.configuration-profile-policy","restart","PUSH Gentle Restart Automation",["Services":["AppleEvents":[entry]]])
            files["PUSH-Gentle-Restart-PPPC.mobileconfig"]=try profile("restart","PUSH Gentle Restart Automation",[approval])
        }
        return files
    }
}
struct DeploymentBundleInput {
    var yaml:String
    var assets:[String:Data] // fixed relative payload paths, never arbitrary filesystem writes
    var teamID:String
    var restartIdentity:RestartProfileIdentity?=nil
    var majorSettings:MajorOfferSettings?=nil
    var hardwareCatalog:AppleHardwareCatalog?=nil
}
enum DeploymentBundle {
    static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func relativePath(_ file:URL,to root:URL)throws->String {
        let prefix=root.standardizedFileURL.resolvingSymlinksInPath().path+"/"
        let path=file.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(prefix) else {throw DeploymentBundleError.invalid("An export file escaped its staging directory.")}
        return String(path.dropFirst(prefix.count))
    }
    static func allowedAsset(_ path:String)->Bool {
        let parts=path.split(separator:"/",omittingEmptySubsequences:false)
        guard !path.hasPrefix("/"),!parts.contains(".."),!parts.contains("."),!parts.contains(""),path.hasSuffix(".png") else{return false}
        return path=="assets/popup-logo.png" || (parts.count==3 && parts[0]=="assets" && parts[1]=="wallpapers" && parts[2].utf8.allSatisfy{(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||$0==45||$0==46})
    }
    static func write(_ input:DeploymentBundleInput,client:URL,to destination:URL)throws {
        let fm=FileManager.default
        guard !fm.fileExists(atPath:destination.path) else {throw DeploymentBundleError.invalid("Choose a new export folder. Existing deployment bundles are never replaced.")}
        guard client.pathExtension=="pkg",let values=try? client.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? 0)>0 else {throw DeploymentBundleError.invalid("The client installer is missing. Reinstall the matching PUSH Admin release.")}
        if let settings=input.majorSettings {_=try settings.validated()}
        let profiles=try DeploymentProfiles.files(teamID:input.teamID,restartIdentity:input.restartIdentity)
        guard input.assets.keys.allSatisfy(allowedAsset) else {throw DeploymentBundleError.invalid("An image destination is outside the managed asset folders.")}
        // Stage beside the destination, then rename only after every file is ready.
        let stage=destination.deletingLastPathComponent().appendingPathComponent(".push-export-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer{try? fm.removeItem(at:stage)}
        func put(_ path:String,_ data:Data,_ mode:Int=0o600)throws {
            let url=stage.appendingPathComponent(path);try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try data.write(to:url,options:.atomic);try fm.setAttributes([.posixPermissions:mode],ofItemAtPath:url.path)
        }
        try fm.copyItem(at:client,to:stage.appendingPathComponent("PUSH-Client-1.11.0.pkg"))
        try put("PolicyPayload/Library/Management/PUSH/config.yaml",Data(input.yaml.utf8))
        if let catalog=input.hardwareCatalog {try put("PolicyPayload/Library/Management/PUSH/assets/hardware/AppleHardwareCatalog.json",JSONEncoder().encode(catalog))}
        if let settings=input.majorSettings {try put("PolicyPayload/Library/Management/PUSH/major-offer.json",JSONEncoder().encode(settings))}
        for (path,data) in input.assets {try put("PolicyPayload/Library/Management/PUSH/"+path,data)}
        for (name,data) in profiles {try put("Profiles/"+name,data)}
        try put("Build-Policy-Package.command",Data(buildPolicy.utf8),0o700)
        try put("Enable-Monitor.sh",Data(enableMonitor.utf8),0o700)
        try put("READ-ME-FIRST.txt",Data(readme(teamID:input.teamID).utf8))
        var entries:[[String:String]]=[]
        for case let file as URL in fm.enumerator(at:stage,includingPropertiesForKeys:[.isRegularFileKey])! {
            if (try file.resourceValues(forKeys:[.isRegularFileKey])).isRegularFile==true {entries.append(["path":try relativePath(file,to:stage),"sha256":digest(try Data(contentsOf:file))])}
        }
        let manifest:[String:Any]=["formatVersion":1,"developer":"Sebastian Santos","engineVersion":"1.11.0","jamfCheckInVersion":"1.1.1","adminIncludedOnClients":false,"signingReadiness":input.teamID.isEmpty ? "Local testing only; no production Team ID supplied":"Verify Developer ID signatures and notarization before fleet rollout; Team ID is a profile constraint, not proof of signing","teamID":input.teamID,"restartProfileSourceSHA256":input.restartIdentity?.sha256 ?? "not included","files":entries.sorted{$0["path"]!<$1["path"]!}]
        try put("manifest.json",JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]))
        try fm.moveItem(at:stage,to:destination)
    }
    static let buildPolicy="""
    #!/bin/bash
    # Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
    # Builds a policy package only. Does not install or activate PUSH.
    set -euo pipefail
    cd "$(dirname "$0")"
    [[ ! -e PUSH-Policy.pkg ]] || { echo 'PUSH-Policy.pkg already exists; choose a fresh export.' >&2; exit 1; }
    stage="$(mktemp -d "${TMPDIR:-/tmp}/push-policy.XXXXXX")"
    trap 'rm -rf "$stage"' EXIT
    /usr/bin/ditto PolicyPayload "$stage/payload"
    /usr/bin/find "$stage/payload" -type d -exec /bin/chmod 755 {} +
    /usr/bin/find "$stage/payload" -type f -exec /bin/chmod 644 {} +
    /usr/bin/pkgbuild --root "$stage/payload" --ownership recommended --identifier com.push.policy.pkg --version 1.0 --install-location / PUSH-Policy.pkg
    echo 'Built policy only. Review and sign before deploying. No monitor was enabled.'
    """+"\n"
    static let enableMonitor="""
    #!/bin/bash
    # Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
    # Separate, deliberate MDM action. Starts real policy evaluation when executed.
    set -euo pipefail
    [[ "${1:-}" == --enable-reviewed-policy ]] || { echo 'Review policy and authorization first. Requires --enable-reviewed-policy.' >&2; exit 2; }
    [[ "$EUID" == 0 ]] || { echo 'Run through your management tool as root.' >&2; exit 1; }
    cli=/Library/Management/PUSH/push-cli
    [[ -x "$cli" ]] || exit 1
    [[ "$("$cli" config get auto.enabled)" == true ]] || { echo 'Automatic checks are disabled in policy.' >&2; exit 1; }
    [[ "$("$cli" config get debug.dryRun)" == false ]] || { echo 'Dry-run is enabled. Live activation stopped.' >&2; exit 1; }
    "$cli" install-daemon
    """+"\n"
    static func readme(teamID:String)->String {"""
    PUSH Client Deployment — Sebastian Santos
    Engine 1.11.0 / JamfCheckIn 1.1.1 / PUSH Admin 1.3.0

    This bundle excludes PUSH Admin from client computers. The client installs PUSH
    and JamfCheckIn, its only menu-bar app. The old standalone PUSH Status is retired.
    Local builds are ad-hoc signed and installers unsigned. These profiles do not
    sign or notarize applications. Production signing/notarization and a managed pilot
    are required before fleet rollout. Team constraint: \(teamID.isEmpty ? "none (local testing)":teamID).

    DEPLOY THROUGH JAMF / MDM
    1. Pause any existing PUSH monitor before changing profiles or policy.
       Review YAML, deadlines, authorization and images. Known plaintext credential
       fields are removed; review any custom settings for secrets before distribution.
    2. Upload Profiles/*.mobileconfig as computer configuration profiles and scope to
       a pilot group first. Background Items requires MDM delivery; do not double-click
       it as a substitute for enrollment. Stable profile identifiers permit replacement.
       If the old JamfCheckIn notifications profile is deployed, replace/unscope it to
       avoid conflicting notification payloads. Team constraints must match all signed
       executables for the matching service labels.
    3. Deploy PUSH-Client-1.11.0.pkg. Previous PUSH/JamfCheckIn files are backed up.
       PUSH monitors are paused. Nothing is launched by the installer. JamfCheckIn
       starts on the next graphical login, or the user can open it manually.
    4. Run Build-Policy-Package.command on your IT Mac to create PUSH-Policy.pkg.
       Sign it for production, then deploy AFTER the client, while monitoring remains
       paused. It installs this draft's YAML/images and has no activation scripts.
    5. Confirm managed authorization/bootstrap-token readiness through MDM and pilot.
       Only then execute Enable-Monitor.sh --enable-reviewed-policy as a separate
       root management action. This starts real checks immediately, and a live policy
       can download/install/restart. Do not execute it just to preview a popup.

    YAML remains authoritative. Profiles do not contain passwords, bootstrap tokens
    or update policy, and do not authorize macOS upgrades by themselves. Re-export
    policy when changing settings. There is no admin console on new client installs.
    Existing PUSH Admin from an older combined package is not silently deleted;
    remove that app through your management tool on employee Macs after review.

    ACCESS
    Notifications: JamfCheckIn native notifications only, banners enabled, lock-screen
    display disabled. PUSH popup windows have their own delivery path. Notification
    permission cannot guarantee that a user sees every alert in every Focus/session.
    Background Items: exact app/launchd identities only; approval does not install or
    activate missing services. No broad identifier prefixes or team-wide rules.
    No Full Disk Access, Accessibility, Screen Recording or camera/microphone grants
    are included. The optional gentle-restart AppleEvents profile is included only
    when a production-signed executable was selected and verified. It permits only
    push-cli to send events to Apple's System Events. It does not authorize arbitrary
    automation. This profile will NOT match the ad-hoc local client: deploy the exact
    production-signed release used to generate the requirement. Confirm TCC attribution
    on a managed pilot before enabling restart enforcement. Without restart enforcement,
    ordinary update/status deployment uses only the two baseline profiles.
    Validate optional Jamf diagnostics on pilot Macs; ordinary root-owned log file
    permissions are not fixed by granting Full Disk Access. Ask only for demonstrated
    feature requirements. Permissions profiles cannot repair Keychain ACLs.
    JamfCheckIn's pre-existing Jamf check-in/inventory administrator actions remain
    separate; PUSH update requests use the guarded channel without a password prompt.

    https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.servicemanagement.yaml
    https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.notificationsettings.yaml
    https://support.apple.com/guide/deployment/dep38df53c2a/web
    """+"\n"}
}
