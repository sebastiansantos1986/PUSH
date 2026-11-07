// ==============================================================================
// PUSH - Proactive Update Scheduling Helper
//
// Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
//
// Component: CLIHelpers.swift
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// ==============================================================================

// CLIHelpers.swift — Shared utilities for push-cli

import Foundation

// MARK: - Output
// All output is mirrored to the log file so every run is fully auditable.

func cliPrint(_ msg: String) {
    RuntimeHealthScope.note(msg)
    print(msg)
    writeToLog(msg)
}
func cliSuccess(_ msg: String) {
    RuntimeHealthScope.note(msg)
    print("\u{001B}[32m✓\u{001B}[0m \(msg)")
    writeToLog("✓ \(msg)")
}
func cliWarning(_ msg: String) {
    RuntimeHealthScope.note(msg)
    print("\u{001B}[33m⚠\u{001B}[0m \(msg)")
    writeToLog("⚠ \(msg)")
}
func cliError(_ msg: String) {
    RuntimeHealthScope.note(msg,error:true)
    fputs("\u{001B}[31m✗\u{001B}[0m \(msg)\n", stderr)
    writeToLog("✗ \(msg)")
}
func cliInfo(_ label: String, _ value: String) {
    print("  \u{001B}[2m\(label.padding(toLength: 24, withPad: " ", startingAt: 0))\u{001B}[0m \(value)")
    writeToLog("  \(label.padding(toLength: 24, withPad: " ", startingAt: 0)) \(value)")
}
func cliSection(_ title: String) {
    print("\n\u{001B}[1m\(title)\u{001B}[0m")
    writeToLog("\n\(title)")
}
func cliDivider() {
    let line = String(repeating: "─", count: 50)
    print(line)
    writeToLog(line)
}

/// Write a plain-text line to the log file (no ANSI codes).
private func writeToLog(_ message: String) {
    let ts   = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let dir = (logPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: logPath),
       let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(data); h.closeFile()
    } else {
        try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
    }
}

// MARK: - Paths

let managedBase = "/Library/Management/PUSH"

var realUserHome: String {
    if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"],
       !sudoUser.isEmpty {
        return "/Users/\(sudoUser)"
    }
    return NSHomeDirectory()
}

var userBase: String {
    (realUserHome as NSString)
        .appendingPathComponent("Library/Application Support/PUSH")
}

var resolvedConfigPath: String? {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--config"), args.count > idx + 1 {
        return args[idx + 1]
    }
    let candidates = [
        "\(managedBase)/config.yaml",
        "\(managedBase)/config.json",
        "\(userBase)/config.yaml",
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0) }
}

var statePath: String {
    FileManager.default.fileExists(atPath: managedBase)
        ? "\(managedBase)/state.json"
        : "\(userBase)/state.json"
}

var logPath: String {
    FileManager.default.fileExists(atPath: managedBase)
        ? "\(managedBase)/logs/push.log"
        : "\(userBase)/logs/push.log"
}

// MARK: - Config / State I/O

func loadConfig() throws -> CLIConfig {
    guard let path = resolvedConfigPath else { throw CLIError.configNotFound }
    return try CLIConfig.load(from: path)
}

/// Action paths must not turn unreadable state into an empty, apparently idle state.
func loadStateForAction(from path: String = statePath) throws -> CLIDeferralState {
    guard FileManager.default.fileExists(atPath: path) else { return CLIDeferralState() }
    return try JSONDecoder().decode(CLIDeferralState.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

func loadState() -> CLIDeferralState {
    guard let data  = FileManager.default.contents(atPath: statePath),
          let state = try? JSONDecoder().decode(CLIDeferralState.self, from: data)
    else { return CLIDeferralState() }
    return state
}

func saveState(_ state: CLIDeferralState) throws {
    let dir = (statePath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(state)
    try data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
}

// MARK: - Shell

@discardableResult
func shell(_ cmd: String) -> (output: String, status: Int32) {
    let (out, status) = runDirect("/bin/zsh", ["-c", cmd])
    return (out.trimmingCharacters(in: .whitespacesAndNewlines), status)
}

// MARK: - Logging
// cliLog writes debug detail to the log file only (not shown on stdout).
// cliPrint/cliSuccess/cliInfo etc. write to both stdout AND the log.

func cliLog(_ message: String) {
    let ts   = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] [DEBUG] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let dir = (logPath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: logPath),
       let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(data); h.closeFile()
    } else {
        try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
    }
}

// MARK: - Errors

enum CLIError: Error, LocalizedError {
    case configNotFound
    case configParseFailed(String)
    case requiresRoot
    case invalidKey(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .configNotFound:           return "No config found at \(managedBase)/config.yaml"
        case .configParseFailed(let m): return "Config parse failed: \(m)"
        case .requiresRoot:             return "This command requires root. Use sudo."
        case .invalidKey(let k):        return "Unknown config key: '\(k)'"
        case .invalidValue(let v):      return "Invalid value: '\(v)'"
        }
    }
}

