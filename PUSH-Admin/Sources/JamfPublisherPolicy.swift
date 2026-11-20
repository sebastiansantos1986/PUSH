// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import CryptoKit

struct JamfPublisherError:LocalizedError {
    let message:String
    var errorDescription:String? {message}
    init(_ message:String){self.message=message}
}
struct JamfPublisherConnection:Codable,Equatable {
    var server="",clientID=""
    func validatedURL()throws->URL {
        guard let c=URLComponents(string:server.trimmingCharacters(in:.whitespacesAndNewlines)),c.scheme?.lowercased()=="https",let host=c.host,!host.isEmpty,c.user==nil,c.password==nil,c.query==nil,c.fragment==nil,c.path.isEmpty || c.path=="/",!clientID.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw JamfPublisherError("Enter the HTTPS Jamf server origin (without /api, credentials or a path) and its client ID.")}
        var clean=c;clean.scheme="https";clean.host=host.lowercased();clean.path=""
        guard let url=clean.url else {throw JamfPublisherError("The Jamf URL is invalid.")};return url
    }
    var secretAccount:String {((try? validatedURL().absoluteString) ?? server) + "|" + clientID}
}
struct JamfPublisherGroup:Identifiable,Equatable {let id:Int,name:String}
struct JamfPublisherSnapshot {
    var groups:[JamfPublisherGroup]
    var categoryID:Int?
    var version:String
    var distribution:String
}
struct JamfPublisherFile {
    let url:URL,fileName:String,sha256:String,md5:String,size:Int
    init(_ url:URL,prefix:String)throws {
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,let size=values.fileSize,size>0,size<=134_217_728 else {throw JamfPublisherError("Select a regular flat package under 128 MB.")}
        let bytes=try Data(contentsOf:url)
        self.url=url;self.size=size;sha256=DeploymentBundle.digest(bytes)
        md5=Insecure.MD5.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
        fileName=prefix+"-"+String(sha256.prefix(16))+".pkg"
    }
}
struct JamfPublisherPolicyItem:Identifiable {
    let role:String,name:String,title:String,description:String,major:Int?
    var eventOnlyRepair=false
    var id:String {role}
}
struct JamfPublisherRemote {
    let id:Int,kind:String,name:String,xml:Data
    var role:String?=nil
    var digest:String {DeploymentBundle.digest(xml)}
}
struct JamfPublisherPlan {
    let project:UUID,connection:JamfPublisherConnection,kit:URL,group:JamfPublisherGroup?,groupName:String
    let client:JamfPublisherFile,profiles:JamfPublisherFile?,mist:JamfPublisherFile?,settings:SelfServiceSettings,icon:URL?
    var deployment=JamfDeploymentSettings()
    var repairClient:JamfPublisherFile?=nil
    func packageFile(for item:JamfPublisherPolicyItem)->JamfPublisherFile? {item.major != nil ? profiles:(item.eventOnlyRepair ? (repairClient ?? client):client)}
    let fileHashes:[String:String]
    let policies:[JamfPublisherPolicyItem],existing:[JamfPublisherRemote],draftHash:String
    var marker:String {"PUSH-Deployment:"+project.uuidString}
    var clientIdentity:String {mist.map{DeploymentBundle.digest(Data((client.sha256+"|"+$0.sha256).utf8))} ?? client.sha256}
    var repairRole:String {deployment.mode == .both ? "client-repair":"client"}
    var previousRepairEvent:String? {
        existing.first(where:{$0.kind=="policies" && $0.role==repairRole}).flatMap{try? JamfPublisherPolicy.value($0.xml,"/policy/general/trigger_other")}
    }
    var clientEvent:String {
        guard deployment.mode.includesOffers else{return ""}
        if let previous=previousRepairEvent,JamfPublisherPolicy.ownedRepairEvent(previous,project:project){return previous}
        return "push-client-"+project.uuidString.lowercased()+"-repair"
    }
    var scopeName:String {group?.name ?? groupName+" (new, empty)"}
    var summary:String {
        var lines=["Server: "+connection.server,"Scope: "+scopeName,"Category: PUSH","Upload/reuse client: "+client.fileName,"Offer profiles: "+(profiles?.fileName ?? "None — required-only deployment"),"Client prerequisite event: "+(clientEvent.isEmpty ? "None — required-only":clientEvent),"Scripts: "+(deployment.mode.includesOffers ? settings.majors:[]).map{"macOS \($0) (After)"}.joined(separator:", "),"Policies (published disabled):"]
        lines += policies.map{$0.title+($0.eventOnlyRepair ? " · on demand, repeatable repair; no check-in trigger":$0.major==nil ? (deployment.mode.requiresCampaign ? " · configured campaign, next check-in, once per computer":" · client only, next check-in, once per computer"):" · Self Service only, ongoing")}
        if let previous=previousRepairEvent {lines.append("Existing repair trigger: "+JamfPublisherPolicy.safeEventDescription(previous))}
        if !existing.isEmpty {lines.append("Existing owned policies will be paused before any script/package changes. Unrelated policies are preserved.")}
        lines += [deployment.summary,"No computer remote commands, update requests or restarts are sent by publishing.",deployment.mode.requiresCampaign ? "Enabling permits configured-client installation at check-in, then live reminders and deadline enforcement.":"Enabling permits on-demand client repair through the offer prerequisite event. An offer verifies the client/UI before requesting the upgrade.","The reviewed Mist package is included when selected; otherwise provision Mist before major upgrades."]
        return lines.joined(separator:"\n")
    }
}
struct JamfPublisherReceipt:Codable {
    struct Object:Codable {let kind:String,id:Int;var name:String;var action:String?=nil;var role:String?=nil}
    var server:String,project:UUID,createdAt=Date(),objects:[Object]=[],verified=false,enabled=false,message="",fingerprints:[String:String]=[:],clientDependencySignature:String?=nil
}
enum JamfPublisherPolicy {
    static let privileges=["Create Policies","Read Policies","Update Policies","Create Scripts","Read Scripts","Update Scripts","Create Packages","Read Packages","Update Packages","Create Categories","Read Categories","Read Smart Computer Groups","Read Static Computer Groups","Create Static Computer Groups","Read Cloud Distribution Point"]
    static func ownedRepairEvent(_ event:String,project:UUID)->Bool {
        event.range(of:"^push-client-"+project.uuidString.lowercased()+"-(repair|[a-f0-9]{16})$",options:[.regularExpression,.caseInsensitive]) != nil
    }
    static func safeEventDescription(_ event:String)->String {
        if event.isEmpty {return "<empty>"}
        if ["None","none"].contains(event){return event}
        if event.range(of:#"^push-client-[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}-(repair|[a-fA-F0-9]{16})$"#,options:.regularExpression) != nil{return event}
        return "<unrecognized trigger; length "+String(event.count)+">"
    }
    static func form(_ values:[String:String])->Data {
        let allowed=CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(values.keys.sorted().map{($0.addingPercentEncoding(withAllowedCharacters:allowed) ?? "")+"="+(values[$0]!.addingPercentEncoding(withAllowedCharacters:allowed) ?? "")}.joined(separator:"&").utf8)
    }
    static func escape(_ text:String)->String {text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;")}
    static func xml(_ text:String)throws->XMLDocument {
        guard text.utf8.count<=8_388_608,!text.uppercased().contains("<!DOCTYPE"),!text.uppercased().contains("<!ENTITY") else {throw JamfPublisherError("Jamf returned unsafe or oversized XML.")}
        return try XMLDocument(xmlString:text,options:[.nodeLoadExternalEntitiesNever])
    }
    static func value(_ xml:Data,_ path:String)throws->String {
        let doc=try self.xml(String(decoding:xml,as:UTF8.self))
        return try doc.nodes(forXPath:path).first?.stringValue ?? ""
    }
    enum PolicyState:String {case enabled,disabled,missing,ambiguous,invalid}
    static func policyState(_ data:Data)throws->PolicyState {
        let doc=try xml(String(decoding:data,as:UTF8.self)),nodes=try doc.nodes(forXPath:"/policy/general/enabled")
        guard !nodes.isEmpty else{return .missing}
        guard nodes.count==1 else{return .ambiguous}
        switch (nodes[0].stringValue ?? "").trimmingCharacters(in:.whitespacesAndNewlines) {
        case "true","1":return .enabled
        case "false","0":return .disabled
        default:return .invalid
        }
    }
    static func changingEnabled(_ data:Data,to enabled:Bool)throws->Data {
        let doc=try xml(String(decoding:data,as:UTF8.self))
        let fields=try doc.nodes(forXPath:"/policy/general/enabled")
        guard fields.count==1,let field=fields.first else {throw JamfPublisherError("Jamf policy has no enabled flag; it was not changed.")}
        field.stringValue=enabled ? "true":"false";return doc.xmlData
    }
    static func packageMetadata(_ file:JamfPublisherFile,category:Int,marker:String)->[String:Any] {
        // Do not submit our hash as server verification. Jamf must compute it.
        ["packageName":file.fileName,"fileName":file.fileName,"categoryId":String(category),"notes":marker+" SHA256:"+file.sha256,"priority":10,"fillUserTemplate":false,"fillExistingUsers":false,"swu":false,"rebootRequired":false,"osInstall":false,"suppressUpdates":false,"suppressFromDock":false,"suppressEula":false,"suppressRegistration":false]
    }
    static func packageReady(_ object:[String:Any],file:JamfPublisherFile)->Bool {
        guard object["fileName"] as? String==file.fileName,object["cloudTransferStatus"] as? String=="READY",Int(String(describing:object["size"] ?? ""))==file.size else{return false}
        let sha=(object["sha256"] as? String ?? "").lowercased(),md5=(object["md5"] as? String ?? "").lowercased()
        if !sha.isEmpty{return sha==file.sha256}
        if !md5.isEmpty{return md5==file.md5}
        let type=(object["hashType"] as? String ?? "").uppercased().replacingOccurrences(of:"-",with:"")
        let hash=(object["hashValue"] as? String ?? "").lowercased()
        return (type=="SHA256" && hash==file.sha256) || (type=="MD5" && hash==file.md5)
    }
    static func script(name:String,content:String,marker:String)->Data {
        Data(("<script><name>"+escape(name)+"</name><category>PUSH</category><notes>"+escape(marker)+"</notes><priority>After</priority><script_contents_encoded>"+Data(content.utf8).base64EncodedString()+"</script_contents_encoded></script>").utf8)
    }
    static func policy(_ item:JamfPublisherPolicyItem,scope:Int,category:Int,package:Int,script:Int?,marker:String,extraPackage:Int?=nil,clientEvent:String="")->Data {
        let prerequisite=item.major==nil
        let checkin=prerequisite && !item.eventOnlyRepair
        let scripts=script.map{"<scripts><size>1</size><script><id>\($0)</id><priority>After</priority></script></scripts>"} ?? "<scripts><size>0</size></scripts>"
        let packages=([package]+(extraPackage.map{[$0]} ?? [])).map{"<package><id>\($0)</id><action>Install</action><fut>false</fut><feu>false</feu></package>"}.joined()
        let description=item.description+"\n\n<!-- "+marker+" -->"
        return Data("""
        <policy><general><name>\(escape(item.name))</name><enabled>false</enabled><trigger>\(checkin ? "CHECKIN":"EVENT")</trigger><trigger_checkin>\(checkin)</trigger_checkin><trigger_enrollment_complete>false</trigger_enrollment_complete><trigger_login>false</trigger_login><trigger_logout>false</trigger_logout><trigger_network_state_changed>false</trigger_network_state_changed><trigger_startup>false</trigger_startup><trigger_other>\(item.eventOnlyRepair ? escape(clientEvent):"")</trigger_other><frequency>\(checkin ? "Once per computer":"Ongoing")</frequency><category><id>\(category)</id></category><site><id>-1</id></site></general>
        <scope><all_computers>false</all_computers><computers/><computer_groups><computer_group><id>\(scope)</id></computer_group></computer_groups><buildings/><departments/><exclusions><computers/><computer_groups/><buildings/><departments/><users/><user_groups/></exclusions></scope>
        <self_service><use_for_self_service>\(!prerequisite)</use_for_self_service><self_service_display_name>\(escape(item.title))</self_service_display_name><install_button_text>Update</install_button_text><reinstall_button_text>Update</reinstall_button_text><self_service_description>\(escape(description))</self_service_description><force_users_to_view_description>true</force_users_to_view_description><feature_on_main_page>false</feature_on_main_page><self_service_categories><category><id>\(category)</id><display_in>true</display_in><feature_in>false</feature_in></category></self_service_categories></self_service>
        <package_configuration><packages><size>\(extraPackage==nil ? 1:2)</size>\(packages)</packages></package_configuration>\(scripts)<reboot><no_user_logged_in>Do not restart</no_user_logged_in><user_logged_in>Do not restart</user_logged_in></reboot></policy>
        """.utf8)
    }
    static func verifyPolicy(_ data:Data,item:JamfPublisherPolicyItem,scope:Int,package:Int,script:Int?,enabled:Bool,extraPackage:Int?=nil,clientEvent:String="")throws {
        let doc=try xml(String(decoding:data,as:UTF8.self))
        let isOffer=item.major != nil
        let expected:[String:String]=[
            "/policy/general/name":item.name,
            "/policy/general/enabled":String(enabled),
            "/policy/scope/all_computers":"false",
            "/policy/scope/computer_groups/computer_group/id":String(scope),
            "/policy/self_service/use_for_self_service":String(isOffer),
            "/policy/general/frequency":(isOffer || item.eventOnlyRepair) ? "Ongoing":"Once per computer",
            "/policy/general/trigger_checkin":String(!isOffer && !item.eventOnlyRepair),
            "/policy/general/trigger_enrollment_complete":"false",
            "/policy/general/trigger_login":"false",
            "/policy/general/trigger_logout":"false",
            "/policy/general/trigger_network_state_changed":"false",
            "/policy/general/trigger_startup":"false",
            "/policy/general/trigger_other":item.eventOnlyRepair ? clientEvent:""
        ]
        for (path,value) in expected.sorted(by:{$0.key<$1.key}) {
            let nodes=try doc.nodes(forXPath:path)
            // Some Jamf versions omit the unsupported logout trigger in GET
            // responses. Its absence is accepted only for the reviewed OFF
            // state. An explicit true/empty value or any other missing safety
            // field still fails verification.
            if path=="/policy/general/trigger_logout",value=="false",nodes.isEmpty {continue}
            let actual=nodes.first?.stringValue ?? ""
            if path=="/policy/general/enabled",nodes.count==1 {
                let state=try policyState(data)
                if state == (enabled ? .enabled:.disabled) {continue}
            }
            guard nodes.count==1,actual==value else {
                let field=String(path.dropFirst("/policy/".count))
                let received=nodes.isEmpty ? "missing":actual.isEmpty ? "empty":["true","false"].contains(actual) ? actual:"different from the reviewed value"
                let detail=path=="/policy/general/trigger_other" ? " Expected "+safeEventDescription(value)+"; returned "+safeEventDescription(actual)+"; field count "+String(nodes.count)+".":""
                throw JamfPublisherError("Jamf policy read-back mismatch at "+field+" (returned "+received+")."+detail+" Policies remain requested disabled.")
            }
        }
        let groups=try doc.nodes(forXPath:"/policy/scope/computer_groups/computer_group")
        guard groups.count==1 else {throw JamfPublisherError("The reviewed pilot group scope was not retained.")}
        for path in ["/policy/scope/computers/computer","/policy/scope/buildings/building","/policy/scope/departments/department"] {
            guard try doc.nodes(forXPath:path).isEmpty else {throw JamfPublisherError("An unreviewed scope target was found.")}
        }
        let packageNodes=try doc.nodes(forXPath:"/policy/package_configuration/packages/package/id")
        let packageIDs=Set(packageNodes.compactMap{Int($0.stringValue ?? "")})
        let expectedIDs=Set([package]+(extraPackage.map{[$0]} ?? []))
        guard packageIDs==expectedIDs,packageNodes.count==expectedIDs.count else {throw JamfPublisherError("The reviewed package mapping was not retained.")}
        let scripts=try doc.nodes(forXPath:"/policy/scripts/script")
        if let script {
            let id=try doc.nodes(forXPath:"/policy/scripts/script/id").first?.stringValue ?? ""
            let priority=try doc.nodes(forXPath:"/policy/scripts/script/priority").first?.stringValue ?? ""
            guard scripts.count==1,id==String(script),priority=="After" else {throw JamfPublisherError("The offer script/order was not retained.")}
        }else {guard scripts.isEmpty else {throw JamfPublisherError("The client prerequisite contains an unexpected script.")}}
    }
    static func objects(_ data:Data,key:String)throws->[[String:Any]] {
        guard let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let list=object[key] as? [[String:Any]],list.count<=20_000 else {throw JamfPublisherError("Jamf returned an unsupported collection. No guessed mapping was used.")};return list
    }
    static func id(_ object:[String:Any])->Int? {Int(String(describing:object["id"] ?? ""))}
}
