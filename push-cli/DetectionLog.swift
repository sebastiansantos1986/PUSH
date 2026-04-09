// DetectionLog.swift — tracks when each macOS version was first detected.
// Stored at /Library/Management/PUSH/detections.json
// Format: { "15.7.5": "2026-04-06T21:00:00Z" }
// Deadline = first detection date + N days, so it never resets between runs.

import Foundation

enum DetectionLog {

    static var logPath: String {
        FileManager.default.fileExists(atPath: managedBase)
            ? "\(managedBase)/detections.json"
            : "\(userBase)/detections.json"
    }

    static func firstSeen(version: String) -> Date? {
        guard let dict = load(), let str = dict[version] else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    static func all() -> [(version: String, date: Date)] {
        guard let dict = load() else { return [] }
        let fmt = ISO8601DateFormatter()
        return dict
            .compactMap { (ver, str) -> (String, Date)? in
                guard let date = fmt.date(from: str) else { return nil }
                return (ver, date)
            }
            .sorted { $0.1 > $1.1 }
    }

    static func record(version: String, date: Date = Date()) {
        var dict = load() ?? [:]
        guard dict[version] == nil else { return }
        dict[version] = ISO8601DateFormatter().string(from: date)
        save(dict)
        cliLog("[DetectionLog] Recorded first detection of \(version)")
    }

    static func remove(version: String) {
        var dict = load() ?? [:]
        dict.removeValue(forKey: version)
        save(dict)
    }

    private static func load() -> [String: String]? {
        guard let data = FileManager.default.contents(atPath: logPath) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static func save(_ dict: [String: String]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        let dir = (logPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
    }
}
