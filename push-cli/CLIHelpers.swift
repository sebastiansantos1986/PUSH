// CLIHelpers.swift — Shared utilities for push-cli

import Foundation

// MARK: - Output
// All output is mirrored to the log file so every run is fully auditable.

func cliPrint(_ msg: String) {
    print(msg)
    writeToLog(msg)
}
func cliSuccess(_ msg: String) {
    print("\u{001B}[32m✓\u{001B}[0m \(msg)")
    writeToLog("✓ \(msg)")
}
func cliWarning(_ msg: String) {
    print("\u{001B}[33m⚠\u{001B}[0m \(msg)")
    writeToLog("⚠ \(msg)")
}
func cliError(_ msg: String) {
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
    let p    = Process()
    let pipe = Pipe()
    p.launchPath          = "/bin/zsh"
    p.arguments           = ["-c", cmd]
    p.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
    p.standardOutput      = pipe
    p.standardError       = pipe
    try? p.run()
    p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                     encoding: .utf8) ?? ""
    return (out.trimmingCharacters(in: .whitespacesAndNewlines), p.terminationStatus)
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
///   .prompt          — Must prompt the user
enum AuthMethod: String {
    case bootstrapToken    = "Bootstrap Token (MDM)"
    case userSavedPassword = "User Saved Password"
    case laps              = "Jamf LAPS"
    case keychain          = "System Keychain"
    case config            = "Config file"
    case prompt            = "User prompt"
}

func selectAuthMethod(config: CLIConfig, allowBootstrapToken: Bool = false) -> AuthMethod {
    guard isAppleSilicon() else { return .prompt } // Intel doesn't need auth

    // Bootstrap Token only when caller opts in (MDM-driven installs only).
    if allowBootstrapToken && isBootstrapTokenEscrowed() {
        return .bootstrapToken
    }
    // User-saved login password — top priority for direct CLI installs.
    // Highest priority because it's the user's own credential, always
    // authorized for their own machine. Only valid when the user is
    // actually logged in (login keychain is unlocked).
    if let consoleUser = consoleUser()?.name,
       userPasswordExistsInLoginKeychain(account: consoleUser) {
        return .userSavedPassword
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
    if let pwd = keychainPassword(), !pwd.isEmpty {
        return .keychain
    }
    if !config.auth.localPassword.isEmpty {
        return .config
    }
    return .prompt
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
        shell("nohup \(cmd) > /tmp/push-ui.log 2>&1 &")
        return
    }
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
        let openCmd = "launchctl asuser \(user.uid) /usr/bin/open -a \"\(appBundle)\" --args \(openArgs) > /tmp/push-ui.log 2>&1 &"
        cliLog("[UI] open command: \(openCmd)")
        shell(openCmd)
    } else {
        // Fallback to direct launch
        shell("launchctl asuser \(user.uid) sudo -u \"\(user.name)\" \(cmd) > /tmp/push-ui.log 2>&1 &")
    }
}

/// Launch push-ui BLOCKING in the console user's GUI session.
/// Returns the exit code. Times out after timeoutMinutes (default 15).
func runUIBlocking(_ cmd: String, timeoutMinutes: Int = 15) -> Int32 {
    guard let user = consoleUser() else {
        let (_, s) = shell(cmd); return s
    }

    let pid      = ProcessInfo.processInfo.processIdentifier
    let exitFile = "/tmp/push-ui-exit.\(pid)"
    let wrapper  = "/tmp/push-ui-run.\(pid).sh"

    let script = """
    #!/bin/bash
    \(cmd)
    echo $? > "\(exitFile)"
    """
    do {
        try script.write(toFile: wrapper, atomically: true, encoding: .utf8)
    } catch {
        cliLog("[UI] Cannot write wrapper: \(error)")
        let (_, s) = shell(cmd); return s
    }
    shell("chmod +x \"\(wrapper)\"")
    shell("launchctl asuser \(user.uid) sudo -u \"\(user.name)\" /bin/bash \"\(wrapper)\" &")

    let timeout = Date().addingTimeInterval(TimeInterval(timeoutMinutes * 60))
    while !FileManager.default.fileExists(atPath: exitFile) {
        guard Date() < timeout else {
            cliLog("[UI] runUIBlocking timed out after \(timeoutMinutes) minutes")
            break
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    let exitStr  = (try? String(contentsOfFile: exitFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "2"
    let exitCode = Int32(exitStr) ?? 2
    shell("rm -f \"\(wrapper)\" \"\(exitFile)\" 2>/dev/null")
    cliLog("[UI] Exit code: \(exitCode)")
    return exitCode
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