// MARK: - Version helpers

func currentMacOSVersion() -> String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return v.patchVersion == 0
        ? "\(v.majorVersion).\(v.minorVersion)"
        : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}

/// Numeric version comparison — handles 15.10 > 15.9 correctly.
func versionGTE(_ a: String, _ b: String) -> Bool {
    let av = a.split(separator: ".").compactMap { Int($0) }
    let bv = b.split(separator: ".").compactMap { Int($0) }
    for i in 0..<max(av.count, bv.count) {
        let ai = i < av.count ? av[i] : 0
        let bi = i < bv.count ? bv[i] : 0
        if ai < bi { return false }
        if ai > bi { return true }
    }
    return true
}

func isValidVersion(_ v: String) -> Bool {
    v.split(separator: ".").compactMap { Int($0) }.count >= 2
}

func formatInterval(_ seconds: Int) -> String {
    if seconds < 3600  { return "\(seconds / 60) minutes" }
    if seconds < 86400 { return "\(seconds / 3600) hours" }
    return "\(seconds / 86400) days"
}

func argValue(_ flag: String, in args: [String]) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

// MARK: - Bootstrap Token

/// Check if Bootstrap Token is escrowed to MDM.
/// Returns true if the machine can use Bootstrap Token for softwareupdate auth.
func isBootstrapTokenEscrowed() -> Bool {
    let (output, status) = shell("profiles status -type bootstraptoken 2>/dev/null")
    guard status == 0 else {
        cliLog("[Auth] Bootstrap Token check failed — profiles command unavailable")
        return false
    }
    let escrowed = output.lowercased().contains("bootstrap token escrowed to server: yes")
    cliLog("[Auth] Bootstrap Token escrowed: \(escrowed)")
    return escrowed
}

/// Check if the console user has a Secure Token.
/// Required for softwareupdate --stdinpass on Apple Silicon.
func consoleUserHasSecureToken() -> Bool {
    guard let user = consoleUser() else { return false }
    let (output, _) = shell("sysadminctl -secureTokenStatus \"\(user.name)\" 2>&1")
    let hasToken = output.lowercased().contains("enabled")
    cliLog("[Auth] Secure Token for \(user.name): \(hasToken ? "enabled" : "disabled")")
    return hasToken
}

/// Smart auth selection for Apple Silicon installs.
///
/// Returns the best available auth method for the *caller's* install path:
///   .bootstrapToken  — Only returned when allowBootstrapToken == true AND the
///                       Bootstrap Token is escrowed. This is correct ONLY for
///                       installs driven via MDM (mdmclient ScheduleOSUpdate).
///                       Direct `startosinstall` or `softwareupdate --install`
///                       calls still need a Secure-Token admin password even
///                       when a Bootstrap Token is escrowed — do NOT pass
///                       allowBootstrapToken: true from those paths.
///   .keychain        — Password stored in System Keychain
///   .config          — Password in config.yaml (plain text fallback)
///   .unavailable     — Leave the installation for IT; never prompt the user
enum AuthMethod: String {
    case bootstrapToken    = "Bootstrap Token (MDM)"
    case laps              = "Jamf LAPS"
    case keychain          = "System Keychain"
    case config            = "Config file"
    case unavailable       = "IT authorization needed (no user prompts)"
}

