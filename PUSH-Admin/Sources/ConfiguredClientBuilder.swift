// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

enum ClientActivation:String,CaseIterable,Identifiable {
    case paused,monitor
    var id:String {rawValue}
    var title:String {self == .paused ? "Install with monitoring paused":"Start monitoring after installation"}
}
enum ConfiguredClientBuilder {
    static func validate(_ document:ConfigDocument,activation:ClientActivation)throws {
        guard document.setupIssues.isEmpty else {throw DeploymentBundleError.invalid("Resolve the setup validation issues before building: "+document.setupIssues.joined(separator:"; "))}
        if activation == .monitor {
            guard !document.setupFlag("debug.dryRun"),document.setupFlag("auto.enabled") || document.setupFlag("entra.enabled") else {throw DeploymentBundleError.invalid("Starting monitoring requires dry-run off and an enabled macOS or registration policy. Use the paused package for inspection.")}
        }
    }
    /// Packaging commands only. Never installer, launchctl, a shell, or PUSH.
    static func command(_ path:String,_ arguments:[String],folder:URL)throws {
        guard ["/usr/sbin/pkgutil","/usr/bin/ditto","/usr/bin/pkgbuild"].contains(path) else {throw DeploymentBundleError.invalid("Unsupported packaging operation.")}
        let log=folder.appendingPathComponent("command-"+UUID().uuidString+".log")
        FileManager.default.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600])
        let handle=try FileHandle(forWritingTo:log);defer{try? handle.close();try? FileManager.default.removeItem(at:log)}
        let process=Process();process.executableURL=URL(fileURLWithPath:path);process.arguments=arguments;process.standardInput=FileHandle.nullDevice;process.standardOutput=handle;process.standardError=handle
        try process.run();let end=Date().addingTimeInterval(180)
        while process.isRunning {
            if Date()>end || (((try? FileManager.default.attributesOfItem(atPath:log.path)[.size]) as? NSNumber)?.intValue ?? 0) > 4_194_304 {process.terminate();kill(process.processIdentifier,SIGKILL);process.waitUntilExit();throw DeploymentBundleError.invalid("The package build exceeded its time or output limit. No installer was run.")}
            Thread.sleep(forTimeInterval:0.1)
        }
        guard process.terminationStatus==0 else {throw DeploymentBundleError.invalid("A packaging tool failed (exit \(process.terminationStatus)). Check free space and the matching Admin installation. No installer was run.")}
    }
    static func checkPayload(_ folder:URL,allowed:[String])throws {
        let fm=FileManager.default
        guard let files=fm.enumerator(at:folder,includingPropertiesForKeys:[.isSymbolicLinkKey,.isDirectoryKey]) else {throw DeploymentBundleError.invalid("The client payload is missing.")}
        for case let file as URL in files {
            let relative=String(file.path.dropFirst(folder.path.count+1))
            let values=try file.resourceValues(forKeys:[.isSymbolicLinkKey,.isDirectoryKey])
            guard values.isSymbolicLink != true,allowed.contains(where:{relative==$0 || relative.hasPrefix($0+"/") || (values.isDirectory==true && $0.hasPrefix(relative+"/"))}) else {throw DeploymentBundleError.invalid("The embedded client contains an unexpected payload path. Reinstall the matching Admin release.")}
        }
    }
    static func preinstall(assetPaths:[String])->String {
        let managedPaths=(["config.yaml"]+assetPaths).map{"\"$base/"+$0+"\""}.joined(separator:" ")
        return """
        #!/bin/bash
        # Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
        set -euo pipefail
        [[ "${3:-/}" == / ]] || exit 1
        base=/Library/Management/PUSH
        for directory in "$base" "$base/assets" "$base/assets/wallpapers" /Library/LaunchDaemons; do
            if [[ -e "$directory" || -L "$directory" ]]; then
                [[ -d "$directory" && ! -L "$directory" && "$(/usr/bin/stat -f %u "$directory")" == 0 ]] || exit 1
            fi
        done
        for file in \(managedPaths); do
            [[ ! -L "$file" ]] || { echo 'A managed policy/image path is a symbolic link; review it before replacement.' >&2; exit 1; }
        done
        scripts="$(cd "$(dirname "$0")" && pwd)"
        /bin/bash "$scripts/engine-preinstall" "$@"
        /bin/bash "$scripts/jamf-preinstall" "$@"
        """+"\n"
    }
    static func postinstall(activation:ClientActivation,main:Bool,entra:Bool,yamlHash:String)->String {
        let start=activation == .monitor ? """
        /bin/mkdir -p /Library/LaunchDaemons
        set +e
        # Install the reviewed five-minute schedules without running a check in
        # this installer script. First eligible execution is after the interval.
        main_loaded=false; entra_loaded=false
        install_monitor() {
            local name="$1" label="$2"
            /bin/cp "$scripts/$name-monitor.plist" "/Library/LaunchDaemons/$label.plist" || return 1
            /usr/sbin/chown root:wheel "/Library/LaunchDaemons/$label.plist" || return 1
            /bin/chmod 644 "/Library/LaunchDaemons/$label.plist" || return 1
            /bin/launchctl bootstrap system "/Library/LaunchDaemons/$label.plist" && /bin/launchctl print "system/$label" >/dev/null
        }
        if [[ \(main ? "true":"false") == true ]]; then
            if install_monitor main com.push.autoupdate; then main_loaded=true; fi
        fi
        if [[ \(entra ? "true":"false") == true ]]; then
            if install_monitor entra com.push.entra-registration; then entra_loaded=true; fi
        fi
        now="$(( $(/bin/date +%s) - 978307200 ))"
        for item in "main:$main_loaded" "entra:$entra_loaded"; do
            name="${item%%:*}"; loaded="${item##*:}"
            if [[ "$loaded" == true ]]; then
                /bin/rm -f "/Library/Management/PUSH/health/intent-$name.json"
                printf '{"desired":"enabled","changedAt":%s,"reason":"Reviewed configured-client installer loaded a deferred five-minute monitor"}\\n' "$now" > "/Library/Management/PUSH/health/intent-$name.json"
                /bin/chmod 644 "/Library/Management/PUSH/health/intent-$name.json"
            fi
        done
        /bin/rm -f /Library/Management/PUSH/configured-activation.json
        printf '{"requested":true,"mainLoaded":%s,"entraLoaded":%s,"changedAt":%s,"firstCheckDelaySeconds":300}\\n' "$main_loaded" "$entra_loaded" "$now" > /Library/Management/PUSH/configured-activation.json
        /bin/chmod 644 /Library/Management/PUSH/configured-activation.json
        echo "Client installed; main monitor loaded: $main_loaded; registration monitor loaded: $entra_loaded. Check endpoint readiness. First checks wait five minutes; no upgrade success is inferred."
        # A failed bootstrap remains visible in the saved result and readiness.
        # Do not trigger Installer rollback while another loaded monitor exists.
        """:"""
        /bin/rm -f /Library/Management/PUSH/configured-activation.json
        printf '{"requested":false,"mainLoaded":false,"entraLoaded":false}\\n' > /Library/Management/PUSH/configured-activation.json
        /bin/chmod 644 /Library/Management/PUSH/configured-activation.json
        echo 'Configured client installed. Monitoring remains paused.'
        """
        return """
        #!/bin/bash
        # Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
        set -euo pipefail
        [[ "${3:-/}" == / ]] || exit 1
        scripts="$(cd "$(dirname "$0")" && pwd)"
        /bin/bash "$scripts/engine-postinstall" "$@"
        cli=/Library/Management/PUSH/push-cli
        # Compare the installed policy to the reviewed package before any activation.
        [[ "$(/usr/bin/shasum -a 256 /Library/Management/PUSH/config.yaml | /usr/bin/awk '{print $1}')" == \(yamlHash) ]] || { echo 'Installed YAML differs from the reviewed package. Monitoring was not activated.' >&2; exit 1; }
        \(start)
        """+"\n"
    }
    static func build(_ input:DeploymentBundleInput,client:URL,activation:ClientActivation,to destination:URL)throws {
        let fm=FileManager.default
        let document=ConfigDocument.load(input.yaml,name:"Reviewed package policy")
        guard document.omittedCredentials==0 else {throw DeploymentBundleError.invalid("Remove plaintext credential fields before packaging.")}
        try validate(document,activation:activation)
        guard !fm.fileExists(atPath:destination.path) else {throw DeploymentBundleError.invalid("Choose a new package export folder. Existing builds are never replaced.")}
        let stage=destination.deletingLastPathComponent().appendingPathComponent(".push-build-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? fm.removeItem(at:stage)}
        let bundle=stage.appendingPathComponent("deliverable")
        try DeploymentBundle.write(input,client:client,to:bundle)
        let expanded=stage.appendingPathComponent("expanded")
        try command("/usr/sbin/pkgutil",["--expand-full",client.path,expanded.path],folder:stage)
        let engine=expanded.appendingPathComponent("push-engine.pkg"),jamf=expanded.appendingPathComponent("jamfcheckin.pkg")
        for (component,identifier,version) in [(engine,"com.push.pkg","1.9.1"),(jamf,"com.sebastianitconsulting.jamfcheckin.pkg","1.1.0")] {
            let info=try String(contentsOf:component.appendingPathComponent("PackageInfo"),encoding:.utf8)
            guard info.contains("identifier=\""+identifier+"\""),info.contains("version=\""+version+"\"") else {throw DeploymentBundleError.invalid("The embedded client versions do not match this builder.")}
        }
        let enginePayload=engine.appendingPathComponent("Payload"),jamfPayload=jamf.appendingPathComponent("Payload")
        try checkPayload(enginePayload,allowed:["Library/Management/PUSH/push-cli","Library/Management/PUSH/push-ui.app","Library/Management/PUSH/Local-Test","Library/Management/PUSH/assets","Library/Management/PUSH/user-request-protocol.json"])
        try checkPayload(jamfPayload,allowed:["Applications/JamfCheckIn.app","Library/LaunchAgents/com.sebastianitconsulting.jamfcheckin.plist"])
        guard !fm.fileExists(atPath:enginePayload.appendingPathComponent("Library/Management/PUSH/PUSH Status.app").path) else {throw DeploymentBundleError.invalid("Use the client release that retires the standalone status menu.")}
        if document.setupFlag("uptime.enabled") {
            let identity=try RestartProfileIdentity.inspect(enginePayload.appendingPathComponent("Library/Management/PUSH/push-cli"))
            guard let reviewed=input.restartIdentity,identity.teamID==reviewed.teamID,identity.requirement==reviewed.requirement,identity.sha256==reviewed.sha256 else {throw DeploymentBundleError.invalid("The client's signed executable does not match the selected restart approval. Use the matching signed production client, or disable uptime enforcement for local testing.")}
        }
        let readme="""
        PUSH Configured Client — built with PUSH Admin 1.1.0
        Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS

        INSTALL ONE PACKAGE: PUSH-Configured-Client.pkg
        Includes PUSH 1.9.1, JamfCheckIn 1.1.0, the reviewed YAML and all staged images.
        PUSH Admin is excluded. The reviewed YAML REPLACES installed policy after backup.
        Previous state, credentials and runtime data are preserved by the client scripts.
        Selected mode: \(activation.title).
        \(activation == .monitor ? "Future installation loads selected monitors; their first checks wait five minutes and can then notify, download, install or restart under the reviewed policy. Monitor loading does not prove upgrade authorization or installation success.":"Future installation leaves monitors paused. Enable only after your managed pilot review.")

        PolicyPayload contains the reviewed configuration/images for inspection only;
        it is already inside the installer. Do not install another policy package.
        Deploy Profiles through MDM before installing on the approved pilot group.
        A package cannot install the MDM-only privacy/background approvals or enroll a Mac.
        Optional dependencies (Mist, protected Installomator, supported Self Service,
        Company Portal and managed upgrade authorization) remain separate managed
        prerequisites when selected. The setup suggestions identify those requirements.
        Local binaries are ad-hoc signed; this generated installer is unsigned. Use
        verified Developer ID signing and notarization before fleet rollout. Repackaging
        signed apps preserves their signatures; the new package still needs installer signing.
        No installer or service was run while building this output.
        A failed activation is recorded in configured-activation.json and can leave the client installed and paused/partly loaded;
        inspect endpoint readiness and installer logs before retrying. Do not infer
        successful updates from a successful build or service bootstrap.

        ACCESS
        Notification and background-item profiles use exact identities. Replace any
        older conflicting JamfCheckIn notification profile in MDM. Team constraints,
        when supplied, must match the actual production signatures. Optional gentle
        restart approval is included only for a matching verified signed client.
        No broad Full Disk Access, Accessibility or Screen Recording grant is included.
        Profile approval cannot guarantee alert visibility through every Focus/session.
        Existing Jamf check-in/inventory admin actions are separate from PUSH requests.
        https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.servicemanagement.yaml
        https://github.com/apple/device-management/blob/release/mdm/profiles/com.apple.notificationsettings.yaml
        """+"\n"
        let payload=stage.appendingPathComponent("payload")
        try command("/usr/bin/ditto",[enginePayload.path,payload.path],folder:stage)
        try command("/usr/bin/ditto",[jamfPayload.path,payload.path],folder:stage)
        let base=payload.appendingPathComponent("Library/Management/PUSH")
        try Data(input.yaml.utf8).write(to:base.appendingPathComponent("config.yaml"),options:.atomic)
        try Data(readme.utf8).write(to:base.appendingPathComponent("Local-Test/INSTALL-AND-TEST.txt"),options:.atomic)
        for (path,data) in input.assets {let file=base.appendingPathComponent(path);try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try data.write(to:file,options:.atomic)}
        // All payload files are public policy/assets/code, never secret credentials.
        for case let file as URL in fm.enumerator(at:payload,includingPropertiesForKeys:[.isDirectoryKey])! {
            let directory=(try file.resourceValues(forKeys:[.isDirectoryKey])).isDirectory==true
            let previous=(try? fm.attributesOfItem(atPath:file.path)[.posixPermissions]) as? NSNumber
            try fm.setAttributes([.posixPermissions:directory ? 0o755:((previous?.intValue ?? 0)&0o111 != 0 ? 0o755:0o644)],ofItemAtPath:file.path)
        }
        let scripts=stage.appendingPathComponent("scripts");try fm.createDirectory(at:scripts,withIntermediateDirectories:false)
        for (source,name) in [(engine.appendingPathComponent("Scripts/preinstall"),"engine-preinstall"),(engine.appendingPathComponent("Scripts/postinstall"),"engine-postinstall"),(jamf.appendingPathComponent("Scripts/preinstall"),"jamf-preinstall")] {try fm.copyItem(at:source,to:scripts.appendingPathComponent(name))}
        if activation == .monitor {
            for (name,label,args) in [("main","com.push.autoupdate",["auto-check","--scheduled"]),("entra","com.push.entra-registration",["entra","scheduled","--from-daemon"])] {
                let plist:[String:Any]=["Label":label,"ProgramArguments":["/Library/Management/PUSH/push-cli"]+args,"RunAtLoad":false,"StartInterval":300,"KeepAlive":false,"ProcessType":"Background","StandardOutPath":"/Library/Management/PUSH/logs/"+name+"-monitor.log","StandardErrorPath":"/Library/Management/PUSH/logs/"+name+"-monitor.log"]
                try PropertyListSerialization.data(fromPropertyList:plist,format:.xml,options:0).write(to:scripts.appendingPathComponent(name+"-monitor.plist"))
            }
        }
        let yamlHash=DeploymentBundle.digest(Data(input.yaml.utf8))
        for (name,text) in [("preinstall",preinstall(assetPaths:input.assets.keys.sorted())),("postinstall",postinstall(activation:activation,main:document.setupFlag("auto.enabled"),entra:document.setupFlag("entra.enabled"),yamlHash:yamlHash))] {try Data(text.utf8).write(to:scripts.appendingPathComponent(name));try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:scripts.appendingPathComponent(name).path)}
        let components=stage.appendingPathComponent("components.plist")
        try command("/usr/bin/pkgbuild",["--analyze","--root",payload.path,components.path],folder:stage)
        guard var componentList=try PropertyListSerialization.propertyList(from:Data(contentsOf:components),format:nil) as? [[String:Any]],componentList.count==2 else {throw DeploymentBundleError.invalid("The client must contain exactly the PUSH popup and JamfCheckIn app bundles.")}
        for i in componentList.indices {componentList[i]["BundleIsRelocatable"]=false;componentList[i]["BundleIsVersionChecked"]=false}
        try PropertyListSerialization.data(fromPropertyList:componentList,format:.xml,options:0).write(to:components)
        let package=bundle.appendingPathComponent("PUSH-Configured-Client.pkg")
        try command("/usr/bin/pkgbuild",["--root",payload.path,"--component-plist",components.path,"--scripts",scripts.path,"--ownership","recommended","--identifier","com.push.configured.client","--version","1.9.1","--install-location","/",package.path],folder:stage)
        for name in ["PUSH-Client-1.9.1.pkg","Build-Policy-Package.command","Enable-Monitor.sh"] {try fm.removeItem(at:bundle.appendingPathComponent(name))}
        try Data(readme.utf8).write(to:bundle.appendingPathComponent("READ-ME-FIRST.txt"),options:.atomic)
        // Replace the baseline manifest after replacing its separate-package workflow.
        try fm.removeItem(at:bundle.appendingPathComponent("manifest.json"))
        var files:[[String:String]]=[]
        for case let file as URL in fm.enumerator(at:bundle,includingPropertiesForKeys:[.isRegularFileKey])! {if (try file.resourceValues(forKeys:[.isRegularFileKey])).isRegularFile==true {files.append(["path":String(file.path.dropFirst(bundle.path.count+1)),"sha256":DeploymentBundle.digest(try Data(contentsOf:file))])}}
        let manifest:[String:Any]=["formatVersion":2,"developer":"Sebastian Santos","adminVersion":"1.1.0","clientVersion":"1.9.1","activation":activation.rawValue,"yamlSHA256":yamlHash,"sourceClientSHA256":DeploymentBundle.digest(try Data(contentsOf:client)),"adminIncludedOnClients":false,"signing":"Unsigned generated installer; verify production signing/notarization separately","files":files.sorted{$0["path"]!<$1["path"]!}]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:bundle.appendingPathComponent("manifest.json"))
        try fm.moveItem(at:bundle,to:destination)
    }
}
