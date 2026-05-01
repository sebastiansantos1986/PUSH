// JamfLAPSClient.swift — retrieve the managed local admin password from Jamf Pro
//
// Flow:
//   1) POST /api/oauth/token                          → bearer token (client_credentials)
//   2) GET  /api/v1/computers-inventory/detail?…       → management ID by serial
//   3) GET  /api/v2/local-admin-password/{mgmtId}/account/{user}/password  → password
//
// The API returns a fresh password; Jamf auto-rotates it after the "Rotation After
// Viewing Interval" configured under Settings → Computer Management → Security.
//
// Secret resolution order (highest wins):
//   1. System Keychain (service com.push.autoupdate, account push_jamf_laps_secret)
//   2. config.jamf.laps.clientSecret  (yaml fallback)

import Foundation

// MARK: - Keychain constants for the LAPS API client secret

let kJamfLapsKeychainService  = "com.push.autoupdate"
let kJamfLapsKeychainAccount  = "push_jamf_laps_secret"
private let kJamfLapsKeychainFile = "/Library/Keychains/System.keychain"

func jamfLapsKeychainSecret() -> String? {
    let (out, status) = shell("""
        security find-generic-password \
          -s '\(kJamfLapsKeychainService)' \
          -a '\(kJamfLapsKeychainAccount)' \
          -w '\(kJamfLapsKeychainFile)' 2>/dev/null
        """)
    guard status == 0 else { return nil }
    let v = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return v.isEmpty ? nil : v
}

func jamfLapsKeychainSecretExists() -> Bool {
    let (_, status) = shell("""
        security find-generic-password \
          -s '\(kJamfLapsKeychainService)' \
          -a '\(kJamfLapsKeychainAccount)' \
          '\(kJamfLapsKeychainFile)' 2>/dev/null
        """)
    return status == 0
}

// MARK: - Client

enum JamfLAPSError: Error, CustomStringConvertible {
    case disabled
    case missingConfig(String)
    case network(String)
    case httpStatus(Int, String)
    case parseFailure(String)
    case noMatchingComputer(String)
    case emptyPassword

    var description: String {
        switch self {
        case .disabled:                    return "LAPS not enabled (jamf.laps.enabled=false)"
        case .missingConfig(let f):        return "LAPS config missing: \(f)"
        case .network(let msg):            return "Network error: \(msg)"
        case .httpStatus(let code, let b): return "HTTP \(code): \(b.prefix(200))"
        case .parseFailure(let msg):       return "Parse error: \(msg)"
        case .noMatchingComputer(let s):   return "No Jamf computer found for serial \(s)"
        case .emptyPassword:               return "Jamf returned an empty LAPS password"
        }
    }
}

struct JamfLAPSClient {
    let config: CLIConfig

    /// Public entry point. Returns the current LAPS password for the configured
    /// managed local admin account, or throws with a diagnosable error.
    func fetchPassword() throws -> (username: String, password: String) {
        guard config.jamf.laps.enabled else { throw JamfLAPSError.disabled }

        let urlBase = config.jamf.url.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !urlBase.isEmpty else { throw JamfLAPSError.missingConfig("jamf.url") }

        let clientId = config.jamf.laps.clientId
        guard !clientId.isEmpty else { throw JamfLAPSError.missingConfig("jamf.laps.clientId") }

        let clientSecret = jamfLapsKeychainSecret() ?? config.jamf.laps.clientSecret
        guard !clientSecret.isEmpty else {
            throw JamfLAPSError.missingConfig("jamf.laps.clientSecret (not in Keychain or yaml)")
        }

        let username = config.jamf.laps.accountName
        guard !username.isEmpty else { throw JamfLAPSError.missingConfig("jamf.laps.accountName") }

        let serial = machineSerialNumber()
        guard !serial.isEmpty else { throw JamfLAPSError.missingConfig("serial number (could not detect)") }

        cliLog("[LAPS] Fetching for serial=\(serial) account=\(username)")

        let token = try getOAuthToken(baseURL: urlBase, clientId: clientId, clientSecret: clientSecret)
        let mgmtId = try getManagementId(baseURL: urlBase, token: token, serial: serial)
        let password = try getLapsPassword(baseURL: urlBase, token: token, mgmtId: mgmtId, username: username)

        cliLog("[LAPS] Retrieved password for \(username) (mgmtId=\(mgmtId))")
        return (username, password)
    }

