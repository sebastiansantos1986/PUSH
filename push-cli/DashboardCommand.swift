// DashboardCommand.swift — Generate a self-contained HTML compliance dashboard
//
// Usage:
//   push-cli dashboard                  Print HTML to stdout
//   push-cli dashboard --output /tmp/push-dashboard.html
//   push-cli dashboard --open           Generate and open in browser

import Foundation

struct DashboardCommand {
    let args: [String]

    var outputPath: String? { argValue("--output", in: args) }
    var openBrowser: Bool   { args.contains("--open") }

    func run() {
        let config  = (try? loadConfig()) ?? CLIConfig()
        let state   = loadState()
        let current = currentMacOSVersion()
        let target  = config.update.targetVersion
        let host    = friendlyHostname()
        let serial  = machineSerial()
        let compliant = target.isEmpty ? true : versionGTE(current, target)
        let graceActive = state.gracePeriodUntil.map { $0 > Date() } ?? false
        let generatedAt = ISO8601DateFormatter().string(from: Date())

        let deferralsUsed = state.deferralCount
        let deferralsMax  = config.update.maxDeferrals
        let deferralPct   = deferralsMax > 0
            ? Int(Double(deferralsUsed) / Double(deferralsMax) * 100)
            : 0

        let daysUntilDeadline: Int? = config.deadlineDate.map {
            max(0, Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0)
        }

        let html = generateHTML(
            host: host, serial: serial,
            current: current, target: target,
            compliant: compliant, graceActive: graceActive,
            deferralsUsed: deferralsUsed, deferralsMax: deferralsMax,
            deferralPct: deferralPct,
            daysUntilDeadline: daysUntilDeadline,
            deadline: config.update.deadline,
            releaseType: config.update.releaseType,
            pastDeadline: config.isPastDeadline,
            installStarted: state.installStarted,
            installCompleted: state.installCompleted,
            deferralReasons: state.deferralReasons,
            accentHex: config.ui.accentColorHex,
            orgName: config.ui.orgName,
            generatedAt: generatedAt
        )

        if let path = outputPath {
            do {
                try html.write(toFile: path, atomically: true, encoding: .utf8)
                cliSuccess("Dashboard saved to \(path)")
                if openBrowser { shell("open \"\(path)\"") }
            } catch {
                cliError("Failed to write: \(error.localizedDescription)"); exit(1)
            }
        } else if openBrowser {
            let tmp = "/tmp/push-dashboard-\(Int(Date().timeIntervalSince1970)).html"
            try? html.write(toFile: tmp, atomically: true, encoding: .utf8)
            shell("open \"\(tmp)\"")
            cliSuccess("Dashboard opened in browser")
        } else {
            print(html)
        }
    }

