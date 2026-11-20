// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

/// Reuses the verified client payload without the local-test installer's service
/// shutdown. Repair never replaces policy, state, credentials or monitoring intent.
enum SelfServiceRepairPackage {
    static func build(engine:URL,to output:URL,stage:URL)throws {
        let fm=FileManager.default,scripts=stage.appendingPathComponent("repair-scripts")
        try fm.createDirectory(at:scripts,withIntermediateDirectories:false)
        for (name,text) in [("preinstall",preinstall),("postinstall",postinstall)] {
            let file=scripts.appendingPathComponent(name);try Data(text.utf8).write(to:file)
            try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path)
        }
        let components=stage.appendingPathComponent("repair-components.plist"),payload=engine.appendingPathComponent("Payload")
        // The payload contains shipped code and public defaults only. Active
        // policy and runtime records must never become repair-package payload.
        let base=payload.appendingPathComponent("Library/Management/PUSH")
        for name in ["config.yaml","config.json","state.json","health"] {
            guard !fm.fileExists(atPath:base.appendingPathComponent(name).path) else {throw AdminError.message("Client repair payload unexpectedly contains active policy/state. Select the base PUSH client package.")}
        }
        try ConfiguredClientBuilder.command("/usr/bin/pkgbuild",["--analyze","--root",payload.path,components.path],folder:stage)
        var entries=try PropertyListSerialization.propertyList(from:Data(contentsOf:components),format:nil) as! [[String:Any]]
        for index in entries.indices {entries[index]["BundleIsRelocatable"]=false}
        try PropertyListSerialization.data(fromPropertyList:entries,format:.xml,options:0).write(to:components)
        try ConfiguredClientBuilder.command("/usr/bin/pkgbuild",["--root",payload.path,"--component-plist",components.path,"--scripts",scripts.path,"--ownership","recommended","--identifier","com.push.pkg","--version","1.16.7","--install-location","/",output.path],folder:stage)
    }
    static let preinstall="""
    #!/bin/bash
    # PUSH — Developer: Sebastian Santos — in-place Self Service repair only
    set -euo pipefail
    [[ "${3:-/}" == / ]] || exit 1
    for path in /Library/Management /Library/Management/PUSH /usr/local /usr/local/bin; do
        [[ ! -e "$path" && ! -L "$path" ]] && continue
        [[ -d "$path" && ! -L "$path" ]] || exit 1
        read -r owner mode <<< "$(/usr/bin/stat -f '%u %Lp' "$path")"
        [[ "$owner" == 0 && "$mode" =~ ^[0-7]+$ ]] && (( (8#$mode & 022)==0 )) || exit 1
    done
    for name in startosinstall softwareupdate mist push-cli; do
        if /usr/bin/pgrep -x "$name" >/dev/null; then
            echo "PUSH repair is waiting for $name to finish. Retry the Self Service offer." >&2; exit 1
        fi
    done
    backup_root=/Library/Management/PUSH-backups
    if [[ -e "$backup_root" || -L "$backup_root" ]]; then
        [[ -d "$backup_root" && ! -L "$backup_root" && "$(/usr/bin/stat -f '%u %Lp' "$backup_root")" == '0 700' ]] || exit 1
    fi
    /bin/mkdir -p "$backup_root"; /bin/chmod 700 "$backup_root"
    backup="$(/usr/bin/mktemp -d "$backup_root/repair.XXXXXXXX")"
    base=/Library/Management/PUSH
    /bin/mkdir -p "$base"
    for name in config.yaml config.json state.json detections.json apps-state.json entra-state.json preparation.json preparation notification-history.json install-recovery.json user-request-result.json assets health; do
        if [[ -e "$base/$name" ]]; then /usr/bin/ditto "$base/$name" "$backup/$name"; fi
    done
    /bin/rm -f "$base/repair-backup-path"
    printf '%s\\n' "$backup" > "$base/repair-backup-path"; /bin/chmod 600 "$base/repair-backup-path"
    echo 'Repairing PUSH in place. Existing policy, runtime state, monitoring and Keychain storage are preserved.'
    """+"\n"
    static let postinstall="""
    #!/bin/bash
    # PUSH — Developer: Sebastian Santos — never starts a monitor or OS update
    set -euo pipefail
    [[ "${3:-/}" == / ]] || exit 1
    base=/Library/Management/PUSH
    pointer="$base/repair-backup-path"
    [[ -f "$pointer" && ! -L "$pointer" && "$(/usr/bin/stat -f '%u %Lp' "$pointer")" == '0 600' ]] || exit 1
    backup="$(/bin/cat "$pointer")"
    case "$backup" in /Library/Management/PUSH-backups/repair.*) ;; *) exit 1 ;; esac
    [[ -d "$backup" && ! -L "$backup" && "$(/usr/bin/stat -f '%u %Lp' "$backup")" == '0 700' ]] || exit 1
    for name in config.yaml config.json state.json detections.json apps-state.json entra-state.json preparation.json preparation notification-history.json install-recovery.json user-request-result.json assets health; do
        if [[ ! -e "$base/$name" && ! -L "$base/$name" && -e "$backup/$name" ]]; then /usr/bin/ditto "$backup/$name" "$base/$name"; fi
    done
    /bin/mkdir -p "$base/logs" "$base/downloads" /usr/local/bin
    [[ "$("$base/push-cli" --version)" == 'push-cli v1.16.7' ]] || { echo 'PUSH repair did not install the expected client.' >&2; exit 1; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$base/push-ui.app/Contents/Info.plist")" == 1.16.7 ]] || { echo 'PUSH repair did not install the matching popup UI.' >&2; exit 1; }
    if [[ ! -e "$base/config.yaml" && ! -e "$base/config.json" ]]; then
        /bin/cp "$base/Local-Test/default-config.yaml" "$base/config.yaml"
        /usr/sbin/chown root:wheel "$base/config.yaml"; /bin/chmod 644 "$base/config.yaml"
    fi
    if [[ -e /usr/local/bin/push-cli && ! -L /usr/local/bin/push-cli ]]; then /bin/rm /usr/local/bin/push-cli; fi
    /bin/ln -sfn "$base/push-cli" /usr/local/bin/push-cli
    echo 'PUSH 1.16.7 client and popup UI repaired and verified. No uninstall, monitor change or macOS installation was performed.'
    """+"\n"
}