    // MARK: - OAuth

    private func getOAuthToken(baseURL: String, clientId: String, clientSecret: String) throws -> String {
        let urlStr = "\(baseURL)/api/oauth/token"
        let body = "grant_type=client_credentials"
                 + "&client_id=\(urlEncode(clientId))"
                 + "&client_secret=\(urlEncode(clientSecret))"
        let headers = ["Content-Type": "application/x-www-form-urlencoded"]

        let (status, data) = httpRequest(method: "POST", url: urlStr, headers: headers, body: body)
        guard (200..<300).contains(status) else {
            throw JamfLAPSError.httpStatus(status, String(data: data, encoding: .utf8) ?? "")
        }

        guard let obj   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String, !token.isEmpty
        else { throw JamfLAPSError.parseFailure("access_token missing from OAuth response") }
        return token
    }

    // MARK: - Management ID lookup by serial

    private func getManagementId(baseURL: String, token: String, serial: String) throws -> String {
        // Filter by serial number and request only what we need.
        let filter = urlEncode("hardware.serialNumber==\"\(serial)\"")
        let section = urlEncode("GENERAL")
        let urlStr = "\(baseURL)/api/v1/computers-inventory"
                   + "?section=\(section)&page=0&page-size=1&filter=\(filter)"

        let (status, data) = httpRequest(method: "GET", url: urlStr,
                                          headers: ["Authorization": "Bearer \(token)",
                                                    "Accept": "application/json"])
        guard (200..<300).contains(status) else {
            throw JamfLAPSError.httpStatus(status, String(data: data, encoding: .utf8) ?? "")
        }

        guard let obj     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]], let first = results.first
        else { throw JamfLAPSError.parseFailure("computers-inventory results missing") }

        // The field is "managementId" at the top level of each result.
        if let mid = first["managementId"] as? String, !mid.isEmpty { return mid }

        // Some Jamf versions nest it under "general".
        if let general = first["general"] as? [String: Any],
           let mid = general["managementId"] as? String, !mid.isEmpty { return mid }

        throw JamfLAPSError.noMatchingComputer(serial)
    }

    // MARK: - Password fetch

    private func getLapsPassword(baseURL: String, token: String, mgmtId: String, username: String) throws -> String {
        let encUser = urlEncode(username)
        let urlStr = "\(baseURL)/api/v2/local-admin-password/\(mgmtId)/account/\(encUser)/password"

        let (status, data) = httpRequest(method: "GET", url: urlStr,
                                          headers: ["Authorization": "Bearer \(token)",
                                                    "Accept": "application/json"])
        guard (200..<300).contains(status) else {
            throw JamfLAPSError.httpStatus(status, String(data: data, encoding: .utf8) ?? "")
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pw  = obj["password"] as? String
        else { throw JamfLAPSError.parseFailure("password field missing") }

        guard !pw.isEmpty else { throw JamfLAPSError.emptyPassword }
        return pw
    }

    // MARK: - HTTP helper (synchronous, no external deps)

    private func httpRequest(method: String, url: String,
                             headers: [String: String] = [:],
                             body: String? = nil) -> (Int, Data) {
        guard let u = URL(string: url) else { return (0, Data()) }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.timeoutInterval = 30
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body = body { req.httpBody = body.data(using: .utf8) }

        let sem = DispatchSemaphore(value: 0)
        var outStatus = 0
        var outData = Data()
        let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let http = resp as? HTTPURLResponse { outStatus = http.statusCode }
            if let d = data { outData = d }
            sem.signal()
        }
        task.resume()
        sem.wait()
        return (outStatus, outData)
    }

    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

// MARK: - Serial number helper

func machineSerialNumber() -> String {
    let (out, _) = shell("ioreg -l | awk -F'\"' '/IOPlatformSerialNumber/ {print $4}'")
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}
