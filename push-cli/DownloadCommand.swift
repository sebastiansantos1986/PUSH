// DownloadCommand.swift — Download macOS update without installing
//
// Usage:
//   push-cli download                     Auto-detect best method
//   push-cli download --method native     Force softwareupdate
//   push-cli download --method mist       Force mist-cli
//   push-cli download --beta              Include beta builds (mist only)

import Foundation

struct DownloadCommand {
    let args: [String]
    var method: String { argValue("--method", in: args) ?? "auto" }
    var isBeta: Bool   { args.contains("--beta") }

    func run() {
        guard getuid() == 0 else {
            cliError("download requires root. Run: sudo push-cli download"); exit(1)
        }
        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }

        let version = config.update.targetVersion
        guard !version.isEmpty else {
            cliError("No target version set. Run: sudo push-cli config set update.targetVersion <version>"); exit(1)
        }

        cliSection("⬇️  Download macOS \(version)")
        cliInfo("Method:", method)
        cliInfo("Platform:", "\(isAppleSilicon() ? "Apple Silicon" : "Intel") / macOS \(macOSMajor)")

        switch method {
        case "mist":   runMist(config: config, version: version)
        case "native": runNative(config: config, version: version)
        default:       runAuto(config: config, version: version)
        }
    }

    // MARK: - Auto

    private func runAuto(config: CLIConfig, version: String) {
        // Try softwareupdate first; fall back to mist-cli
        cliPrint("Auto-detecting best download method…")
        let (swuOut, _) = shell("/usr/sbin/softwareupdate --list 2>&1")
        let labelOpt = parseSWULabel(version: version, output: swuOut)

        if let label = labelOpt {
            cliInfo("Found via softwareupdate:", label)
            runNativeWithLabel(label: label, config: config)
        } else {
            cliInfo("Not found via softwareupdate — trying mist-cli…", "")
            runMist(config: config, version: version)
        }
    }

    // MARK: - Native (softwareupdate)

    private func runNative(config: CLIConfig, version: String) {
        let (swuOut, _) = shell("/usr/sbin/softwareupdate --list 2>&1")
        guard let label = parseSWULabel(version: version, output: swuOut) else {
            cliError("Version \(version) not found in softwareupdate --list")
            cliPrint("Try: push-cli download --method mist")
            exit(1)
        }
        runNativeWithLabel(label: label, config: config)
    }

    private func runNativeWithLabel(label: String, config: CLIConfig) {
        let user    = consoleUser()
        let pwd     = config.auth.localPassword.isEmpty ? nil : config.auth.localPassword
        let acct    = config.auth.localAccount.isEmpty  ? nil : config.auth.localAccount

        let cmd = softwareupdateDownloadCmd(label: label, password: pwd, account: acct, user: user)
        cliLog("[Download] Running: softwareupdate --download \"\(label)\" [as: \(user?.name ?? "root")]")
        cliPrint("Downloading via softwareupdate… (this may take a while)")

        let (out, status) = shell(cmd)
        if status == 0 {
            cliSuccess("Download complete: \(label)")
        } else {
            cliError("softwareupdate download failed (exit \(status))")
            cliLog("[Download] Output: \(out)")
            exit(1)
        }
    }

    // MARK: - Mist-CLI

    private func runMist(config: CLIConfig, version: String) {
        guard let mist = findMistCLI() else {
            cliError("mist-cli not found at /usr/local/bin/mist or /opt/homebrew/bin/mist")
            cliPrint("Install mist-cli: https://github.com/ninxsoft/mist-cli")
            exit(1)
        }

        // Get the build number for the target version using mist list
        cliPrint("Querying mist-cli for available installers…")
        let listArgs = isBeta ? "--include-betas" : ""
        let (listOut, _) = shell("\"\(mist)\" list installer --output-type csv --no-ansi --compatible \(listArgs) 2>/dev/null")
        guard let build = parseMistBuild(version: version, csv: listOut) else {
            cliError("macOS \(version) not found via mist-cli")
            cliLog("[Download] mist list output:\n\(listOut)")
            exit(1)
        }

        cliInfo("Found build:", build)
        let betaFlag = isBeta ? "--include-betas" : ""
        let appName  = "Install %NAME%.app"
        let dlDir    = "\(managedBase)/downloads"
        shell("mkdir -p \"\(dlDir)\"")

        let cmd = "\"\(mist)\" download installer --force --no-ansi --output-directory \"/Applications\" --compatible \(betaFlag) \"\(build)\" application --application-name \"\(appName)\""
        cliLog("[Download] Running mist-cli: \(cmd)")
        cliPrint("Downloading via mist-cli… (this may take a while)")

        let (_, status) = shell(cmd)
        if status == 0 {
            cliSuccess("Download complete via mist-cli")
        } else {
            cliError("mist-cli download failed (exit \(status))")
            exit(1)
        }
    }

    // MARK: - Helpers

    private func parseSWULabel(version: String, output: String) -> String? {
        var current = ""
        for line in output.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("* Label:") {
                current = t.replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces)
            } else if t.contains("Version: \(version)") && !current.isEmpty {
                return current
            }
        }
        return nil
    }

    private func parseMistBuild(version: String, csv: String) -> String? {
        // CSV columns: Version, Build, Size, Date, ...
        for line in csv.components(separatedBy: "\n") {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 2 else { continue }
            let v = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                           .replacingOccurrences(of: "\"", with: "")
            let b = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
                           .replacingOccurrences(of: "\"", with: "")
            if v == version || v.hasPrefix(version) { return b }
        }
        return nil
    }

    private func findMistCLI() -> String? {
        ["/usr/local/bin/mist", "/opt/homebrew/bin/mist"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}
