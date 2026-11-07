// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
// PUSH actions use the fixed typed user request channel. No privileged shell fallback.
enum PushCLI {
    static let path="/Library/Management/PUSH/push-cli"
    static var isInstalled:Bool {FileManager.default.isExecutableFile(atPath:path)}
}
