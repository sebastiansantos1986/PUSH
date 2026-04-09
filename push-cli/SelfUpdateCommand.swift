// SelfUpdateCommand.swift — PUSH self-update mechanism
//
// Checks GitHub releases for a newer version of push-cli.
// Downloads and replaces itself in /Library/Management/PUSH/
// Configurable via config.yaml update.selfUpdateURL

import Foundation

struct SelfUpdateCommand {
    let args: [String]
    var checkOnly: Bool { args.contains("--check") }
    var force:     Bool { args.contains("--force") }

    // MARK: - Version info — shared with main.swift's cliVersion
    // Do NOT hardcode a second version string here; use the global.
    static var currentVersion: String { cliVersion }

    func run() {
        guard getuid() == 0 || checkOnly else {
            cliError("self-update requires root. Run: sudo push-cli self-update")
            exit(1)
        }

        guard let config = try? loadConfig() else {
            cliError("Cannot load config"); exit(1)
        }

        let releaseURL = config.update.selfUpdateURL.isEmpty
            ? "https://api.github.com/repos/your-org/push/releases/latest"
            : config.update.selfUpdateURL

        cliSection("🔄 PUSH Self-Update")
        cliInfo("Current version:", Self.currentVersion)
        cliInfo("Release URL:",     releaseURL)
        cliPrint("")

        guard let release = fetchLatestRelease(url: releaseURL) else {
            cliError("Could not fetch release info from \(releaseURL)")
            cliPrint("Check auto.selfUpdateURL in config or your network connection.")
            exit(1)
        }

        cliInfo("Latest version:", release.version)

        if !force && !isNewerVersion(release.version, than: Self.currentVersion) {
            cliSuccess("Already on latest version (\(Self.currentVersion))")
            exit(0)
        }

        if checkOnly {
            if isNewerVersion(release.version, than: Self.currentVersion) {
                cliPrint("Update available: \(Self.currentVersion) → \(release.version)")
                cliPrint("Run: sudo push-cli self-update")
                exit(1) // exit 1 = update available (useful for Jamf EA)
            } else {
                cliSuccess("Up to date")
                exit(0)
            }
        }

        cliPrint("Updating \(Self.currentVersion) → \(release.version)…")

        guard let cliURL = release.cliDownloadURL else {
            cliError("No push-cli binary found in release assets")
            exit(1)
        }

        let tmpPath = "/tmp/push-cli-update"
        let (_, dlStatus) = shell("curl -fsSL \"\(cliURL)\" -o \"\(tmpPath)\"")
        guard dlStatus == 0 else {
            cliError("Download failed"); exit(1)
        }

        shell("chmod +x \"\(tmpPath)\"")

        // Verify it actually runs
        let (ver, verStatus) = shell("\"\(tmpPath)\" --version 2>/dev/null")
        guard verStatus == 0, !ver.isEmpty else {
            cliError("Downloaded binary failed verification"); exit(1)
        }

        let destPath = "\(managedBase)/push-cli"
        shell("cp \"\(tmpPath)\" \"\(destPath)\"")
        shell("chmod +x \"\(destPath)\"")
        shell("chown root:wheel \"\(destPath)\"")
        shell("ln -sf \"\(destPath)\" /usr/local/bin/push-cli")
        shell("rm -f \"\(tmpPath)\"")

        cliSuccess("Updated to \(release.version)")
        cliLog("[SelfUpdate] Updated \(Self.currentVersion) → \(release.version)")
    }

    // MARK: - Fetch release

    private struct ReleaseInfo {
        let version:        String
        let cliDownloadURL: String?
    }

    private func fetchLatestRelease(url: String) -> ReleaseInfo? {
        guard let endpoint = URL(string: url) else { return nil }
        var req = URLRequest(url: endpoint, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("push-cli/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        var result: ReleaseInfo?
        let sema = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sema.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            let tag = (json["tag_name"] as? String ?? "").replacingOccurrences(of: "v", with: "")
            let assets = json["assets"] as? [[String: Any]] ?? []
            let cliAsset = assets.first {
                ($0["name"] as? String ?? "").contains("push-cli")
            }
            let downloadURL = cliAsset?["browser_download_url"] as? String

            result = ReleaseInfo(version: tag, cliDownloadURL: downloadURL)
        }.resume()

        sema.wait()
        return result
    }

    // MARK: - Version comparison

    private func isNewerVersion(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").compactMap { Int($0) }
        let bv = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(av.count, bv.count) {
            let ai = i < av.count ? av[i] : 0
            let bi = i < bv.count ? bv[i] : 0
            if ai > bi { return true }
            if ai < bi { return false }
        }
        return false
    }
}
