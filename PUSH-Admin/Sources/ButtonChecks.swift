// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
struct PopupButtonCheck: Identifiable {
    let id = UUID()
    let date = Date()
    let state: String
    let action: String
    let exitCode: Int32?
    let automatic: Bool
}
