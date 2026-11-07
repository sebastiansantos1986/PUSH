// PUSH — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

struct RuntimeHealthRecord: Codable {
    var module: String
    var source: String
    var startedAt: Date
    var updatedAt: Date
    var finishedAt: Date?
    var phase: String
    var reason: String
    var error: String?
    var userUID: Int?
}
struct RuntimeMonitorIntent: Codable {
    let desired: String
    let changedAt: Date
    let reason: String
}
/// Local, non-secret observations. Failure to save health must never change update behavior.
final class RuntimeHealthScope {
    private static var active: RuntimeHealthScope?
    private let previous: RuntimeHealthScope?
    private var record: RuntimeHealthRecord
    private var ended = false
    init(module: String, scheduled: Bool) {
        previous = Self.active
        let now = Date()
        record = .init(module:module,source:scheduled ? "scheduled":"manual",startedAt:now,updatedAt:now,phase:"checking",reason:"Check started")
        Self.active = self
        save()
    }
    private static func protectedFolder() -> URL? {
        let url = URL(fileURLWithPath:managedBase + "/health")
        do { try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o755]) } catch { return nil }
        var info = stat()
        guard lstat(url.path,&info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == 0, info.st_mode & 0o022 == 0 else { return nil }
        return url
    }
    static func clean(_ text: String) -> String {
        if text.range(of:#"(?i)(bearer\s|password\s*[:=]|secret\s*[:=]|access_token|refresh_token|api[_-]?key\s*[:=]|https?://[^\s]*[@?])"#,options:.regularExpression) != nil { return "Authorization details omitted; review the local PUSH log with IT." }
        return String(String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 })).prefix(600))
    }
    private func save() {
        guard let folder = Self.protectedFolder(), let data = try? JSONEncoder().encode(record) else { return }
        let target = folder.appendingPathComponent(record.module + "-" + record.source + ".json")
        do { try data.write(to:target,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:target.path) } catch {}
    }
    static func note(_ text: String, error: Bool = false) {
        guard let scope = active else { return }
        scope.record.reason = clean(text)
        scope.record.updatedAt = Date()
        if error { scope.record.error = clean(text); scope.record.phase = "failed" }
        scope.save()
    }
    static func phase(_ phase: String, _ reason: String) {
        guard let scope = active else { return }
        scope.record.phase = phase; scope.record.reason = clean(reason); scope.record.updatedAt = Date(); scope.save()
    }
    static func user(_ uid: Int) { active?.record.userUID = uid; active?.save() }
    static func uiResult(_ code: Int32) -> Int32 {
        if code < 0 || [99,101,103].contains(code) { note("A PUSH prompt could not be displayed or failed. No user choice was recorded.",error:true) }
        else { phase("checking",code == 100 ? "Prompt timed out without a user response":"Prompt response received; policy evaluation resumed") }
        return code
    }
    func finish() {
        guard !ended else { return }; ended = true
        record.finishedAt = Date(); record.updatedAt = Date()
        record.phase = record.error == nil ? "completed":"failed"
        if let error = record.error { record.reason = error }
        save()
        if Self.active === self { Self.active = previous }
    }
    static func monitorIntent(_ monitor: String, desired: String, reason: String) {
        guard ["main","entra"].contains(monitor), let folder = protectedFolder(), let data = try? JSONEncoder().encode(RuntimeMonitorIntent(desired:desired,changedAt:Date(),reason:clean(reason))) else { return }
        try? data.write(to:folder.appendingPathComponent("intent-" + monitor + ".json"),options:.atomic)
    }
}