    private func generateHTML(
        host: String, serial: String,
        current: String, target: String,
        compliant: Bool, graceActive: Bool,
        deferralsUsed: Int, deferralsMax: Int, deferralPct: Int,
        daysUntilDeadline: Int?, deadline: String, releaseType: String,
        pastDeadline: Bool, installStarted: Bool, installCompleted: Bool,
        deferralReasons: [String], accentHex: String, orgName: String,
        generatedAt: String
    ) -> String {
        let statusColor  = compliant ? "#30d158" : "#ff453a"
        let statusLabel  = compliant ? "Compliant" : "Non-Compliant"
        let statusBg     = compliant ? "rgba(48,209,88,0.12)" : "rgba(255,69,58,0.12)"
        let deferColor   = deferralPct > 66 ? "#ff453a" : deferralPct > 33 ? "#ff9500" : "#30d158"
        let accent       = accentHex.isEmpty ? "#0A84FF" : accentHex
        let org          = orgName.isEmpty ? "PUSH" : orgName
        let deadlineStr  = deadline.isEmpty ? "Not set" : deadline.prefix(10).description
        let daysStr      = daysUntilDeadline.map { "\($0) days" } ?? "—"
        let reasonsHTML  = deferralReasons.isEmpty
            ? "<span style='color:#888'>None recorded</span>"
            : deferralReasons.map { "<span style='background:#2a2a2e;padding:3px 8px;border-radius:4px;font-size:12px'>\($0)</span>" }.joined(separator: " ")

        return """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PUSH — \(host)</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif;background:#0a0a0c;color:#e0e0e4;min-height:100vh;padding:32px}
h1{font-size:22px;font-weight:600;color:#fff;margin-bottom:4px}
.subtitle{font-size:13px;color:#666;margin-bottom:32px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px;margin-bottom:24px}
.card{background:#1c1c1e;border:1px solid rgba(255,255,255,0.08);border-radius:14px;padding:20px}
.card-title{font-size:11px;color:#666;text-transform:uppercase;letter-spacing:.6px;margin-bottom:14px}
.stat{font-size:36px;font-weight:700;letter-spacing:-1px;margin-bottom:4px}
.stat-label{font-size:12px;color:#888}
.status-badge{display:inline-flex;align-items:center;gap:8px;padding:8px 16px;border-radius:20px;font-size:14px;font-weight:600;background:\(statusBg);color:\(statusColor);margin-bottom:20px}
.dot{width:8px;height:8px;border-radius:50%;background:\(statusColor)}
.row{display:flex;justify-content:space-between;align-items:center;padding:10px 0;border-bottom:1px solid rgba(255,255,255,0.05)}
.row:last-child{border-bottom:none}
.row-label{font-size:13px;color:#888}
.row-value{font-size:13px;font-weight:500;color:#e0e0e4;font-family:'SF Mono',monospace}
.bar-bg{height:6px;background:rgba(255,255,255,0.08);border-radius:3px;margin:8px 0 4px}
.bar-fill{height:6px;border-radius:3px;background:\(deferColor);width:\(deferralPct)%;transition:width .6s ease}
.version-row{display:flex;align-items:center;gap:12px;margin-top:8px}
.version-chip{background:#111;border:1px solid rgba(255,255,255,0.08);border-radius:8px;padding:8px 14px}
.chip-label{font-size:10px;color:#555;text-transform:uppercase;letter-spacing:.4px;margin-bottom:3px}
.chip-value{font-size:13px;font-family:'SF Mono',monospace;font-weight:500}
.arrow{color:#444;font-size:16px}
.footer{font-size:11px;color:#444;margin-top:24px;text-align:center}
.accent{color:\(accent)}
.tag{display:inline-block;background:#2a2a2e;padding:3px 8px;border-radius:4px;font-size:12px;margin:2px}
</style>
</head>
<body>
<h1>\(org) — Compliance Report</h1>
<p class="subtitle">Generated \(generatedAt) · \(host) · \(serial)</p>

<div class="status-badge"><div class="dot"></div>\(statusLabel)</div>

<div class="grid">

  <div class="card">
    <div class="card-title">macOS Version</div>
    <div class="version-row">
      <div class="version-chip">
        <div class="chip-label">Current</div>
        <div class="chip-value">\(current)</div>
      </div>
      <div class="arrow">→</div>
      <div class="version-chip">
        <div class="chip-label">Required</div>
        <div class="chip-value accent">\(target.isEmpty ? "—" : target)</div>
      </div>
    </div>
    <div style="margin-top:16px">
      <div class="row"><span class="row-label">Release type</span><span class="row-value">\(releaseType)</span></div>
      <div class="row"><span class="row-label">Deadline</span><span class="row-value">\(deadlineStr)</span></div>
      <div class="row"><span class="row-label">Days remaining</span><span class="row-value \(pastDeadline ? "" : "")">\(pastDeadline ? "⚠ Passed" : daysStr)</span></div>
      \(graceActive ? "<div class=\"row\"><span class=\"row-label\">Grace period</span><span class=\"row-value\" style=\"color:#ff9500\">Active</span></div>" : "")
    </div>
  </div>

  <div class="card">
    <div class="card-title">Deferrals</div>
    <div class="stat" style="color:\(deferColor)">\(deferralsUsed)<span style="font-size:18px;color:#555">/\(deferralsMax)</span></div>
    <div class="stat-label">deferrals used</div>
    <div class="bar-bg"><div class="bar-fill"></div></div>
    <div style="font-size:11px;color:#555">\(deferralPct)% of limit</div>
    \(!deferralReasons.isEmpty ? "<div style='margin-top:14px'><div class='card-title' style='margin-bottom:8px'>Reasons given</div>\(reasonsHTML)</div>" : "")
  </div>

  <div class="card">
    <div class="card-title">Install Status</div>
    <div class="row"><span class="row-label">Install started</span><span class="row-value" style="color:\(installStarted ? "#30d158" : "#888")">\(installStarted ? "Yes ✓" : "No")</span></div>
    <div class="row"><span class="row-label">Install completed</span><span class="row-value" style="color:\(installCompleted ? "#30d158" : "#888")">\(installCompleted ? "Yes ✓" : "No")</span></div>
    <div class="row"><span class="row-label">Hostname</span><span class="row-value">\(host)</span></div>
    <div class="row"><span class="row-label">Serial</span><span class="row-value">\(serial)</span></div>
  </div>

</div>

<p class="footer">PUSH v1.0.0 · \(generatedAt)</p>
</body>
</html>
"""
    }

    private func friendlyHostname() -> String {
        let (name, _) = shell("scutil --get ComputerName 2>/dev/null")
        if !name.isEmpty { return name }
        return ProcessInfo.processInfo.hostName
    }

    private func machineSerial() -> String {
        let (out, _) = shell("system_profiler SPHardwareDataType 2>/dev/null | awk '/Serial Number/{print $NF}'")
        return out.isEmpty ? "unknown" : out
    }
}

// MARK: - CLIConfig deadline helper

extension CLIConfig {
    var deadlineDate: Date? {
        guard !update.deadline.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                             .withColonSeparatorInTime]
        return fmt.date(from: update.deadline)
            ?? ISO8601DateFormatter().date(from: update.deadline)
    }
}
