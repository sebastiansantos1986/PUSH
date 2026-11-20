// PUSH Tahoe campaign — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import IOKit
import Darwin

struct Catalog:Decodable {
    struct Release:Decodable {let version:String,posted:Date,expires:Date,devices:[String]}
    let fetchedAt:Date,source:String,releases:[Release]
}
struct Identity {let model:String,keys:[String],appleSilicon:Bool?}
struct Readiness:Codable {let status:String,model:String,currentOS:String,reason:String,source:String;let targetMajor:Int=26}
let applePage="https://support.apple.com/en-us/122867"
func assess(_ identity:Identity,os:String,catalog:Catalog?,now:Date=Date())->Readiness {
    func result(_ status:String,_ reason:String,_ source:String=applePage)->Readiness {.init(status:status,model:identity.model,currentOS:os,reason:reason,source:source)}
    guard let major=Int(os.split(separator:".").first ?? "") else{return result("Unverified - IT review","Operating system version is unavailable.")}
    if major>26 {return result("Above Tahoe - do not downgrade","Already on a later major version; exclude from this campaign.")}
    guard let catalog,catalog.source=="https://gdmf.apple.com/v2/pmv",now.timeIntervalSince(catalog.fetchedAt)>=(-300),now.timeIntervalSince(catalog.fetchedAt)<=30*86400 else{return result("Unverified - IT review","Apple catalog missing or older than 30 days; refresh before classifying.")}
    let valid=catalog.releases.filter{$0.posted<=now && $0.expires>now}
    let tahoe=valid.filter{$0.version.split(separator:".").first=="26"}
    guard !tahoe.isEmpty,!identity.keys.isEmpty else{return result("Unverified - IT review","No current Tahoe hardware list or readable device identity.")}
    let keys=Set(identity.keys.map{$0.uppercased()})
    let listed=tahoe.contains{!keys.isDisjoint(with:$0.devices.map{$0.uppercased()})}
    let intelMac=identity.appleSilicon==false && identity.model.range(of:"^(MacBookPro|MacBookAir|MacBook|Macmini|MacPro|iMac|iMacPro)[0-9]+,[0-9]+$",options:.regularExpression) != nil
    // Apple's complete Tahoe Intel list, mapped to Apple's model identifiers:
    // 2019 16-inch MBP, 2020 13-inch four-port MBP, 2020 27-inch iMac, 2019 Mac Pro.
    let intelSupported=Set(["MacBookPro16,1","MacBookPro16,4","MacBookPro16,2","iMac20,1","iMac20,2","MacPro7,1"])
    if listed || (intelMac && intelSupported.contains(identity.model)) {
        return result(major<14 ? "Tahoe supported - OS below PUSH minimum":"Tahoe supported",major<14 ? "Hardware supports Tahoe, but the PUSH client requires macOS 14+. IT must bridge this OS before installing PUSH.":"Hardware supports Tahoe. Installer availability, disk space, power and installation authorization require separate checks.",listed ? catalog.source:applePage)
    }
    if intelMac || valid.contains(where:{!keys.isDisjoint(with:$0.devices.map{$0.uppercased()})}) {
        return result("Tahoe unsupported - replacement review","Not listed for Tahoe. Review for replacement; this result does not say that all security updates are unavailable.")
    }
    return result("Unverified - IT review","Unrecognized hardware is not labeled unsupported.")
}
func identity()->Identity {
    var n=0;sysctlbyname("hw.model",nil,&n,nil,0);var b=[CChar](repeating:0,count:max(1,n));sysctlbyname("hw.model",&b,&n,nil,0);let model=String(cString:b)
    var keys=[model]
    for entry in [IORegistryEntryFromPath(kIOMasterPortDefault,"IODeviceTree:/"),IOServiceGetMatchingService(kIOMasterPortDefault,IOServiceMatching("IOPlatformExpertDevice"))] where entry != 0 {
        for name in ["target-type","bridge-model","bridge-model-identifier","board-id","compatible","model"] {
            if let value=IORegistryEntryCreateCFProperty(entry,name as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() {
                if let d=value as? Data,let s=String(data:d,encoding:.utf8){keys+=s.split(separator:"\0").map(String.init)}else if let s=value as? String {keys.append(s)}
            }
        };IOObjectRelease(entry)
    }
    var arm:Int32=0;var armN=MemoryLayout<Int32>.size;let silicon:Bool?=sysctlbyname("hw.optional.arm64",&arm,&armN,nil,0)==0 ? arm==1:nil
    return .init(model:model,keys:keys,appleSilicon:silicon)
}
func resolvedArchitecture(_ arm:Bool?,os:String)->Bool? {
    if let arm {return arm}
    // Actual macOS 10 predates Apple silicon. On newer systems a missing
    // architecture capability remains unverified (including Rosetta ambiguity).
    return Int(os.split(separator:".").first ?? "")==10 ? false:nil
}
func load(_ path:String)->Catalog? {guard let d=try? Data(contentsOf:URL(fileURLWithPath:path)),d.count<1048576 else{return nil};return try? JSONDecoder().decode(Catalog.self,from:d)}
if CommandLine.arguments.count==3,CommandLine.arguments[1]=="--self-test",let catalog=load(CommandLine.arguments[2]),let target=catalog.releases.first(where:{$0.version.hasPrefix("26.")}),let board=target.devices.first {
    let now=catalog.fetchedAt.addingTimeInterval(60);var count=0
    func check(_ value:Bool){guard value else{fputs("Offline readiness fixture failed\n",stderr);exit(1)};count+=1}
    check(resolvedArchitecture(nil,os:"10.15.7")==false)
    check(resolvedArchitecture(nil,os:"14.0")==nil)
    check(resolvedArchitecture(true,os:"26.0")==true)
    let known=Identity(model:"FixtureMac",keys:[board.lowercased()],appleSilicon:true)
    check(assess(known,os:"15.7",catalog:catalog,now:now).status=="Tahoe supported")
    check(assess(known,os:"12.0",catalog:catalog,now:now).status=="Tahoe supported - OS below PUSH minimum")
    check(assess(known,os:"26.0",catalog:catalog,now:now).status=="Tahoe supported")
    check(assess(known,os:"27.0",catalog:nil,now:now).status=="Above Tahoe - do not downgrade")
    for model in ["MacBookPro16,1","MacBookPro16,4","MacBookPro16,2","iMac20,1","iMac20,2","MacPro7,1"] {check(assess(.init(model:model,keys:[model],appleSilicon:false),os:"15.0",catalog:catalog,now:now).status=="Tahoe supported")}
    for model in ["MacBookPro16,3","MacBookPro15,1","MacBookAir9,1","iMac19,1"] {check(assess(.init(model:model,keys:[model],appleSilicon:false),os:"15.0",catalog:catalog,now:now).status=="Tahoe unsupported - replacement review")}
    check(assess(.init(model:"Unknown",keys:["UNLISTED"],appleSilicon:nil),os:"15.0",catalog:catalog,now:now).status=="Unverified - IT review")
    check(assess(known,os:"15.0",catalog:catalog,now:now.addingTimeInterval(31*86400)).status=="Unverified - IT review")
    check(assess(known,os:"15.0",catalog:nil,now:now).status=="Unverified - IT review")
    check(assess(known,os:"invalid",catalog:catalog,now:now).status=="Unverified - IT review")
    print("Passed \(count) offline hardware fixtures. No local hardware, credential, popup or update check was performed.");exit(0)
}
let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/sw_vers");process.arguments=["-productVersion"];let pipe=Pipe();process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
var os="";if (try? process.run()) != nil {let d=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit();if process.terminationStatus==0 {os=String(decoding:d,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)}}
let detected=identity()
let local=Identity(model:detected.model,keys:detected.keys,appleSilicon:resolvedArchitecture(detected.appleSilicon,os:os))
let report=assess(local,os:os,catalog:load("/Library/Management/PUSH/Tahoe-Campaign/AppleHardwareCatalog.json"))
if CommandLine.arguments.contains("--ea") {print("<result>\(report.status)</result>")}
else if let data=try? JSONEncoder().encode(report),let text=String(data:data,encoding:.utf8){print(text)}else{exit(1)}
