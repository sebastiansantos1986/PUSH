// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import IOKit
import Darwin

struct AppleHardwareReader {
    static func identity()->HardwareIdentity {
        var size=0;sysctlbyname("hw.model",nil,&size,nil,0);var bytes=[CChar](repeating:0,count:max(1,size));sysctlbyname("hw.model",&bytes,&size,nil,0)
        let model=String(cString:bytes);var keys=[model]
        func read(_ entry:io_registry_entry_t) {
            guard entry != 0 else{return}
            defer{IOObjectRelease(entry)}
            for name in ["target-type","bridge-model","bridge-model-identifier","board-id","compatible","model"] {
                if let value=IORegistryEntryCreateCFProperty(entry,name as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() {
                    if let data=value as? Data,let text=String(data:data,encoding:.utf8){keys+=text.split(separator:"\0").map(String.init)}
                    else if let text=value as? String {keys.append(text)}
                }
            }
        }
        read(IORegistryEntryFromPath(kIOMainPortDefault,"IODeviceTree:/"))
        read(IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOPlatformExpertDevice")))
        var arm:Int32=0;var armSize=MemoryLayout<Int32>.size
        let architecture:Bool?=sysctlbyname("hw.optional.arm64",&arm,&armSize,nil,0)==0 ? arm==1:nil
        return .init(model:model,deviceKeys:Array(Set(keys.filter{!$0.isEmpty && $0.count<100})),appleSilicon:architecture)
    }
    static func bundled()->AppleHardwareCatalog? {
        var paths=[cacheURL.path,"/Library/Management/PUSH/assets/hardware/AppleHardwareCatalog.json","/Library/Management/PUSH/push-ui.app/Contents/Resources/AppleHardwareCatalog.json","/Library/Management/PUSH/PUSH Major Upgrade Demo.app/Contents/Resources/AppleHardwareCatalog.json"]
        if let url=Bundle.main.url(forResource:"AppleHardwareCatalog",withExtension:"json"){paths.append(url.path)}
        return paths.compactMap {path->AppleHardwareCatalog? in
            guard let info=try? FileManager.default.attributesOfItem(atPath:path),((info[.size] as? NSNumber)?.intValue ?? Int.max) < 1048576,let data=try? Data(contentsOf:URL(fileURLWithPath:path)),let value=try? JSONDecoder().decode(AppleHardwareCatalog.self,from:data),value.source=="https://gdmf.apple.com/v2/pmv",value.fetchedAt.timeIntervalSinceNow<300 else{return nil}
            return value
        }.max{$0.fetchedAt<$1.fetchedAt}
    }
    static func assessment(target:String)->AppleHardwareResult {
        let hardware=identity()
        return bundled()?.assess(hardware,target:target) ?? .init(state:.unknown,targetMajor:AppleHardwareCatalog.major(target),model:hardware.model,reason:"The verified Apple hardware catalog is unavailable. No compatibility assumption was made.",checkedAt:Date())
    }
}

extension AppleHardwareReader {
    static var cacheURL:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PUSH Hardware/catalog.json")}
    static func refresh()async throws->AppleHardwareCatalog {
        var request=URLRequest(url:URL(string:"https://gdmf.apple.com/v2/pmv")!);request.timeoutInterval=20;request.cachePolicy = .reloadIgnoringLocalCacheData
        let session=URLSession(configuration:.ephemeral);defer{session.invalidateAndCancel()}
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,http.statusCode==200,http.url?.scheme=="https",http.url?.host=="gdmf.apple.com" else {throw MajorUpgradeDemoError.invalid("Apple's hardware catalog could not be verified.")}
        let catalog=try AppleHardwareCatalog.fromApple(data)
        try FileManager.default.createDirectory(at:cacheURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(catalog).write(to:cacheURL,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:cacheURL.path)
        return catalog
    }
}