func selectAuthMethod(config: CLIConfig, allowBootstrapToken: Bool = false) -> AuthMethod {
    guard isAppleSilicon() else { return .unavailable } // Intel install paths do not request credentials

    // Bootstrap Token only when caller opts in (MDM-driven installs only).
    if allowBootstrapToken && isBootstrapTokenEscrowed() {
        return .bootstrapToken
    }
    // LAPS: zero-touch retrieval from Jamf at install time.
    if config.jamf.laps.enabled
        && !config.jamf.url.isEmpty
        && !config.jamf.laps.clientId.isEmpty
        && !config.jamf.laps.accountName.isEmpty
        && (jamfLapsKeychainSecretExists() || !config.jamf.laps.clientSecret.isEmpty)
    {
        return .laps
    }
    if !config.auth.localAccount.isEmpty && keychainPasswordExists() {
        return .keychain
    }
    if !config.auth.localAccount.isEmpty && !config.auth.localPassword.isEmpty {
        return .config
    }
    return .unavailable
}

// MARK: - Console user (for GUI session launching)

func consoleUser() -> (name: String, uid: Int)? {
    let (name, _) = shell("stat -f '%Su' /dev/console")
    guard !name.isEmpty, name != "root", name != "loginwindow" else { return nil }
    let (uidStr, _) = shell("id -u \"\(name)\"")
    guard let uid = Int(uidStr) else { return nil }
    return (name, uid)
}

/// Launch push-ui non-blocking in the console user's GUI session (for toasts/installing).
func launchUIAsUser(_ cmd: String) {
    guard let user = consoleUser() else {
        NotificationHistory.record(state:NotificationHistoryPolicy.state(in:cmd),outcome:"delayed",reason:"No desktop session for nonblocking notification",retry:Date().addingTimeInterval(300))
        cliLog("[UI] No console session; notification remains queued")
        return
    }
    NotificationHistory.record(state:NotificationHistoryPolicy.state(in:cmd),outcome:"requested",reason:"Nonblocking UI launch requested; window appearance is unconfirmed",uid:user.uid)
    cliLog("[UI] Launching as \(user.name) (uid \(user.uid)): \(cmd)")

    // Use open(1) to launch the app in the user's GUI session — this is the most
    // reliable way to surface a window from a root LaunchDaemon on modern macOS.
    // We write the arguments to a temp file and pass them via --args.
    let uiBinary = resolveUIBinary()
    let appBundle = uiBinary
        .components(separatedBy: "/Contents/MacOS/").first ?? ""

    // Extract --state and other args from cmd string for open --args
    var openArgs = ""
    if let range = cmd.range(of: uiBinary + "\" ") {
        openArgs = String(cmd[range.upperBound...])
    } else if let range = cmd.range(of: "push-ui\" ") {
        openArgs = String(cmd[range.upperBound...])
    }

    if !appBundle.isEmpty && appBundle.hasSuffix(".app") {
        // Launch via open -a so macOS properly connects it to the user's session
        let openCmd = "launchctl asuser \(user.uid) /usr/bin/open -a \"\(appBundle)\" --args \(openArgs) > /dev/null 2>&1 &"
        cliLog("[UI] open command: \(openCmd)")
        shell(openCmd)
    } else {
        // Fallback to direct launch
        shell("launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \(cmd) > /dev/null 2>&1 &")
    }
}

