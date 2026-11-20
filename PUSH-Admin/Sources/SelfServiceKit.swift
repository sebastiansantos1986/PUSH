// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit

struct SelfServiceSettings:Codable {
    var offer26=true,offer27=true
    var title26="Upgrade to macOS Tahoe",title27="Upgrade to macOS 27"
    var description26="Upgrade to the latest stable macOS Tahoe release supported by your Mac. Save your work and connect to power. PUSH checks available storage, shows download progress and warns you before installation begins. Your Mac will restart when ready."
    var description27="Upgrade to the latest stable macOS 27 release supported by your Mac. Save your work and connect to power. PUSH checks available storage, shows download progress and warns you before installation begins. Your Mac will restart when ready."
    var majors:[Int] {[26,27].filter{$0==26 ? offer26:offer27}}
    func title(_ major:Int)->String {major==26 ? title26:title27}
    func description(_ major:Int)->String {major==26 ? description26:description27}
    func validate()throws {
        guard !majors.isEmpty,majors.allSatisfy({!title($0).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && title($0).count<=120 && !description($0).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && description($0).count<=4000}) else {throw AdminError.message("Select at least one offer and provide its title and description (title up to 120 characters; description up to 4,000).")}
    }
}
enum SelfServiceKit {
    static let logoPath="/Library/Management/PUSH/self-service/assets/popup-logo.png"
    static let states=["downloading","installing","preflightDisk","preflightPower","rebooting"]
    static func profile(_ document:ConfigDocument,major:Int)throws->ConfigDocument {
        guard [26,27].contains(major) else {throw AdminError.message("Only macOS 26 and 27 offers are supported.")}
        var result=ConfigDocument.fresh
        // Copy presentation and nonsecret preflight thresholds only. No campaign
        // deadline, targeting, auth account/secret, or background task is imported.
        for group in configGroups where group.fields.contains(where:{$0.id.hasPrefix("ui.")}) {
            for field in group.fields where field.id.hasPrefix("ui.") {if let value=document.value(field.id){result.edits[field.id]=value}}
        }
        for key in ["preflight.minDiskSpaceGB","preflight.minBatteryPercent","preflight.requireACPower"] {if let value=document.value(key){result.edits[key]=value}}
        for key in ["auto.enabled","auto.trackLatest","auto.autoInstallNonSystemUpdates","update.allowUserUpdateRequests","update.autoInstallAfterDeadline","update.silentInstallAfterDeadline","update.forceRestartAfterInstall","apps.enabled","entra.enabled","uptime.enabled","compliance.wallpaperEnabled","ui.menuBarEnabled"] {result.edits[key]="false"}
        for key in ["update.deadline","update.automaticDeadline","update.automaticDeadlineTarget"] {result.edits[key]=""}
        result.edits["update.targetVersion"]="\(major).0";result.edits["update.macOSName"]=major==26 ? "macOS Tahoe":"macOS";result.edits["update.releaseType"]="major"
        result.edits["auto.maximumMajorVersion"]="\(major)";result.edits["auto.enforceMinimumMajorVersion"]="\(major)"
        result.edits["auth.promptUserForInstall"]="true";result.edits["debug.dryRun"]="false"
        result.edits["ui.appName"]="Software Update"
        if document.value("ui.logoPath")==deployedPopupLogoPath {
            guard let bytes=document.logoImageData else {throw AdminError.message("Choose the custom popup icon again before exporting.")}
            result.logoImageData=try BrandingImage.normalizedPNG(bytes);result.edits["ui.logoPath"]=logoPath
        }else if !(document.value("ui.logoPath") ?? "").isEmpty {throw AdminError.message("Select an icon in Admin so the offer can include it on every Mac.")}
        guard result.problems.isEmpty else {throw AdminError.message("Review the offer settings: "+result.problems.joined(separator:"; "))}
        return result
    }
    static let bootstrapMarker="client_event=\"\" # PUSH_JAMF_CLIENT_EVENT"
    static func binding(_ data:Data,event:String)throws->Data {
        let text=String(decoding:data,as:UTF8.self)
        guard text.components(separatedBy:bootstrapMarker).count==2,!event.isEmpty,event.utf8.allSatisfy({(48...57).contains($0)||(97...122).contains($0)||$0==45}) else {throw AdminError.message("Rebuild the Self Service kit in the current Admin version to include its client prerequisite handoff.")}
        return Data(text.replacingOccurrences(of:bootstrapMarker,with:"client_event=\""+event+"\" # PUSH_JAMF_CLIENT_EVENT").utf8)
    }
    static func script(major:Int)->String {
        """
        #!/bin/bash
        # Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
        set -euo pipefail
        [[ "$EUID" == 0 ]] || { echo 'Run this script as a Jamf policy.' >&2; exit 1; }
        cli=/Library/Management/PUSH/push-cli
        ui=/Library/Management/PUSH/push-ui.app/Contents/MacOS/push-ui
        jamf=/usr/local/jamf/bin/jamf
        mist=/usr/local/bin/mist
        mist_alt=/opt/homebrew/bin/mist
        current_os="$(/usr/bin/sw_vers -productVersion)"
        current_major="${current_os%%.*}"
        [[ "$current_major" =~ ^[0-9]+$ ]] || { echo 'Unable to determine the running macOS generation.' >&2; exit 1; }
        needs_mist=false
        if (( 10#$current_major < \(major) )); then needs_mist=true; fi
        \(bootstrapMarker)
        trusted_executable() {
            local path="$1" cursor="$1" owner mode
            [[ -x "$path" ]] || { echo "Prerequisite missing or not executable: $path" >&2;return 1; }
            while [[ "$cursor" != / ]]; do
                [[ ! -L "$cursor" ]] || { echo "Prerequisite path is a symbolic link: $cursor" >&2;return 1; }
                read -r owner mode <<< "$(/usr/bin/stat -f '%u %Lp' "$cursor" 2>/dev/null)"
                [[ "$owner" == 0 && "$mode" =~ ^[0-7]+$ ]] || { echo "Prerequisite path must be root-owned: $cursor (uid=$owner mode=$mode)" >&2;return 1; }
                (( (8#$mode & 022) == 0 )) || { echo "Prerequisite path is group/other writable: $cursor (mode=$mode)" >&2;return 1; }
                cursor="${cursor%/*}"; [[ -n "$cursor" ]] || cursor=/
            done
        }
        client_version_ok() {
            trusted_executable "$cli" || return 1
            local version major minor patch
            version="$("$cli" --version)" || return 1
            version="${version##*v}"
            [[ "$version" =~ ^([0-9]+)\\.([0-9]+)\\.([0-9]+)$ ]] || return 1
            major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"
            if (( 10#$major > 1 || (10#$major == 1 && (10#$minor > 16 || (10#$minor == 16 && 10#$patch >= 3))) )); then return 0; fi
            echo "Installed PUSH client is $version; this offer requires 1.16.7 or newer." >&2
            return 1
        }
        client_ready() { client_version_ok && trusted_executable "$ui"; }
        mist_ready() {
            [[ "$needs_mist" == true ]] || return 0
            local tool version major minor
            for tool in "$mist" "$mist_alt"; do
                trusted_executable "$tool" || continue
                version="$("$tool" --version)" || continue
                # Mist reports the installed version first, with optional status
                # such as "2.3 (latest: 2.3)". Never select the advertised latest
                # version or the last word of that status as the installed version.
                version="${version#mist-cli }";version="${version#mist }";version="${version#v}"
                [[ "$version" =~ ^([0-9]+)\\.([0-9]+)(\\.[0-9]+)?([[:space:]]|$) ]] || continue
                major="${BASH_REMATCH[1]}";minor="${BASH_REMATCH[2]}"
                if (( 10#$major > 2 || (10#$major == 2 && 10#$minor >= 3) )); then return 0; fi
            done
            return 1
        }
        prerequisites_ready() { client_ready && mist_ready; }
        if ! prerequisites_ready; then
            if client_version_ok && [[ "$("$cli" --version)" != 'push-cli v1.16.7' ]]; then
                echo 'A newer PUSH client has a missing/untrusted prerequisite. IT must repair its matching prerequisite package; this offer will not downgrade it.' >&2; exit 1
            fi
            if [[ -z "$client_event" ]]; then
                echo 'PUSH client or popup UI is missing/outdated. Deploy the matching PUSH Client 1.16.7 prerequisite before this manually exported offer.' >&2; exit 1
            fi
            trusted_executable "$jamf" || { echo 'The protected Jamf agent is missing. IT must repair enrollment/client deployment.' >&2; exit 1; }
            echo 'Preparing PUSH and required Mist prerequisites before the selected macOS offer...'
            "$jamf" policy -event "$client_event" || { echo 'PUSH prerequisite request failed. Review its Jamf policy log; no macOS installation was requested.' >&2; exit 1; }
            prerequisites_ready || { echo 'PUSH prerequisite did not provide the verified client, popup UI, and Mist (when required). Review the specific prerequisite/version errors above and the installer log. A successful package action alone does not verify the installed files. No macOS installation was requested.' >&2; exit 1; }
        fi
        echo 'PUSH client and popup UI verified. Resolving the latest eligible macOS \(major).x update...'
        exec "$cli" self-service-upgrade --major \(major) --config /Library/Management/PUSH/self-service/macOS-\(major).yaml
        """+"\n"
    }
    static let guide="""
    PUSH Jamf Self Service offers — Developer: Sebastian Santos
    Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

    This folder is a setup kit, not an automatic Jamf import or deployment.
    1. Pilot the matching PUSH Client 1.16.7 first. The client package is a separate
       prerequisite, not a package to reinstall on every Self Service click.
       Admin is not included on endpoints. Existing campaign settings stay separate.
       This local-test client installer pauses existing monitoring. If you also use
       a reminder campaign, review and re-enable its monitors through Readiness
       after the separate client installation. Offers need no background monitor.
       A root-protected, approved Mist CLI at /usr/local/bin/mist or
       /opt/homebrew/bin/mist is also needed for major-upgrade compatible discovery.
       A user-writable Homebrew installation is not accepted by this root workflow.
       Deploy/sign/notarize production binaries using your organization's process;
       local ad-hoc packages are for testing, not proof of production readiness.
       When using Publish to Jamf, generated offer scripts receive a deployment-
       specific custom event for that client policy. If the client/UI is missing
       or outdated, the offer requests the prerequisite once, rechecks installation
       and continues only if verified. Existing valid clients skip reinstallation.
       The prerequisite must be enabled, scoped, and eligible under its execution
       history; failure stops before requesting a macOS update. Manual export
       scripts have no automatic event until configured by the publisher.
    2. Upload PUSH-SelfService-Profiles.pkg and the supplied scripts to Jamf Pro.
       The profiles package contains only isolated offer YAML and an optional logo.
       It installs no schedules and does not replace config.yaml or state.json.
    3. Create one policy per selected generation. Enable Show in Self Service,
       choose Ongoing execution frequency, and leave automatic triggers disabled.
       Attach the profiles package; set the corresponding script priority to After.
       Copy the supplied display name/description. Select Self-Service-Icon.png if
       you chose a custom icon; otherwise choose your preferred icon in Jamf.
       Jamf-policy-plan.json is a human-readable checklist, NOT an API import.
    4. Scope each policy to an eligible pilot group: hardware compatible with that
       generation, running macOS 14 or later and no newer than that generation.
       Exclude unsupported/unverified hardware until IT reviews it. Use Admin's
       Tahoe hardware audit for macOS 26 reporting. Confirm macOS 27 eligibility
       using current Apple data and the managed test fleet; no invented support list.
       Honor Apple/MDM availability and deferrals; PUSH cannot bypass restrictions.
    5. Test on a managed pilot. User clicks the item in Self Service while logged in.
       The latest eligible stable release within that generation is selected at run
       time. A Mac on the same generation uses Apple's native point-update route;
       an actual major upgrade uses a verified full installer. No downgrade occurs.

    PUSH UI: authorization when no valid saved user password is available, download
    progress, installer preparation progress, and the final prepared-restart notice.
    Low-storage and power warnings appear when needed. The client contains PUSH
    only; JamfCheckIn and PUSH Admin are not deployed.
    Passwords are never included in this kit. Canceled authorization starts no update.
    For major upgrades the final notice follows startosinstall preparation, not
    download completion. The native point-update route retains its pre-install
    warning because macOS controls its restart timing. macOS controls restart timing after the native update is committed.
    Failures/unsupported hardware are reported in the Jamf policy log and PUSH log,
    without extra campaign, error or compliance popups from this offer.
    Missing authorization or failed preflight prevents installation. Once startosinstall
    commits preparation, macOS owns its restart timer; a final UI failure is reported
    honestly and cannot promise cancellation of the committed installation.
    No reminders, deadlines, wallpaper enforcement or background offer monitor is
    enabled by these profiles. A separate existing campaign remains independent.
    Installed/staged is not a completed-upgrade claim; verify after reboot.

    No installer, update, credential read or restart was run while exporting.
    """
    static func write(document:ConfigDocument,settings:SelfServiceSettings,client:URL,to destination:URL,mist:URL?=nil)throws {
        try settings.validate()
        let fm=FileManager.default
        guard !fm.fileExists(atPath:destination.path),client.pathExtension=="pkg",(try client.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey])).isSymbolicLink != true else {throw AdminError.message("Choose a new export folder and the matching client package.")}
        let stage=destination.deletingLastPathComponent().appendingPathComponent(".push-self-service-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? fm.removeItem(at:stage)}
        let checked=stage.appendingPathComponent("client-inspection")
        try ConfiguredClientBuilder.command("/usr/sbin/pkgutil",["--expand-full",client.path,checked.path],folder:stage)
        guard let info=try? String(contentsOf:checked.appendingPathComponent("push-engine.pkg/PackageInfo"),encoding:.utf8),info.contains("identifier=\"com.push.pkg\""),info.contains("version=\"1.16.7\"") else {throw AdminError.message("This kit requires the matching PUSH Client 1.16.7 package.")}
        let output=stage.appendingPathComponent("output"),payload=stage.appendingPathComponent("payload"),profileRoot=payload.appendingPathComponent("Library/Management/PUSH/self-service")
        try fm.createDirectory(at:output,withIntermediateDirectories:true)
        try fm.createDirectory(at:profileRoot,withIntermediateDirectories:true,attributes:[.posixPermissions:0o755])
        var plans:[[String:Any]]=[]
        for major in settings.majors {
            let policy=try profile(document,major:major)
            try Data(policy.yaml.utf8).write(to:profileRoot.appendingPathComponent("macOS-\(major).yaml"))
            if let logo=policy.logoImageData {
                let assets=profileRoot.appendingPathComponent("assets");try fm.createDirectory(at:assets,withIntermediateDirectories:true,attributes:[.posixPermissions:0o755])
                try logo.write(to:assets.appendingPathComponent("popup-logo.png"));try logo.write(to:output.appendingPathComponent("Self-Service-Icon.png"))
            }
            let name="Jamf-Offer-macOS-\(major).sh"
            try Data(script(major:major).utf8).write(to:output.appendingPathComponent(name))
            try Data((settings.title(major)+"\n\n"+settings.description(major)+"\n\nYou may be asked for your Mac login password to authorize installation.\n").utf8).write(to:output.appendingPathComponent("Self-Service-macOS-\(major).txt"))
            plans.append(["generation":major,"displayName":settings.title(major),"description":settings.description(major),"selfService":true,"executionFrequency":"Ongoing","automaticTriggers":[],"package":"PUSH-SelfService-Profiles.pkg","script":name,"scriptPriority":"After","scope":"Compatible pilot Macs; macOS 14 or later; no newer generation"])
        }
        try ConfiguredClientBuilder.command("/usr/bin/pkgbuild",["--root",payload.path,"--ownership","recommended","--identifier","com.push.self-service.profiles","--version","1.0.0","--install-location","/",output.appendingPathComponent("PUSH-SelfService-Profiles.pkg").path],folder:stage)
        try fm.copyItem(at:client,to:output.appendingPathComponent("PUSH-Client-1.16.7.pkg"))
        try SelfServiceRepairPackage.build(engine:checked.appendingPathComponent("push-engine.pkg"),to:output.appendingPathComponent("PUSH-Repair-Client.pkg"),stage:stage)
        if let mist {
            try JamfBundledDependencies.validateMist(mist)
            try fm.copyItem(at:mist,to:output.appendingPathComponent("Approved-Mist.pkg"))
            for name in ["Mist-CLI-LICENSE.txt","Mist-CLI-Provenance.json"] {if let url=Bundle.main.url(forResource:(name as NSString).deletingPathExtension,withExtension:(name as NSString).pathExtension) {try fm.copyItem(at:url,to:output.appendingPathComponent(name))}}
        }
        try Data(guide.utf8).write(to:output.appendingPathComponent("READ-ME-FIRST.txt"))
        try JSONSerialization.data(withJSONObject:["format":"setup checklist; not Jamf API import","developer":"Sebastian Santos","policies":plans],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("Jamf-policy-plan.json"))
        let files=try fm.contentsOfDirectory(at:output,includingPropertiesForKeys:nil).map{["path":$0.lastPathComponent,"sha256":DeploymentBundle.digest(try Data(contentsOf:$0))]}.sorted{$0["path"]!<$1["path"]!}
        try JSONSerialization.data(withJSONObject:["developer":"Sebastian Santos","minimumClient":"1.16.7","noAutomaticTriggers":true,"files":files],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("manifest.json"))
        try fm.moveItem(at:output,to:destination)
    }
}
extension AdminStore {
    var selfServiceSettings:SelfServiceSettings {get {document.selfServiceSettings ?? SelfServiceSettings()} set {document.selfServiceSettings=newValue}}
    func exportSelfServiceKit(){
        do{
            try selfServiceSettings.validate()
            guard let client=Bundle.main.url(forResource:"PUSH-Client-1.16.7",withExtension:"pkg") else {throw AdminError.message("Reinstall the matching Admin; its client prerequisite is missing.")}
            let panel=NSSavePanel();panel.nameFieldStringValue="PUSH-Jamf-Self-Service";panel.message="Export isolated offer profiles, two policy scripts and the client prerequisite. This does not publish to Jamf or install anything."
            guard panel.runModal() == .OK,let url=panel.url else{return}
            try SelfServiceKit.write(document:document,settings:selfServiceSettings,client:client,to:url,mist:JamfBundledDependencies.mist())
            notice="Self Service kit created. Follow READ-ME-FIRST to create the Jamf policies. No update, installer or deployment ran."
        }catch{notice=error.localizedDescription}
    }
}
