// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum HardwareSupportState:String,Codable {case supported,unsupported,unknown}
struct HardwareIdentity:Codable {
    var model:String
    var deviceKeys:[String]
    var appleSilicon:Bool?=nil
}
struct AppleHardwareResult:Codable {
    var state:HardwareSupportState,targetMajor:Int?,model:String,reason:String
    var source="https://gdmf.apple.com/v2/pmv"
    var checkedAt:Date
    func notice(debug:Bool=false)->SinglePopupNotice {
        var value=SinglePopupNotice(title:state == .unsupported ? "This Mac cannot upgrade to macOS \(targetMajor ?? 0)":"Compatibility could not be verified",message:reason+"\n\nContact IT before proceeding. This result is about the selected major macOS release, not every available update.")
        value.style="warning";value.debug=debug;return value
    }
}
struct AppleHardwareCatalog:Codable {
    struct Release:Codable {var version:String,posted:Date,expires:Date,devices:[String]}
    var fetchedAt:Date
    var source="https://gdmf.apple.com/v2/pmv"
    var releases:[Release]
    static func major(_ version:String)->Int? {
        let parts=version.split(separator:".",omittingEmptySubsequences:false)
        guard (1...3).contains(parts.count),parts.allSatisfy({!$0.isEmpty && $0.utf8.allSatisfy{(48...57).contains($0)}}) else{return nil}
        return Int(parts[0])
    }
    static func fromApple(_ data:Data,now:Date=Date())throws->Self {
        guard data.count<16777216,let root=(try JSONSerialization.jsonObject(with:data)) as? [String:Any],let sets=root["PublicAssetSets"] as? [String:Any],let rows=sets["macOS"] as? [[String:Any]] else {throw MajorUpgradeDemoError.invalid("Apple's compatibility catalog format could not be verified.")}
        let date=DateFormatter();date.locale=Locale(identifier:"en_US_POSIX");date.timeZone=TimeZone(secondsFromGMT:0);date.dateFormat="yyyy-MM-dd"
        let releases=rows.compactMap{row->Release? in
            guard let version=row["ProductVersion"] as? String,major(version) != nil,let post=row["PostingDate"] as? String,let posted=date.date(from:post),let exp=row["ExpirationDate"] as? String,let expires=date.date(from:exp),let ids=row["SupportedDevices"] as? [String],!ids.isEmpty,ids.count<2000 else{return nil}
            return Release(version:version,posted:posted,expires:expires,devices:ids.map{$0.uppercased()})
        }
        guard !releases.isEmpty else {throw MajorUpgradeDemoError.invalid("Apple's catalog contains no verifiable macOS hardware lists.")}
        return .init(fetchedAt:now,releases:releases)
    }
    func assess(_ hardware:HardwareIdentity,target:String,now:Date=Date())->AppleHardwareResult {
        let major=Self.major(target)
        func result(_ state:HardwareSupportState,_ reason:String)->AppleHardwareResult {.init(state:state,targetMajor:major,model:hardware.model,reason:reason,checkedAt:now)}
        guard source=="https://gdmf.apple.com/v2/pmv",now.timeIntervalSince(fetchedAt)>=(-300),now.timeIntervalSince(fetchedAt)<=30*86400,let major,major>0 else {return result(.unknown,"The Apple catalog or selected version is stale, unavailable or invalid. No hardware-support assumption was made.")}
        let valid=releases.filter{$0.posted<=now && $0.expires>now}
        let targetRows=valid.filter{Self.major($0.version)==major}
        guard !targetRows.isEmpty else{return result(.unknown,"Apple's current catalog has no verified hardware list for the selected macOS major version.")}
        let keys=Set(hardware.deviceKeys.map{$0.uppercased()})
        guard !keys.isEmpty else{return result(.unknown,"The Mac's Apple device/board identity could not be read.")}
        if targetRows.contains(where:{!keys.isDisjoint(with:$0.devices)}) {return result(.supported,"Apple's published catalog lists this hardware for macOS \(major). Installer availability, minimum build, authorization and management restrictions still need separate checks.")}
        // Apple's current macOS 27 compatibility page lists Apple-silicon Macs only.
        // This negative rule is limited to known Intel Mac family identifiers and
        // a fresh target-27 catalog; no future major or unknown architecture is inferred.
        if major==27,hardware.appleSilicon==false,hardware.model.range(of:"^(MacBookPro|MacBookAir|MacBook|Macmini|MacPro|iMac|iMacPro)[0-9]+,[0-9]+$",options:.regularExpression) != nil {
            var value=result(.unsupported,"Apple's macOS 27 compatibility list requires Apple silicon. This Intel Mac is not supported for that major release. No upgrade was started.")
            value.source="https://www.apple.com/os/macos/";return value
        }
        let known=Set(valid.flatMap(\.devices))
        guard !keys.isDisjoint(with:known) else{return result(.unknown,"The detected device is not identifiable in the current Apple catalog. An unfamiliar model is not labeled unsupported.")}
        return result(.unsupported,"Apple's current catalog recognizes this device under other macOS releases but does not list it for macOS \(major). No upgrade was started.")
    }
}
