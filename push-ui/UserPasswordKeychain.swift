// PUSH - Proactive Update Scheduling Helper
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS

import Foundation
import AppKit
import Darwin
let kPushUserPwService = "com.push.userpassword"
@discardableResult
func saveUserPasswordToLoginKeychain(account: String, password: String) -> Bool {
    guard account == NSUserName(), getuid() != 0 else { return false }
    return PushKeychain.save(service: kPushUserPwService, account: account, password: password)
}

/// Runs before AppKit starts. The same signed UI executable owns and reads the entry.
func handleCredentialRequest(_ args: [String]) {
    guard args.count == 3, args[1].hasPrefix("--credential-") else { return }
    guard getuid() != 0, args[2] == NSUserName() else { exit(1) }
    let account = args[2]
    switch args[1] {
    case "--credential-check":
        exit(isTrustedInstallRequester() ? 0:70)
    case "--credential-prompt":
        guard isTrustedInstallRequester() else {exit(70)}
        MainActor.assumeIsolated { runInstallAuthorizationPrompt(account:account) }
    case "--credential-read":
        guard isTrustedInstallRequester() else {exit(70)}
        guard let password = PushKeychain.read(service: kPushUserPwService, account: account) else { exit(1) }
        FileHandle.standardOutput.write(Data(password.utf8))
        exit(0)
    case "--credential-exists":
        exit(PushKeychain.exists(service: kPushUserPwService, account: account) ? 0 : 1)
    case "--credential-delete":
        exit(PushKeychain.delete(service: kPushUserPwService, account: account) ? 0 : 1)
    default: exit(1)
    }
}

/// Presentation-only factory shared with offline visual review. It never reads
/// Keychain, verifies a password, runs a modal window or starts an update.
@MainActor func makeInstallAuthorizationAlert(account:String,fullName:String,icon:NSImage?=nil)->(NSAlert,NSSecureTextField){
    let alert=NSAlert();alert.alertStyle = .informational
    alert.icon=icon ?? Bundle.main.path(forResource:"PUSH",ofType:"icns").flatMap{NSImage(contentsOfFile:$0)} ?? NSApplication.shared.applicationIconImage
    alert.messageText="Authorize your update"
    alert.informativeText="Enter your Mac login password to continue. It will be saved securely for future updates. Cancel leaves the update unstarted."
    alert.addButton(withTitle:"Authorize update");alert.addButton(withTitle:"Cancel")
    let accessory=NSView(frame:NSRect(x:0,y:0,width:320,height:108))
    let identity=NSTextField(wrappingLabelWithString:fullName.isEmpty ? account:fullName+" · "+account)
    identity.frame=NSRect(x:0,y:80,width:320,height:28);identity.font = .systemFont(ofSize:12,weight:.medium);identity.textColor = .secondaryLabelColor
    let field=NSSecureTextField(frame:NSRect(x:0,y:43,width:320,height:28));field.placeholderString="Mac login password";field.font = .systemFont(ofSize:14)
    field.setAccessibilityLabel("Mac login password")
    let privacy=NSTextField(wrappingLabelWithString:"Saved in your login Keychain on this Mac. Never sent to IT.")
    privacy.frame=NSRect(x:0,y:0,width:320,height:32);privacy.font = .systemFont(ofSize:11);privacy.textColor = .secondaryLabelColor
    for view in [identity,field,privacy]{accessory.addSubview(view)}
    alert.accessoryView=accessory
    return (alert,field)
}

/// Local install authorization using the existing PUSH login Keychain store.
/// Legacy passwordPrompt/save-to-keychain routes remain disabled.
@MainActor private func runInstallAuthorizationPrompt(account:String)->Never {
    let app=NSApplication.shared;app.setActivationPolicy(.accessory)
    let (alert,field)=makeInstallAuthorizationAlert(account:account,fullName:NSFullUserName())
    alert.window.initialFirstResponder=field;alert.window.level = .modalPanel
    let timeout=Timer.scheduledTimer(withTimeInterval:600,repeats:false){_ in NSApplication.shared.abortModal()}
    RunLoop.main.add(timeout,forMode:RunLoop.Mode("NSModalPanelRunLoopMode"))
    defer{timeout.invalidate();field.stringValue=""}
    app.activate(ignoringOtherApps:true)
    for attempt in 0..<3 {
        guard alert.runModal() == .alertFirstButtonReturn else {field.stringValue="";Foundation.exit(2)}
        let password=field.stringValue;field.stringValue=""
        guard !password.isEmpty,password.utf8.count<=4096,!password.contains("\n"),!password.contains("\r"),verifyLocalPassword(account:account,password:password) else {
            alert.informativeText=attempt<2 ? "That password could not be verified for \(account). Try your Mac login password again. Your password is stored only in your local login Keychain, not sent to IT.":"Authorization could not be verified. Contact IT for help."
            continue
        }
        guard saveUserPasswordToLoginKeychain(account:account,password:password) else {
            // The password is already verified. Asking for it again cannot fix
            // a locked Keychain or a denied application identity/ACL.
            let failure=NSAlert();failure.alertStyle = .warning
            failure.messageText="Your password was verified, but could not be saved"
            failure.informativeText="PUSH could not update its saved credential in your login Keychain. No update was started. Contact IT to check Keychain access before trying again."
            failure.addButton(withTitle:"Close");failure.runModal()
            Foundation.exit(1)
        }
        guard let data=try? JSONEncoder().encode(InstallAuthorizationReply(account:account,password:password)) else {Foundation.exit(1)}
        FileHandle.standardOutput.write(data);Foundation.exit(0)
    }
    Foundation.exit(1)
}

/// A normal app launch or user LaunchAgent must not be able to ask for a
/// password through this private route. Require the root install launcher and
/// an anonymous output pipe before creating any UI.
private func isTrustedInstallRequester()->Bool {
    var info=proc_bsdinfo(),status=stat()
    let parent=getppid(),size=MemoryLayout<proc_bsdinfo>.size
    guard fstat(STDOUT_FILENO,&status)==0,(status.st_mode & S_IFMT)==S_IFIFO else{return false}
    var path=[CChar](repeating:0,count:Int(MAXPATHLEN)*4)
    guard proc_pidpath(parent,&path,UInt32(path.count))>0 else{return false}
    let uid:UInt32,realUID:UInt32
    if proc_pidinfo(parent,PROC_PIDTBSDINFO,0,&info,Int32(size))==Int32(size) {
        uid=info.pbi_uid;realUID=info.pbi_ruid
    }else {
        // A desktop user may read sudo's executable path while libproc refuses
        // its detailed root process information. Use the kernel's process record
        // as a second identity source; never treat unavailable identity as root.
        var process=kinfo_proc(),length=MemoryLayout<kinfo_proc>.size
        var query:[Int32]=[CTL_KERN,KERN_PROC,KERN_PROC_PID,parent]
        guard sysctl(&query,UInt32(query.count),&process,&length,nil,0)==0,
              length==MemoryLayout<kinfo_proc>.size,process.kp_proc.p_pid==parent else{return false}
        uid=process.kp_eproc.e_ucred.cr_uid;realUID=process.kp_eproc.e_pcred.p_ruid
    }
    guard getppid()==parent else{return false}
    return InstallAuthorizationReply.trustedRequester(uid:uid,realUID:realUID,path:String(cString:path),pipe:true)
}
