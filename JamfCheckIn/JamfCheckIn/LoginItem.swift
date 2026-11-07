// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    @Published var isEnabled = false
    @Published var available = true
    @Published var managedByDeployment=false

    init() { refresh() }

    func refresh() {
        let path="/Library/LaunchAgents/com.sebastianitconsulting.jamfcheckin.plist"
        let data=try? Data(contentsOf:URL(fileURLWithPath:path))
        let agent=data.flatMap{try? PropertyListSerialization.propertyList(from:$0,format:nil)} as? [String:Any]
        managedByDeployment=agent?["Label"] as? String == "com.sebastianitconsulting.jamfcheckin" && agent?["ProgramArguments"] as? [String] == ["/Applications/JamfCheckIn.app/Contents/MacOS/JamfCheckIn"]
        isEnabled = managedByDeployment || SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        refresh();guard !managedByDeployment else{return}
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            available = false
        }
        refresh()
    }
}