/// Launch push-ui BLOCKING in the console user's GUI session.
/// Returns the exit code. Times out after timeoutMinutes (default 15).
func runUIBlocking(_ cmd: String, timeoutMinutes: Int = 15, onDisplayed: (() -> Void)? = nil) -> Int32 {
    let console=consoleUser()
    let audit=NotificationAttempt(command:cmd,uid:console?.uid)
    guard let user=console else{return audit.finish(101)}
    let fm = FileManager.default
    let session = URL(fileURLWithPath:"/private/tmp/push-ui-session-" + UUID().uuidString)
    let ready = session.appendingPathComponent("ready")
    let log = session.appendingPathComponent("output")
    do {
        try fm.createDirectory(at:session,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        if getuid() == 0 { try fm.setAttributes([.ownerAccountID:NSNumber(value:user.uid)],ofItemAtPath:session.path) }
        else if getuid() != user.uid { try? fm.removeItem(at:session); return audit.finish(101) }
    } catch { return audit.finish(99) }
    defer { try? fm.removeItem(at:session) }
    guard fm.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600]),
          let output = try? FileHandle(forUpdating:log) else { return audit.finish(99) }
    defer { try? output.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath:"/bin/launchctl")
    let command = cmd + " --ready-file " + shellArgument(ready.path)
    process.arguments = ["asuser",String(user.uid),"/usr/bin/sudo","-n","-u",user.name,"--","/bin/zsh","-c","exec " + command]
    process.standardOutput = output; process.standardError = output
    process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch { cliLog("[UI] Could not start GUI session process: \(error.localizedDescription)"); return audit.finish(99) }
    func diagnostic() {
        // Read the original descriptor, not a user-replaceable pathname.
        guard let size = try? output.seekToEnd() else { return }
        try? output.seek(toOffset:size > 1200 ? size - 1200 : 0)
        if let data = try? output.read(upToCount:1200), !data.isEmpty {
            let safe = String(decoding:data,as:UTF8.self).unicodeScalars.filter { $0.value >= 32 && $0.value != 127 || $0 == "\n" }
            cliLog("[UI] Diagnostic: " + String(String.UnicodeScalarView(safe)))
        }
    }
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let end = Date().addingTimeInterval(1)
        while process.isRunning && Date() < end { Thread.sleep(forTimeInterval:0.05) }
        if process.isRunning { kill(process.processIdentifier,SIGKILL) }
        process.waitUntilExit()
    }
    RuntimeHealthScope.phase("openingPrompt","Opening a PUSH prompt")
    let startup = Date().addingTimeInterval(20)
    let timeout = Date().addingTimeInterval(TimeInterval(timeoutMinutes * 60))
    var visible = false
    while process.isRunning {
        if !visible && fm.fileExists(atPath:ready.path) {
            visible = true
            audit.displayed()
            onDisplayed?()
            RuntimeHealthScope.phase("waitingForUser","Waiting for a response to the visible PUSH prompt")
            cliLog("[UI] Window reported visible in the console session")
        }
        if !visible && Date() >= startup {
            stop(); diagnostic()
            cliLog("[UI] Window did not report visible within 20 seconds")
            return audit.finish(103)
        }
        if Date() >= timeout { stop(); diagnostic(); cliLog("[UI] No user response before timeout"); return audit.finish(100) }
        Thread.sleep(forTimeInterval:0.1)
    }
    process.waitUntilExit()
    let reportedVisible = visible || fm.fileExists(atPath:ready.path)
    let result = popupWindowResult(status:process.terminationStatus,reason:process.terminationReason,visible:reportedVisible)
    guard reportedVisible else {
        diagnostic()
        cliLog("[UI] Child exited before reporting a visible window (status \(result))")
        return audit.finish(103)
    }
    if reportedVisible {if !visible {onDisplayed?()};audit.displayed()}
    if result != 0 { diagnostic() }
    return audit.finish(result)
}

// MARK: - push-ui path resolver

func resolveUIBinary() -> String {
    let standard = [
        "\(managedBase)/push-ui.app/Contents/MacOS/push-ui",
        "/usr/local/bin/push-ui.app/Contents/MacOS/push-ui",
    ]
    if let found = standard.first(where: { FileManager.default.fileExists(atPath: $0) }) {
        return found
    }
    // Dev fallback — DerivedData
    let home = realUserHome
    let (derived, _) = shell("find \(home)/Library/Developer/Xcode/DerivedData -path '*/push-ui.app/Contents/MacOS/push-ui' -type f 2>/dev/null | grep -v 'Index.noindex' | grep -v '.dSYM' | head -1")
    if !derived.isEmpty { return derived }
    return "\(managedBase)/push-ui.app/Contents/MacOS/push-ui"
}
