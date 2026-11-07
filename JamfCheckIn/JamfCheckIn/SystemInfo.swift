// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import IOKit
import IOKit.ps
import Darwin

struct DeviceInfo: Sendable {
    var osVersion: String = "—"
    var diskUsedBytes: Int64 = 0
    var diskTotalBytes: Int64 = 0
    var hasBattery: Bool = false
    var batteryPercent: Int? = nil
    var batteryHealth: String? = nil
    var batteryMaxCapacityPercent: Int? = nil
    var batteryCycleCount: Int? = nil
    var bootTime: Date? = nil
    var fileVault: String = "Unknown"
    var gatekeeper: String = "Unknown"
    var sip: String = "Unknown"
    var firewall: String = "Unknown"
    var enrollment: String = "Unknown"
    var jssURL: String? = nil
    var lastInventory: Date? = nil
    var serialNumber: String = "—"
    var model: String = "—"
    var computerName: String = "—"
    var currentUser: String = "—"
    var localIP: String = "—"
}

enum SystemInfo {
    static func gather(logContent: String) -> DeviceInfo {
        var info = DeviceInfo()
        info.osVersion = osVersionString()
        if let disk = diskUsage() {
            info.diskUsedBytes = disk.used
            info.diskTotalBytes = disk.total
        }
        let battery = batteryInfo()
        info.hasBattery = battery.present
        info.batteryPercent = battery.percent
        info.batteryHealth = battery.health
        let detail = batteryHealthDetail()
        info.batteryMaxCapacityPercent = detail.maxPct
        info.batteryCycleCount = detail.cycles
        info.bootTime = bootTime()
        info.fileVault = fileVaultStatus()
        info.gatekeeper = gatekeeperStatus()
        info.sip = sipStatus()
        info.firewall = firewallStatus()
        info.enrollment = enrollmentStatus()
        info.jssURL = jamfServerURL()
        info.lastInventory = lastInventoryDate(in: logContent)
        info.serialNumber = serialNumber()
        info.model = hardwareModel()
        info.computerName = computerName()
        info.currentUser = NSUserName()
        info.localIP = localIPAddress() ?? "—"
        return info
    }

    static func osVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let base = v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
        let build = Shell.run("/usr/bin/sw_vers", ["-buildVersion"])
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        return build.isEmpty ? "macOS \(base)" : "macOS \(base) (\(build))"
    }

    static func diskUsage() -> (used: Int64, total: Int64)? {
        let url = URL(fileURLWithPath: "/")
        guard let vals = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]), let total = vals.volumeTotalCapacity else { return nil }
        let available = vals.volumeAvailableCapacityForImportantUsage ?? 0
        let totalBytes = Int64(total)
        return (max(0, totalBytes - available), totalBytes)
    }

    static func batteryInfo() -> (present: Bool, percent: Int?, health: String?) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return (false, nil, nil) }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if (desc[kIOPSTypeKey as String] as? String) == (kIOPSInternalBatteryType as String) {
                let percent = desc[kIOPSCurrentCapacityKey as String] as? Int
                let health = desc[kIOPSBatteryHealthKey as String] as? String
                return (true, percent, health)
            }
        }
        return (false, nil, nil)
    }

    static func batteryHealthDetail() -> (maxPct: Int?, cycles: Int?) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }

        func intProp(_ key: String) -> Int? {
            guard let ref = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0
            ) else { return nil }
            return ref.takeRetainedValue() as? Int
        }

        let cycles = intProp("CycleCount")
        let design = intProp("DesignCapacity")
        let rawMax = intProp("AppleRawMaxCapacity")
            ?? intProp("NominalChargeCapacity")
            ?? intProp("MaxCapacity")

        var maxPct: Int? = nil
        if let design, design > 0, let rawMax {
            maxPct = Int((Double(rawMax) / Double(design) * 100.0).rounded())
        }
        return (maxPct, cycles)
    }

    static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, u_int(mib.count), &tv, &size, nil, 0) == 0, tv.tv_sec != 0
        else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
    }

    static func fileVaultStatus() -> String {
        let out = Shell.run("/usr/bin/fdesetup", ["status"]).output.lowercased()
        if out.contains("filevault is on") { return "On" }
        if out.contains("filevault is off") { return "Off" }
        return "Unknown"
    }

    static func gatekeeperStatus() -> String {
        let out = Shell.run("/usr/sbin/spctl", ["--status"]).output.lowercased()
        if out.contains("assessments enabled") { return "On" }
        if out.contains("assessments disabled") { return "Off" }
        return "Unknown"
    }

    static func sipStatus() -> String {
        let out = Shell.run("/usr/bin/csrutil", ["status"]).output.lowercased()
        if out.contains("enabled") { return "On" }
        if out.contains("disabled") { return "Off" }
        return "Unknown"
    }

    static func firewallStatus() -> String {
        let out = Shell.run(
            "/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"]
        ).output.lowercased()
        if out.contains("state = 1") || out.contains("state = 2") || out.contains("enabled") { return "On" }
        if out.contains("state = 0") || out.contains("disabled") { return "Off" }
        return "Unknown"
    }

    static func enrollmentStatus() -> String {
        let result = Shell.run("/usr/bin/profiles", ["status", "-type", "enrollment"])
        guard result.status == 0, !result.output.isEmpty else { return "Unknown" }
        for line in result.output.split(whereSeparator: \.isNewline)
        where line.localizedCaseInsensitiveContains("MDM enrollment") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return "Unknown"
    }

    static func jamfServerURL() -> String? {
        let path = "/Library/Preferences/com.jamfsoftware.jamf.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
              ) as? [String: Any]
        else { return nil }
        return plist["jss_url"] as? String
    }

    static func lastInventoryDate(in content: String) -> Date? {
        let markers = ["Submitting data to", "Sending reported data", "Submitting log to"]
        let lines = content.split(whereSeparator: \.isNewline)
        for line in lines.reversed() where markers.contains(where: { line.contains($0) }) {
            if let date = JamfMonitor.syslogDate(from: String(line)) { return date }
        }
        return nil
    }

    static func serialNumber() -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return "—" }
        defer { IOObjectRelease(service) }
        if let ref = IORegistryEntryCreateCFProperty(
            service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0
        ), let serial = ref.takeRetainedValue() as? String {
            return serial
        }
        return "—"
    }

    static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "—" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let model = String(cString: buffer)
        return model.isEmpty ? "—" : model
    }

    static func computerName() -> String {
        let name = Shell.run("/usr/sbin/scutil", ["--get", "ComputerName"])
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return Host.current().localizedName ?? "—"
    }

    static func localIPAddress() -> String? {
        var primary: String?
        var fallback: String?
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor = ifaddrPtr
        while let entry = cursor {
            let flags = Int32(entry.pointee.ifa_flags)
            let isUpRunning = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUpRunning, !isLoopback, let addr = entry.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    let name = String(cString: entry.pointee.ifa_name)
                    if name == "en0" { primary = ip }
                    else if fallback == nil { fallback = ip }
                }
            }
            cursor = entry.pointee.ifa_next
        }
        return primary ?? fallback
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return (task.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (-1, "")
        }
    }

    @discardableResult
    static func runAdmin(_ command: String) -> (status: Int32, output: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", script])
    }
}
