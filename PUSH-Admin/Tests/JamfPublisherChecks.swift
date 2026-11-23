// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit

/// In-memory server; never creates a URLSession or accesses Keychain/Jamf.
final class FixtureJamfTransport:JamfHTTPTransport {
    var requests:[URLRequest]=[]
    var packages:[[String:Any]]=[],scripts:[Int:Data]=[:],policies:[Int:Data]=[:]
    var cloud="JAMF_CLOUD",failRoute:String?,wrongHash=false,failEnable=false,pending=false
    var validationRoute:String?
    var next=100,enableAttempts=0
    var lagReadsOnStateWrite=0,numericPolicyState=false,ignoreDisable=false
    var stalePolicies:[Int:(Data,Int)]=[:]
    var groupXML:[Int:Data]=[:]
    var groups:[[String:Any]]=[["id":9,"name":"Approved Pilot"]]
    func response(_ object:Any,status:Int=200)throws->JamfHTTPResponse {.init(data:try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]),status:status)}
    func send(_ request:URLRequest,upload:URL?) async throws->JamfHTTPResponse {
        requests.append(request)
        let path=request.url!.path.trimmingCharacters(in:CharacterSet(charactersIn:"/")),method=request.httpMethod!
        if path==validationRoute && method=="PUT" {return .init(data:Data("<html><body><h1>Conflict</h1><p>Error: Missing required field self_service_icon.id</p></body></html>".utf8),status:409)}
        if path==failRoute {return try response(["message":"TOP_SECRET_DO_NOT_SHOW"],status:403)}
        if path=="api/oauth/token" {return try response(["access_token":"FIXTURE_TOKEN","expires_in":1800])}
        if path=="api/v1/auth/invalidate-token" {return .init(data:Data(),status:204)}
        if path=="api/v1/jamf-pro-version" {return try response(["version":"11.22.0-t1760000000"])}
        if path=="api/v1/cloud-distribution-point" {return try response(["cdnType":cloud])}
        if path=="JSSResource/categories" {return try response(["categories":[["id":2,"name":"PUSH"]]])}
        if path=="JSSResource/computergroups" {return try response(["computer_groups":groups])}
        if path=="JSSResource/scripts" {return try response(["scripts":try scripts.map{["id":$0.key,"name":try JamfPublisherPolicy.value($0.value,"/script/name")] as [String:Any]}])}
        if path=="JSSResource/policies" {return try response(["policies":try policies.map{["id":$0.key,"name":try JamfPublisherPolicy.value($0.value,"/policy/general/name")] as [String:Any]}])}
        if path=="api/v1/packages" {
            if method=="GET" {return try response(["results":packages,"totalCount":packages.count])}
            var record=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any];next+=1;record["id"]=String(next);record["cloudTransferStatus"]="MISSING";packages.append(record);return try response(["id":String(next)],status:201)
        }
        if path.hasPrefix("api/v1/packages/") {
            let id=Int(path.split(separator:"/")[3])!,index=packages.firstIndex{JamfPublisherPolicy.id($0)==id}!
            if method=="GET" {return try response(packages[index])}
            let body=try Data(contentsOf:upload!),start=body.range(of:Data("\r\n\r\n".utf8))!.upperBound
            let boundary=request.value(forHTTPHeaderField:"Content-Type")!.components(separatedBy:"boundary=").last!
            let end=body.range(of:Data(("\r\n--"+boundary+"--\r\n").utf8))!.lowerBound
            let bytes=body.subdata(in:start..<end)
            packages[index]["size"]=String(bytes.count);packages[index]["sha256"]=wrongHash ? String(repeating:"0",count:64):DeploymentBundle.digest(bytes);packages[index]["cloudTransferStatus"]=pending ? "UPLOADING":"READY"
            return .init(data:Data("{}".utf8),status:201)
        }
        for kind in ["scripts","policies"] where path.hasPrefix("JSSResource/"+kind+"/id/") {
            var id=Int(path.split(separator:"/").last!)!
            if method=="GET" {
                var data=(kind=="scripts" ? scripts[id]:policies[id])!
                if kind=="policies",let (old,remaining)=stalePolicies[id],remaining>0 {data=old;stalePolicies[id]=(old,remaining-1)}
                if kind=="policies",numericPolicyState {
                    let doc=try JamfPublisherPolicy.xml(String(decoding:data,as:UTF8.self))
                    for node in try doc.nodes(forXPath:"/policy/general/enabled") {node.stringValue=(node.stringValue=="true" || node.stringValue=="1") ? "1":"0"}
                    data=doc.xmlData
                }
                return .init(data:data,status:200)
            }
            if kind=="policies",(try? JamfPublisherPolicy.value(request.httpBody!,"/policy/general/enabled"))=="true" {
                enableAttempts+=1
                if failEnable,enableAttempts>=2 {return try response(["message":"TOP_SECRET_DO_NOT_SHOW"],status:403)}
            }
            if kind=="policies",id != 0,let old=policies[id] {
                let was=try JamfPublisherPolicy.policyState(old),desired=try JamfPublisherPolicy.policyState(request.httpBody!)
                if ignoreDisable,was == .enabled,desired == .disabled {return try response(["id":String(id)])}
                if was != desired,lagReadsOnStateWrite>0 {stalePolicies[id]=(old,lagReadsOnStateWrite)}
            }
            if id==0 {next+=1;id=next}
            if kind=="scripts" {scripts[id]=request.httpBody!}else{
                let doc=try JamfPublisherPolicy.xml(String(decoding:request.httpBody!,as:UTF8.self))
                for node in try doc.nodes(forXPath:"/policy/general/trigger_logout") {node.detach()}
                policies[id]=doc.xmlData
            }
            return try response(["id":String(id)],status:method=="POST" ? 201:200)
        }
        if path.hasPrefix("JSSResource/fileuploads/policies/") {
            let id=Int(path.split(separator:"/").last!)!,doc=try JamfPublisherPolicy.xml(String(decoding:policies[id]!,as:UTF8.self))
            let service=try doc.nodes(forXPath:"/policy/self_service").first as! XMLElement
            let icon=XMLElement(name:"self_service_icon");icon.addChild(XMLElement(name:"id",stringValue:"999"));service.addChild(icon)
            policies[id]=doc.xmlData
            return .init(data:Data(),status:201)
        }
        if path.hasPrefix("JSSResource/computergroups/id/") {
            var id=Int(path.split(separator:"/").last!)!
            if method=="GET" {
                let name=groups.first{JamfPublisherPolicy.id($0)==id}!["name"] as! String
                return .init(data:groupXML[id] ?? Data("<computer_group><id>\(id)</id><name>\(JamfPublisherPolicy.escape(name))</name><is_smart>false</is_smart><site><id>-1</id></site><computers><computer><id>77</id></computer></computers></computer_group>".utf8),status:200)
            }
            if id==0 {next+=1;id=next}
            let name=try JamfPublisherPolicy.value(request.httpBody!,"/computer_group/name")
            groupXML[id]=request.httpBody!
            if let index=groups.firstIndex(where:{JamfPublisherPolicy.id($0)==id}) {groups[index]["name"]=name}else{groups.append(["id":id,"name":name])}
            return try response(["id":String(id)],status:method=="POST" ? 201:200)
        }
        if path=="JSSResource/categories/id/0" {next+=1;return try response(["id":String(next)],status:201)}
        throw JamfPublisherError("Unexpected fixture request: "+method+" "+path)
    }
}
func runJamfPublisherChecks() async throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("push-publisher-tests-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
    defer{try? FileManager.default.removeItem(at:root)}
    for name in ["PUSH-Client-1.16.7.pkg","PUSH-Repair-Client.pkg","PUSH-SelfService-Profiles.pkg"] {try Data(("FIXTURE DATA "+name).utf8).write(to:root.appendingPathComponent(name))}
    for major in [26,27] {try Data(SelfServiceKit.script(major:major).utf8).write(to:root.appendingPathComponent("Jamf-Offer-macOS-\(major).sh"))}
    let connection=JamfPublisherConnection(server:"https://tenant.example.test",clientID:"client+&=")
    for server in ["http://tenant.example.test","https://user:password@tenant.example.test","https://tenant.example.test/api","https://tenant.example.test?token=x","https://tenant.example.test/#x"] {
        do{_=try JamfPublisherConnection(server:server,clientID:"x").validatedURL();check(false,"unsafe Jamf origin rejected")}catch{check(true,"unsafe Jamf origin rejected")}
    }
    check(connection.secretAccount != JamfPublisherConnection(server:connection.server,clientID:"another").secretAccount,"API Keychain entries bind both server and client ID")
    let form=String(decoding:JamfPublisherPolicy.form(["client_id":"x+&=","client_secret":"a b/+&="]),as:UTF8.self)
    check(form.contains("client_id=x%2B%26%3D") && form.contains("client_secret=a%20b%2F%2B%26%3D"),"OAuth form encoding preserves plus/ampersand/equal/space in secrets")
    for pair in [("POST","api/v1/mdm/commands"),("POST","api/v1/managed-software-updates/plans"),("DELETE","JSSResource/policies/id/1"),("POST","JSSResource/computercommands/command/EraseDevice"),("PUT","api/v1/api-roles/1")] {check(!JamfPublisherAPI.allowed(method:pair.0,path:pair.1),"publisher refuses unrelated/destructive endpoint "+pair.1)}
    do{_=try JamfPublisherPolicy.xml("<!DOCTYPE x [<!ENTITY xx SYSTEM 'file:///etc/passwd'>]><policy>&xx;</policy>");check(false,"XML entities blocked")}catch{check(true,"XML entities blocked")}
    let server=FixtureJamfTransport(),api=try JamfPublisherAPI(connection:connection,secret:"FIXTURE_SECRET",transport:server),publisher=JamfPublisher(api:api)
    publisher.pollDelayNanoseconds=0
    let inspection=try await publisher.inspect()
    check(inspection.groups.first?.id==9,"read-only inspection lists pilot groups")
    check(server.requests.allSatisfy{$0.httpMethod=="GET" || $0.url?.path=="/api/oauth/token"},"connection check writes no Jamf configuration")
    var settings=SelfServiceSettings();settings.title26="Tahoe <IT> & team";settings.description26="Save work <now> & connect to power."
    let project=UUID()
    let plan=try await publisher.prepare(kit:root,project:project,settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    let receipt=try await publisher.publish(plan)
    let success=JamfPublishSuccess(plan:plan,receipt:receipt)
    check(success != nil && success!.title=="Published to Jamf" && !success!.enabled,"publish success dialog requires a verified receipt and describes disabled policies")
    check(success?.group.name=="Approved Pilot" && success?.group.id==9 && success?.group.action=="Used existing group","success dialog gives the exact existing group name and ID")
    check(Set(success!.policies.map(\.name))==Set(plan.policies.map(\.name)) && success!.policies.allSatisfy{$0.action=="Created"},"success dialog lists every actual created policy name rather than only display titles")
    let summary=try String(contentsOf:root.appendingPathComponent("Jamf-publish-summary.txt"),encoding:.utf8)
    check(summary==success?.text && summary.contains("Disabled") && success!.policies.allSatisfy{summary.contains($0.name) && summary.contains("Jamf ID: \($0.id)")},"saved summary matches the dialog and retains exact names and IDs")
    var incomplete=receipt;incomplete.verified=false
    check(JamfPublishSuccess(plan:plan,receipt:incomplete)==nil,"partial/unverified publish cannot show a success dialog")
    var wrongServer=receipt;wrongServer.server="https://another.example.test"
    check(JamfPublishSuccess(plan:plan,receipt:wrongServer)==nil,"success report cannot mix a different server's receipt")
    check(JamfPublishSuccess.preview.isPreview && JamfPublishSuccess.preview.text.contains("SIMULATION ONLY") && JamfPublishSuccess.preview.text.contains("EXAMPLE"),"display-only success preview clearly labels fictional names and IDs")
    check(receipt.verified && !receipt.enabled && server.policies.count==3 && server.scripts.count==2,"publisher creates two offers and a client prerequisite disabled")
    check(server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/general/enabled"))=="false"},"publish never enables a policy")
    check(server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/scope/all_computers"))=="false" && (try? JamfPublisherPolicy.value($0,"/policy/scope/computer_groups/computer_group/id"))=="9"},"all published policies retain the selected single pilot scope")
    let offer=server.policies.values.first{(try? JamfPublisherPolicy.value($0,"/policy/self_service/self_service_display_name"))==settings.title26}!
    let prerequisite=server.policies.values.first{(try? JamfPublisherPolicy.value($0,"/policy/general/trigger_other"))==plan.clientEvent}!
    check(plan.clientEvent=="push-client-"+project.uuidString.lowercased()+"-repair","new workflows use a stable project repair trigger rather than a package hash")
    check(JamfPublisherPolicy.ownedRepairEvent("push-client-"+project.uuidString.lowercased()+"-0123456789abcdef",project:project),"legacy project-and-hash repair triggers remain valid")
    check(!JamfPublisherPolicy.ownedRepairEvent("push-client-"+UUID().uuidString.lowercased()+"-repair",project:project),"another project's trigger cannot be inherited")
    check(JamfPublisherPolicy.safeEventDescription("SECRET_DO_NOT_REPORT").contains("unrecognized") && !JamfPublisherPolicy.safeEventDescription("SECRET_DO_NOT_REPORT").contains("SECRET"),"unexpected trigger diagnostics never echo arbitrary field contents")
    let boundEvent=try JamfPublisherPolicy.value(prerequisite,"/policy/general/trigger_other")
    check((try? JamfPublisherPolicy.value(prerequisite,"/policy/general/frequency"))=="Ongoing" && (try? JamfPublisherPolicy.value(prerequisite,"/policy/general/trigger_checkin"))=="false","repair remains callable after prior success and cannot reinstall at every check-in")
    check(boundEvent==plan.clientEvent && boundEvent.hasPrefix("push-client-"+project.uuidString.lowercased()),"client prerequisite custom event binds the exact reviewed deployment and client hash")
    let boundScripts=server.scripts.values.compactMap{data -> String? in guard let encoded=try? JamfPublisherPolicy.value(data,"/script/script_contents_encoded"),let bytes=Data(base64Encoded:encoded) else{return nil};return String(decoding:bytes,as:UTF8.self)}
    check(boundScripts.count==2 && boundScripts.allSatisfy{$0.contains("client_event=\""+plan.clientEvent+"\"")},"each published offer requests only its own client prerequisite event")
    let savedTitle=try JamfPublisherPolicy.value(offer,"/policy/self_service/self_service_display_name")
    check(savedTitle==settings.title26,"Self Service names survive XML escaping")
    let item=plan.policies.first!,clientObject=receipt.objects.first{$0.kind=="policies" && $0.name==item.name}!
    let clientReadback=server.policies[clientObject.id]!,clientPackage=receipt.objects.first{$0.kind=="packages" && $0.name==plan.client.fileName}!.id
    let clientDocument=try JamfPublisherPolicy.xml(String(decoding:clientReadback,as:UTF8.self))
    let logoutNodes=try clientDocument.nodes(forXPath:"/policy/general/trigger_logout")
    check(logoutNodes.isEmpty,"publisher fixture reproduces Jamf's omitted unsupported logout trigger")
    try JamfPublisherPolicy.verifyPolicy(clientReadback,item:item,scope:9,package:clientPackage,script:nil,enabled:false,clientEvent:plan.clientEvent)
    check(true,"live-server logout-field omission passes the narrowly scoped compatibility rule")
    for (field,value) in [("trigger_logout","true"),("trigger_logout",""),("trigger_network_state_changed","missing"),("enabled","missing"),("trigger_other","missing")] {
        let changed=try JamfPublisherPolicy.xml(String(decoding:clientReadback,as:UTF8.self))
        let general=try changed.nodes(forXPath:"/policy/general").first as! XMLElement
        for node in try changed.nodes(forXPath:"/policy/general/"+field) {node.detach()}
        if value != "missing" {general.addChild(XMLElement(name:field,stringValue:value))}
        do{try JamfPublisherPolicy.verifyPolicy(changed.xmlData,item:item,scope:9,package:clientPackage,script:nil,enabled:false,clientEvent:plan.clientEvent);check(false,"unsafe/malformed read-back rejected "+field)}catch{check(error.localizedDescription.contains(field),"unsafe/malformed read-back rejected with a precise field name: "+field)}
    }
    let before=server.packages.count
    let again=try await publisher.prepare(kit:root,project:project,settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    let second=try await publisher.publish(again)
    check(JamfPublishSuccess(plan:again,receipt:second)!.policies.allSatisfy{$0.action=="Updated"},"repeat publish success reports updated policies honestly")
    check(server.packages.count==before && server.policies.count==3 && server.scripts.count==2 && second.verified,"explicit repeat publish updates owned items without duplicates")
    let activated=try await publisher.enablePilot(again,receipt:second)
    let enabledReport=JamfPublishSuccess(plan:again,receipt:activated)
    check(enabledReport?.enabled==true && enabledReport?.title=="Your pilot is enabled" && enabledReport!.text.contains("Enabled for pilot"),"pilot activation success popup distinguishes enabled state from disabled publishing")
    check(activated.enabled && server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/general/enabled"))=="true"},"separate pilot activation enables only verified policies")
    check(server.requests.allSatisfy{JamfPublisherAPI.allowed(method:$0.httpMethod!,path:$0.url!.path.trimmingCharacters(in:CharacterSet(charactersIn:"/")))},"full publish/enable sends no remote upgrade or restart request")
    let stored=try Data(contentsOf:root.appendingPathComponent("Jamf-publish-receipt.json"))
    check(!String(decoding:stored,as:UTF8.self).contains("FIXTURE_SECRET") && !String(decoding:stored,as:UTF8.self).contains("FIXTURE_TOKEN"),"publish receipt contains IDs and hashes, never API secrets or tokens")
    // A changed remote script must not be activated using an older verification.
    let pausedPlan=try await publisher.prepare(kit:root,project:project,settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    let pausedReceipt=try await publisher.publish(pausedPlan)
    let changed=server.scripts.keys.first!;server.scripts[changed]=Data("<script><name>Changed</name></script>".utf8)
    do{_=try await publisher.enablePilot(pausedPlan,receipt:pausedReceipt);check(false,"changed published script blocks activation")}catch{check(true,"changed published script blocks activation")}
    check(server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/general/enabled"))=="false"},"failed pre-activation verification leaves policies disabled")
    server.scripts[changed]=pausedPlan.existing.first{$0.kind=="scripts" && $0.id==changed}!.xml
    let activationPlan=try await publisher.prepare(kit:root,project:project,settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    let activationReceipt=try await publisher.publish(activationPlan)
    server.failEnable=true;server.enableAttempts=0
    do{_=try await publisher.enablePilot(activationPlan,receipt:activationReceipt);check(false,"partial activation failure handled")}catch{check(true,"partial activation failure handled")}
    check(server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/general/enabled"))=="false"},"partial activation requests rollback to disabled for every reviewed policy")
    server.failEnable=false
    let drift=try await publisher.prepare(kit:root,project:project,settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    let policyID=server.policies.keys.first!,beforeDriftWrites=server.requests.filter{$0.httpMethod != "GET"}.count
    server.policies[policyID]=try JamfPublisherPolicy.changingEnabled(server.policies[policyID]!,to:true)
    do{_=try await publisher.publish(drift);check(false,"remote drift blocks overwrite")}catch{check(true,"remote drift blocks overwrite")}
    check(server.requests.filter{$0.httpMethod != "GET"}.count==beforeDriftWrites,"remote drift is detected before any write")
    let badServer=FixtureJamfTransport();badServer.wrongHash=true
    let badPublisher=JamfPublisher(api:try JamfPublisherAPI(connection:connection,secret:"fixture",transport:badServer));badPublisher.pollDelayNanoseconds=0
    let badPlan=try await badPublisher.prepare(kit:root,project:UUID(),settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    do{_=try await badPublisher.publish(badPlan);check(false,"wrong server package hash blocks publish")}catch{check(true,"wrong server package hash blocks publish")}
    check(badServer.policies.isEmpty && badServer.requests.filter{$0.url?.path.hasSuffix("/upload")==true}.count==1,"unverified upload neither creates policies nor retries writes automatically")
    let mist=root.appendingPathComponent("Approved-Mist.pkg");try Data("fixture Mist package".utf8).write(to:mist)
    try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])).write(to:root.appendingPathComponent("Self-Service-Icon.png"))
    let emptyServer=FixtureJamfTransport(),emptyPublisher=JamfPublisher(api:try JamfPublisherAPI(connection:connection,secret:"fixture",transport:emptyServer));emptyPublisher.pollDelayNanoseconds=0
    let emptyPlan=try await emptyPublisher.prepare(kit:root,project:UUID(),settings:settings,group:nil,draftHash:"fixture",mistURL:mist)
    let emptyReceipt=try await emptyPublisher.publish(emptyPlan)
    let emptySuccess=JamfPublishSuccess(plan:emptyPlan,receipt:emptyReceipt)
    check(emptySuccess?.group.name==emptyPlan.groupName && emptySuccess?.group.action=="Created empty group" && !emptySuccess!.group.name.contains("(new, empty)"),"new pilot success popup uses the real created group name without review annotations")
    check(emptyReceipt.verified && emptyServer.groups.count==2 && emptyServer.packages.count==3,"publisher can create an empty pilot and include an approved Mist prerequisite")
    let clientXML=emptyServer.policies.values.first{(try? JamfPublisherPolicy.value($0,"/policy/self_service/use_for_self_service"))=="false"}!
    let clientDoc=try JamfPublisherPolicy.xml(String(decoding:clientXML,as:UTF8.self))
    let packageCount=try clientDoc.nodes(forXPath:"/policy/package_configuration/packages/package").count
    check(packageCount==2,"client prerequisite installs both reviewed client and Mist packages")
    check(emptyServer.policies.values.filter{(try? JamfPublisherPolicy.value($0,"/policy/self_service/use_for_self_service"))=="true"}.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/self_service/self_service_icon/id"))=="999"},"custom Self Service icon attachment is verified for both offers")
    var archived=ConfigDocument.fresh;archived.jamfDeploymentID=project
    let restored=try SavedWorkflow(name:"Jamf deployment",document:archived,wallpaperData:[:]).restoredDocument()
    check(restored.jamfDeploymentID==project,"reusable workflows retain their Jamf ownership identity without secrets")
    let pendingServer=FixtureJamfTransport();pendingServer.pending=true
    let pendingPublisher=JamfPublisher(api:try JamfPublisherAPI(connection:connection,secret:"fixture",transport:pendingServer));pendingPublisher.pollDelayNanoseconds=0
    let pendingProject=UUID(),pendingPlan=try await pendingPublisher.prepare(kit:root,project:pendingProject,settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    do{_=try await pendingPublisher.publish(pendingPlan);check(false,"pending cloud package remains disabled")}catch{check(true,"pending cloud package remains disabled")}
    pendingServer.pending=false;pendingServer.packages[0]["cloudTransferStatus"]="READY"
    let resumedPlan=try await pendingPublisher.prepare(kit:root,project:pendingProject,settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    let resumedReceipt=try await pendingPublisher.publish(resumedPlan)
    check(resumedReceipt.verified && pendingServer.packages.count==2,"resume reuses the same immutable package records after cloud inventory catches up")
    check(pendingServer.requests.filter{$0.url?.path.hasSuffix("/upload")==true}.count==2,"resume does not re-upload the already verified client package")
    // No server mutation after a frozen local kit changes.
    let freshServer=FixtureJamfTransport(),freshAPI=try JamfPublisherAPI(connection:connection,secret:"FIXTURE_SECRET",transport:freshServer),freshPublisher=JamfPublisher(api:freshAPI)
    freshPublisher.pollDelayNanoseconds=0
    let frozen=try await freshPublisher.prepare(kit:root,project:UUID(),settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"fixture")
    try Data("changed package".utf8).write(to:root.appendingPathComponent("PUSH-SelfService-Profiles.pkg"))
    let writes=freshServer.requests.filter{$0.httpMethod != "GET"}.count
    do{_=try await freshPublisher.publish(frozen);check(false,"changed local package blocks publish")}catch{check(true,"changed local package blocks publish")}
    check(freshServer.requests.filter{$0.httpMethod != "GET"}.count==writes,"changed kit causes no Jamf configuration writes")
    // Unsupported file-share environment stops during read-only inspection.
    let localServer=FixtureJamfTransport();localServer.cloud="NONE"
    let local=JamfPublisher(api:try JamfPublisherAPI(connection:connection,secret:"fixture",transport:localServer))
    do{_=try await local.inspect();check(false,"unsupported distribution is actionable")}catch{check(error.localizedDescription.contains("File-share"),"unsupported distribution is actionable")}
    let denied=FixtureJamfTransport();denied.failRoute="JSSResource/policies"
    let deniedPublisher=JamfPublisher(api:try JamfPublisherAPI(connection:connection,secret:"TOP_SECRET_DO_NOT_SHOW",transport:denied))
    do{_=try await deniedPublisher.inspect();check(false,"HTTP permission failure handled")}catch{check(error.localizedDescription.contains("403") && !error.localizedDescription.contains("TOP_SECRET_DO_NOT_SHOW"),"HTTP permission failure gives actionable status without echoing response secrets")}
    try await runJamfNameChecks(root:root,connection:connection)
    try await runJamfDeploymentChecks(root:root,connection:connection)
    try runSelfServiceBootstrapChecks(root:root)
    try await runBundledDependencyChecks(root:root,connection:connection)
    try await runPolicyStateChecks(root:root,connection:connection)
    try await runValidationReasonChecks(connection:connection)
    await api.disconnect()
}

func runJamfNameChecks(root:URL,connection:JamfPublisherConnection) async throws {
    let kit=root.appendingPathComponent("rename-kit")
    try FileManager.default.createDirectory(at:kit,withIntermediateDirectories:false)
    for name in ["PUSH-Client-1.16.7.pkg","PUSH-Repair-Client.pkg","PUSH-SelfService-Profiles.pkg","Jamf-Offer-macOS-26.sh","Jamf-Offer-macOS-27.sh"] {try FileManager.default.copyItem(at:root.appendingPathComponent(name),to:kit.appendingPathComponent(name))}
    let server=FixtureJamfTransport(),api=try JamfPublisherAPI(connection:connection,secret:"fixture",transport:server),publisher=JamfPublisher(api:api,receiptSearchRoot:root)
    publisher.pollDelayNanoseconds=0
    let project=UUID(),settings=SelfServiceSettings()
    let plan=try await publisher.prepare(kit:kit,project:project,settings:settings,group:.init(id:9,name:"Approved Pilot"),draftHash:"names")
    var receipt=try await publisher.publish(plan)
    // Existing released receipts have no role metadata.
    receipt.objects=receipt.objects.map{var item=$0;item.role=nil;return item}
    let receiptURL=kit.appendingPathComponent("Jamf-publish-receipt.json")
    try JSONEncoder().encode(receipt).write(to:receiptURL)
    let editor=JamfNameEditor(api:api),record=JamfPublishedRecord(url:receiptURL,receipt:receipt)
    let review=try await editor.review(record:record)
    check(review.policies.count==3 && Set(review.policies.map(\.role))==Set(["client","macOS-26","macOS-27"]),"legacy receipts resolve policy roles by deployment identity")
    let before=server.requests.count
    let names=Dictionary(uniqueKeysWithValues:review.policies.map{($0.id,$0.role=="client" ? "IT - Install PUSH":"IT - Upgrade "+$0.role)})
    let result=try await editor.apply(review,policyNames:names,groupName:"IT - Pilot & Test")
    let writes=server.requests.dropFirst(before).filter{$0.httpMethod != "GET"}
    check(writes.count==4 && writes.allSatisfy{$0.httpMethod=="PUT"},"rename changes only existing policies and group; no creation/upload/activation")
    check(Set(result.policies.map(\.id))==Set(review.policies.map(\.id)) && result.groupID==9,"friendly names preserve immutable Jamf IDs")
    check(result.text.contains("IT - Pilot & Test") && result.policies.allSatisfy{result.text.contains($0.name) && result.text.contains(String($0.id))},"rename success gives actual names and IDs")
    check(server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/general/enabled"))=="false"},"renaming never enables disabled policies")
    for item in review.policies {let nameCheck1=try JamfNamePolicy.protectedSignature(item.xml,kind:"policies")==JamfNamePolicy.protectedSignature(server.policies[item.id]!,kind:"policies");check(nameCheck1,"rename preserves policy scope, triggers, packages and script settings "+item.role)}
    let nameCheck2=try JamfPublisherPolicy.value(server.groupXML[9]!,"/computer_group/computers/computer/id")=="77"
    check(nameCheck2,"static pilot membership is preserved when renaming")
    let saved=try JSONDecoder().decode(JamfPublisherReceipt.self,from:Data(contentsOf:receiptURL))
    check(saved.objects.filter{$0.kind=="policies"}.allSatisfy{$0.role != nil && names[$0.id]==$0.name},"receipt persists renamed IDs and explicit roles")
    var doc=ConfigDocument.fresh;doc.jamfDeploymentID=project;doc.jamfObjectBindings=result.bindings
    let restored=try SavedWorkflow(name:"Named deployment",document:doc,wallpaperData:[:]).restoredDocument()
    check(restored.jamfObjectBindings?.policyIDs==result.bindings?.policyIDs && restored.jamfObjectBindings?.groupID==9,"saved workflows retain renamed object bindings without credentials")
    let again=try await publisher.prepare(kit:kit,project:project,settings:settings,group:nil,draftHash:"names")
    check(Set(again.policies.map(\.name))==Set(names.values) && again.group?.name=="IT - Pilot & Test","re-publish resolves renamed policies and group by receipt IDs")
    let second=try await publisher.publish(again)
    check(server.policies.count==3 && second.objects.filter{$0.kind=="policies"}.allSatisfy{$0.action=="Updated"},"re-publish updates renamed policies without duplicates")
    _=try await publisher.enablePilot(again,receipt:second)
    check(server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/general/enabled"))=="true"},"renamed offer policies still resolve their original script IDs for activation")
    let current=JamfPublishedRecord(url:receiptURL,receipt:try JSONDecoder().decode(JamfPublisherReceipt.self,from:Data(contentsOf:receiptURL)))
    let activeReview=try await editor.review(record:current)
    let policy=activeReview.policies.first!
    _=try await editor.apply(activeReview,policyNames:[policy.id:"IT - Renamed Active Policy"],groupName:activeReview.group.name)
    check(server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/general/enabled"))=="true"},"rename preserves already-enabled policy state")
    let smart=Data("<computer_group><id>9</id><name>IT - Pilot &amp; Test</name><is_smart>true</is_smart><site><id>-1</id></site><criteria><criterion><name>Operating System Version</name><priority>0</priority><and_or>and</and_or><search_type>less than</search_type><value>26.0</value><opening_paren>false</opening_paren><closing_paren>false</closing_paren></criterion></criteria><computers><computer><id>77</id></computer></computers></computer_group>".utf8)
    server.groupXML[9]=smart
    let latest=JamfPublishedRecord(url:receiptURL,receipt:try JSONDecoder().decode(JamfPublisherReceipt.self,from:Data(contentsOf:receiptURL)))
    let smartReview=try await editor.review(record:latest),smartBefore=server.requests.count
    _=try await editor.apply(smartReview,policyNames:[:],groupName:"IT - Smart Upgrade Pilot")
    check(smartReview.group.role=="smart" && server.requests.dropFirst(smartBefore).filter{$0.httpMethod=="PUT"}.count==1,"smart group-only rename needs only one group write")
    let nameCheck3=try JamfNamePolicy.protectedSignature(smart,kind:"computergroups")==JamfNamePolicy.protectedSignature(server.groupXML[9]!,kind:"computergroups")
    check(nameCheck3,"smart group rename preserves ordered criteria and all protected settings")
    let membership=try JamfPublisherPolicy.xml(String(decoding:smart,as:UTF8.self));try membership.nodes(forXPath:"/computer_group/computers/computer/id").first!.stringValue="88"
    let nameCheck4=try JamfNamePolicy.protectedSignature(smart,kind:"computergroups")==JamfNamePolicy.protectedSignature(membership.xmlData,kind:"computergroups")
    check(nameCheck4,"computed smart membership may refresh without altering criteria")
    try membership.nodes(forXPath:"/computer_group/criteria/criterion/value").first!.stringValue="27.0"
    let nameCheck5=try JamfNamePolicy.protectedSignature(smart,kind:"computergroups") != JamfNamePolicy.protectedSignature(membership.xmlData,kind:"computergroups")
    check(nameCheck5,"changed smart criteria are detected")
    for invalid in [""," \n ","Bad\nName",String(repeating:"x",count:201)] {do{_=try JamfNamePolicy.validated(invalid);check(false,"invalid name rejected")}catch{check(true,"invalid name rejected")}}
    let finalRecord=JamfPublishedRecord(url:receiptURL,receipt:try JSONDecoder().decode(JamfPublisherReceipt.self,from:Data(contentsOf:receiptURL)))
    let fresh=try await editor.review(record:finalRecord)
    server.groups.append(["id":10,"name":"Taken"])
    let collisionBefore=server.requests.filter{$0.httpMethod=="PUT"}.count
    do{_=try await editor.apply(fresh,policyNames:[:],groupName:"taken");check(false,"duplicate group name rejected")}catch{check(true,"duplicate group name rejected")}
    check(server.requests.filter{$0.httpMethod=="PUT"}.count==collisionBefore,"name collision causes no writes")
    server.groupXML[9]=membership.xmlData
    do{_=try await editor.apply(fresh,policyNames:[:],groupName:"Another Pilot");check(false,"remote drift blocks rename")}catch{check(true,"remote drift blocks rename")}
    check(server.requests.filter{$0.httpMethod=="PUT"}.count==collisionBefore,"remote drift is detected before any rename write")
    let smaller=SelfServiceSettings();var one=smaller;one.offer27=false
    let reduced=try await publisher.prepare(kit:kit,project:project,settings:one,group:nil,draftHash:"names")
    check(reduced.existing.filter{$0.kind=="policies"}.count==3 && reduced.policies.count==2,"removed renamed offers remain tracked for pausing on later publish")
    let copyKit=root.appendingPathComponent("new-kit");try FileManager.default.createDirectory(at:copyKit,withIntermediateDirectories:false)
    for file in try FileManager.default.contentsOfDirectory(at:kit,includingPropertiesForKeys:nil) where !file.lastPathComponent.hasPrefix("Jamf-publish-") {try FileManager.default.copyItem(at:file,to:copyKit.appendingPathComponent(file.lastPathComponent))}
    let linkedPublisher=JamfPublisher(api:api)
    let linked=try await linkedPublisher.prepare(kit:copyKit,project:project,settings:settings,group:nil,draftHash:"names",bindings:restored.jamfObjectBindings)
    check(Set(linked.policies.map(\.name))==Set(server.policies.values.compactMap{try? JamfPublisherPolicy.value($0,"/policy/general/name")}),"saved ID bindings resolve renamed policies from a new export kit")
    check(JamfPublishedRecord.records(root:root,server:"https://other.test",project:project).isEmpty && JamfPublishedRecord.records(root:root,server:connection.server,project:UUID()).isEmpty,"receipt lookup isolates server and workflow identity")
    await api.disconnect()
}

func runJamfDeploymentChecks(root:URL,connection:JamfPublisherConnection) async throws {
    var deployment=JamfDeploymentSettings();deployment.mode = .required
    var source=ConfigDocument.fresh
    source.edits["apps.enabled"]="true";source.edits["entra.enabled"]="true";source.edits["uptime.enabled"]="true"
    source.edits["schedule.respectAlertWindow"]="true";source.edits["schedule.skipWeekends"]="true";source.edits["debug.dryRun"]="true"
    let campaign=try deployment.document(from:source)
    check(campaign.setupValue("update.toastIntervalSeconds")=="3600" && campaign.setupValue("update.nudgeIntervalSeconds")=="86400","required workflow packages hourly toasts and daily full reminders")
    check(campaign.setupFlag("auto.enabled") && !campaign.setupFlag("debug.dryRun") && campaign.setupFlag("update.autoInstallAfterDeadline"),"required workflow enables live campaign and deadline enforcement")
    check(!campaign.setupFlag("schedule.respectAlertWindow") && !campaign.setupFlag("schedule.skipWeekends") && !campaign.setupFlag("schedule.skipDuringMeetings"),"required reminders are allowed 24/7 including weekends")
    check(!campaign.setupFlag("apps.enabled") && !campaign.setupFlag("entra.enabled") && !campaign.setupFlag("uptime.enabled"),"required macOS workflow does not activate unrelated draft modules")
    check(campaign.setupFlag("auth.promptUserForInstall") && campaign.setupFlag("update.prepareAtDeadlineWhenLoggedOut"),"required workflow keeps user Keychain authorization and logged-out preparation")
    check(campaign.setupValue("auto.maximumMajorVersion")=="26" && campaign.setupValue("auto.enforceMinimumMajorVersion")=="26","required workflow bounds stable discovery to the chosen generation")
    check(campaign.setupValue("toast.message").contains("macOS Tahoe") && !campaign.setupValue("ui.majorMessage").isEmpty,"required campaign provides suggested user messages")
    source.edits["toast.message"]="IT custom notice";let custom=try deployment.document(from:source)
    check(custom.setupValue("toast.message")=="IT custom notice","required workflow preserves administrator custom wording")
    var managed=deployment;managed.campaign.authorization = .managed
    let managedPolicy=try managed.document(from:source)
    check(!managedPolicy.setupFlag("auth.promptUserForInstall"),"managed campaign authorization does not silently enable password prompts")
    try deployment.validatePolicy(campaign.yaml)
    check(true,"packaged required rules validate against the reviewed workflow")
    let enginePolicy=CLIConfig.parse(yaml:campaign.yaml)
    check(enginePolicy.update.toastIntervalSeconds==3600 && enginePolicy.update.nudgeIntervalSeconds==86400,"client parser reads hourly and daily intervals from exported YAML")
    var changed=campaign;changed.edits["update.toastIntervalSeconds"]="999"
    do{try deployment.validatePolicy(changed.yaml);check(false,"changed campaign cadence rejected")}catch{check(true,"changed campaign cadence rejected")}
    var expired=deployment;expired.campaign.deadline=Date().addingTimeInterval(-60)
    do{try expired.validate();check(false,"past required deadline rejected before build/publish")}catch{check(true,"past required deadline rejected before build/publish")}
    var archived=ConfigDocument.fresh;archived.jamfDeploymentSettings=deployment
    let restored=try SavedWorkflow(name:"Required campaign",document:archived,wallpaperData:[:]).restoredDocument()
    check(restored.jamfDeploymentSettings?.mode == .required && restored.jamfDeploymentSettings?.campaign.deadline==deployment.campaign.deadline,"required deployment choice and deadline survive saved workflows")
    let kit=root.appendingPathComponent("required-kit");try FileManager.default.createDirectory(at:kit,withIntermediateDirectories:false)
    try Data("FIXTURE CONFIGURED CLIENT".utf8).write(to:kit.appendingPathComponent("PUSH-Client-1.16.7.pkg"))
    try JSONEncoder().encode(deployment).write(to:kit.appendingPathComponent("Jamf-deployment.json"));try Data(campaign.yaml.utf8).write(to:kit.appendingPathComponent("Required-update-config.yaml"))
    var noOffers=SelfServiceSettings();noOffers.offer26=false;noOffers.offer27=false
    let server=FixtureJamfTransport(),api=try JamfPublisherAPI(connection:connection,secret:"fixture",transport:server),publisher=JamfPublisher(api:api);publisher.pollDelayNanoseconds=0
    let project=UUID(),plan=try await publisher.prepare(kit:kit,project:project,settings:noOffers,group:.init(id:9,name:"Approved Pilot"),draftHash:"required",deployment:deployment)
    check(plan.profiles==nil && plan.policies.count==1 && plan.policies[0].major==nil,"required-only plan creates one campaign policy without offer profiles")
    check(plan.summary.contains("3,600") && plan.summary.contains("86,400") && plan.summary.contains("deadline"),"required review discloses cadence, enforcement and live monitoring")
    let receipt=try await publisher.publish(plan)
    check(receipt.verified && !receipt.enabled && server.policies.count==1 && server.scripts.isEmpty && server.packages.count==1,"required publish uploads configured client only and leaves campaign disabled")
    let policy=server.policies.values.first!
    let checkin=try JamfPublisherPolicy.value(policy,"/policy/general/trigger_checkin"),frequency=try JamfPublisherPolicy.value(policy,"/policy/general/frequency"),selfService=try JamfPublisherPolicy.value(policy,"/policy/self_service/use_for_self_service")
    check(checkin=="true" && frequency=="Once per computer" && selfService=="false","campaign deploys once per computer at check-in without requiring Self Service click")
    let activated=try await publisher.enablePilot(plan,receipt:receipt)
    check(activated.enabled && activated.message.contains("hourly") && JamfPublishSuccess(plan:plan,receipt:activated)!.nextStep.contains("deadline"),"required activation/success describes live reminders and deadline enforcement truthfully")
    check(server.requests.allSatisfy{JamfPublisherAPI.allowed(method:$0.httpMethod!,path:$0.url!.path.trimmingCharacters(in:CharacterSet(charactersIn:"/")))},"required publishing sends no remote update or restart command")
    var both=deployment;both.mode = .both
    try JSONEncoder().encode(both).write(to:kit.appendingPathComponent("Jamf-deployment.json"))
    try Data("FIXTURE RAW REPAIR CLIENT".utf8).write(to:kit.appendingPathComponent("PUSH-Repair-Client.pkg"))
    try Data("FIXTURE OFFER PROFILES".utf8).write(to:kit.appendingPathComponent("PUSH-SelfService-Profiles.pkg"))
    for major in [26,27] {try Data(SelfServiceKit.script(major:major).utf8).write(to:kit.appendingPathComponent("Jamf-Offer-macOS-\(major).sh"))}
    let combined=try await publisher.prepare(kit:kit,project:project,settings:SelfServiceSettings(),group:.init(id:9,name:"Approved Pilot"),draftHash:"both",deployment:both)
    let combinedReceipt=try await publisher.publish(combined)
    check(combinedReceipt.verified && server.policies.count==4 && server.scripts.count==2 && server.packages.count==3,"combined workflow retains campaign policy and adds isolated optional offers without duplicates")
    let repairItem=combined.policies.first{$0.role=="client-repair"}!
    check(repairItem.eventOnlyRepair && combined.packageFile(for:repairItem)?.sha256 != combined.client.sha256,"combined repair uses raw client, never the campaign configuration replacement")
    let repairPolicy=server.policies.values.first{(try? JamfPublisherPolicy.value($0,"/policy/general/trigger_other"))==combined.clientEvent}!
    check((try? JamfPublisherPolicy.value(repairPolicy,"/policy/general/frequency"))=="Ongoing" && (try? JamfPublisherPolicy.value(repairPolicy,"/policy/general/trigger_checkin"))=="false","combined campaign gets a separate repeatable event-only repair")
    check(server.policies.values.allSatisfy{(try? JamfPublisherPolicy.value($0,"/policy/general/enabled"))=="false"},"switching workflow types pauses reviewed policies before publishing disabled")
    let exportClient=ProcessInfo.processInfo.environment["PUSH_REQUIRED_CLIENT"]
    if let exportClient,let folder=ProcessInfo.processInfo.environment["PUSH_REQUIRED_FOLDER"] {
        let destination=URL(fileURLWithPath:folder)
        try JamfDeploymentKit.write(document:source,settings:noOffers,deployment:deployment,client:URL(fileURLWithPath:exportClient),to:destination,defaultWallpaper:try Data(contentsOf:URL(fileURLWithPath:"Resources/PUSH-NonCompliant.png")))
        let expanded=root.appendingPathComponent("configured-inspection")
        try ConfiguredClientBuilder.command("/usr/sbin/pkgutil",["--expand-full",destination.appendingPathComponent("PUSH-Client-1.16.7.pkg").path,expanded.path],folder:root)
        let base=expanded.appendingPathComponent("Payload/Library/Management/PUSH")
        let yaml=try String(contentsOf:base.appendingPathComponent("config.yaml"),encoding:.utf8)
        try deployment.validatePolicy(yaml)
        let packagedPolicy=ConfigDocument.load(yaml,name:"inspected")
        check(packagedPolicy.setupFlag("compliance.wallpaperEnabled") && FileManager.default.fileExists(atPath:base.appendingPathComponent("assets/wallpapers/PUSH-NonCompliant.png").path),"required client includes enabled noncompliant wallpaper and its actual image")
        check(packagedPolicy.setupValue("update.targetVersion")=="26.0" && packagedPolicy.setupFlag("auto.trackLatest"),"initial generation floor supports first-check wallpaper while latest tracking stays enabled")
        check(ConfigDocument.load(yaml,name:"inspected").setupValue("toast.message")=="IT custom notice","actual campaign package contains reviewed YAML and custom message")
        let post=try String(contentsOf:expanded.appendingPathComponent("Scripts/postinstall"),encoding:.utf8)
        check(post.contains("install_monitor main com.push.autoupdate") && post.contains("firstCheckDelaySeconds\":300") && post.contains("if [[ true == true ]]"),"actual campaign installer loads main monitor with five-minute first-check delay")
        let plist=try PropertyListSerialization.propertyList(from:Data(contentsOf:expanded.appendingPathComponent("Scripts/main-monitor.plist")),format:nil) as! [String:Any]
        check(plist["StartInterval"] as? Int==300 && plist["RunAtLoad"] as? Bool==false && (plist["ProgramArguments"] as? [String])?.suffix(2)==["auto-check","--scheduled"],"actual packaged monitor uses scheduled auto-check every five minutes")
        check(!FileManager.default.fileExists(atPath:destination.appendingPathComponent("PUSH-SelfService-Profiles.pkg").path) && !FileManager.default.fileExists(atPath:destination.appendingPathComponent("Jamf-Offer-macOS-26.sh").path),"required-only kit contains no unused Self Service offer artifacts")
        check(!FileManager.default.fileExists(atPath:expanded.appendingPathComponent("Payload/Applications/PUSH Admin.app").path) && FileManager.default.fileExists(atPath:destination.appendingPathComponent("PUSH-Background-Items.mobileconfig").path),"campaign excludes Admin and exports background approval for MDM deployment")
        let actual=try await publisher.prepare(kit:destination,project:UUID(),settings:noOffers,group:.init(id:9,name:"Approved Pilot"),draftHash:"actual",deployment:deployment)
        check(actual.policies.count==1 && actual.profiles==nil,"publisher prepares the actual configured required-only kit")
        let bothFolder=destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent+"-both")
        try JamfDeploymentKit.write(document:source,settings:SelfServiceSettings(),deployment:both,client:URL(fileURLWithPath:exportClient),to:bothFolder,defaultWallpaper:try Data(contentsOf:URL(fileURLWithPath:"Resources/PUSH-NonCompliant.png")))
        let combinedActual=try await publisher.prepare(kit:bothFolder,project:UUID(),settings:SelfServiceSettings(),group:.init(id:9,name:"Approved Pilot"),draftHash:"actual both",deployment:both)
        check(combinedActual.policies.count==4 && combinedActual.profiles != nil,"actual combined kit prepares campaign plus both optional offers")
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:bothFolder.appendingPathComponent("manifest.json"))) as! [String:Any]
        let entries=manifest["files"] as! [[String:String]]
        let validManifest=try entries.allSatisfy{entry in DeploymentBundle.digest(try Data(contentsOf:bothFolder.appendingPathComponent(entry["path"]!)))==entry["sha256"]}
        check(validManifest,"combined kit manifest covers exact packages, scripts, YAML and MDM approvals")
    }
    await api.disconnect()
}

func runSelfServiceBootstrapChecks(root:URL)throws {
    do {
    let repairRoot=root.appendingPathComponent("repair-runtime"),fm=FileManager.default
    try fm.createDirectory(at:repairRoot,withIntermediateDirectories:false)
    let base=repairRoot.appendingPathComponent("Library/Management/PUSH")
    try fm.createDirectory(at:base.appendingPathComponent("push-ui.app/Contents"),withIntermediateDirectories:true)
    let cli=base.appendingPathComponent("push-cli")
    try Data("#!/bin/bash\necho 'push-cli v1.16.7'\n".utf8).write(to:cli);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:cli.path)
    try PropertyListSerialization.data(fromPropertyList:["CFBundleShortVersionString":"1.16.7"],format:.xml,options:0).write(to:base.appendingPathComponent("push-ui.app/Contents/Info.plist"))
    for name in ["config.yaml","state.json","health/intent-main.json"] {
        let file=base.appendingPathComponent(name);try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(("existing "+name).utf8).write(to:file)
    }
    let stat=repairRoot.appendingPathComponent("stat"),pgrep=repairRoot.appendingPathComponent("pgrep")
    try Data("#!/bin/bash\nmode=$(/usr/bin/stat -f %Lp \"${@: -1}\")\nprintf '0 %s\\n' \"$mode\"\n".utf8).write(to:stat)
    try Data("#!/bin/bash\nexit 1\n".utf8).write(to:pgrep)
    for file in [stat,pgrep] {try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path)}
    for (name,text) in [("preinstall",SelfServiceRepairPackage.preinstall),("postinstall",SelfServiceRepairPackage.postinstall)] {
        let script=repairRoot.appendingPathComponent(name)
        let rewritten=text.replacingOccurrences(of:"/Library/Management",with:repairRoot.path+"/Library/Management").replacingOccurrences(of:"/usr/local",with:repairRoot.path+"/usr/local").replacingOccurrences(of:"/usr/bin/stat",with:stat.path).replacingOccurrences(of:"/usr/bin/pgrep",with:pgrep.path)
        try Data(rewritten.utf8).write(to:script)
        let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/bash");process.arguments=[script.path];process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice;try process.run();process.waitUntilExit()
        check(process.terminationStatus==0,"in-place repair "+name+" completes against isolated existing installation")
    }
    for name in ["config.yaml","state.json","health/intent-main.json"] {check((try? String(contentsOf:base.appendingPathComponent(name),encoding:.utf8))=="existing "+name,"in-place repair preserves "+name)}
    }

    let folder=root.appendingPathComponent("bootstrap-shims");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
    func quote(_ text:String)->String {"'"+text.replacingOccurrences(of:"'",with:"'\\''")+"'"}
    func put(_ name:String,_ text:String)throws->URL {let url=folder.appendingPathComponent(name);try Data(text.utf8).write(to:url);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:url.path);return url}
    let mist=folder.appendingPathComponent("mock-mist")
    let cli=folder.appendingPathComponent("mock-cli"),ui=folder.appendingPathComponent("mock-ui"),jamf=folder.appendingPathComponent("mock-jamf"),calls=folder.appendingPathComponent("offer-calls"),requests=folder.appendingPathComponent("prerequisite-requests")
    func mockClient(_ version:String)->String {"#!/bin/bash\nif [[ \"${1:-}\" == --version ]]; then echo "+quote("push-cli v"+version)+"; exit 0; fi\nprintf '%s\\n' \"$*\" >> "+quote(calls.path)+"\n"}
    let good=try put("good-client",mockClient("1.16.7")),goodUI=try put("good-ui","#!/bin/bash\nexit 0\n")
    let goodMist=try put("good-mist","#!/bin/bash\necho 2.3\n")
    let event="push-client-fixture-0123456789abcdef",original=SelfServiceKit.script(major:26)
    let bound=String(decoding:try SelfServiceKit.binding(Data(original.utf8),event:event),as:UTF8.self)
    check(bound.contains("client_event=\""+event+"\"") && !bound.contains("auto-check"),"bound offer keeps isolated upgrade command and deployment-specific prerequisite")
    for invalid in ["","evil;command","bad\nevent"] {do{_=try SelfServiceKit.binding(Data(original.utf8),event:invalid);check(false,"invalid bootstrap event rejected")}catch{check(true,"invalid bootstrap event rejected")}}
    do{_=try SelfServiceKit.binding(Data("#!/bin/bash\nlegacy offer\n".utf8),event:event);check(false,"legacy kit requires rebuild")}catch{check(error.localizedDescription.contains("Rebuild"),"legacy kit requires rebuild before prerequisite handoff")}
    // Execute only temporary shims: no PUSH binary, Jamf agent, installer, UI,
    // network request or privileged command is executed by these branch tests.
    func run(version:String?,hasUI:Bool,behavior:String,eventEnabled:Bool=true,mistVersion:String?=nil,running:String="26.0")throws->(Int32,String,String,String) {
        for url in [cli,ui,mist,calls,requests] {try? FileManager.default.removeItem(at:url)}
        if let version {_=try put("mock-cli",mockClient(version))}
        if hasUI {_=try put("mock-ui","#!/bin/bash\nexit 0\n")}
        if let mistVersion {_=try put("mock-mist","#!/bin/bash\necho "+quote(mistVersion)+"\n")}
        let action=behavior=="install" ? "/bin/cp "+quote(good.path)+" "+quote(cli.path)+"\n/bin/cp "+quote(goodUI.path)+" "+quote(ui.path)+"\n/bin/cp "+quote(goodMist.path)+" "+quote(mist.path):behavior=="fail" ? "exit 1":"exit 0"
        _=try put("mock-jamf","#!/bin/bash\nprintf '%s\\n' \"$*\" >> "+quote(requests.path)+"\n"+action+"\n")
        var text=eventEnabled ? bound:original
        text=text.replacingOccurrences(of:"[[ \"$EUID\" == 0 ]] || { echo 'Run this script as a Jamf policy.' >&2; exit 1; }",with:"# Nonprivileged branch test with temporary executables only.")
        text=text.replacingOccurrences(of:"cli=/Library/Management/PUSH/push-cli",with:"cli="+quote(cli.path)).replacingOccurrences(of:"ui=/Library/Management/PUSH/push-ui.app/Contents/MacOS/push-ui",with:"ui="+quote(ui.path)).replacingOccurrences(of:"jamf=/usr/local/jamf/bin/jamf",with:"jamf="+quote(jamf.path))
        text=text.replacingOccurrences(of:"current_os=\"$(/usr/bin/sw_vers -productVersion)\"",with:"current_os="+quote(running)).replacingOccurrences(of:"mist=/usr/local/bin/mist",with:"mist="+quote(mist.path)).replacingOccurrences(of:"mist_alt=/opt/homebrew/bin/mist",with:"mist_alt="+quote(mist.path))
        text=text.replacingOccurrences(of:"if ! prerequisites_ready; then",with:"trusted_executable() { [[ -x \"$1\" && ! -L \"$1\" ]]; }\nif ! prerequisites_ready; then")
        let script=try put("test-offer",text),log=folder.appendingPathComponent("output")
        FileManager.default.createFile(atPath:log.path,contents:nil);let handle=try FileHandle(forWritingTo:log);defer{try? handle.close()}
        let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/bash");process.arguments=[script.path];process.standardOutput=handle;process.standardError=handle;process.standardInput=FileHandle.nullDevice;try process.run();process.waitUntilExit()
        return (process.terminationStatus,(try? String(contentsOf:requests,encoding:.utf8)) ?? "",(try? String(contentsOf:calls,encoding:.utf8)) ?? "",(try? String(contentsOf:log,encoding:.utf8)) ?? "")
    }
    let missing=try run(version:nil,hasUI:false,behavior:"install")
    check(missing.0==0 && missing.1=="policy -event "+event+"\n" && missing.2.contains("self-service-upgrade --major 26 --config /Library/Management/PUSH/self-service/macOS-26.yaml"),"missing client requests prerequisite then continues only after client/UI verification")
    for version in ["1.16.7","1.16.8","1.17.0","2.0.0"] {
        let ready=try run(version:version,hasUI:true,behavior:"fail")
        check(ready.0==0 && ready.1.isEmpty && !ready.2.isEmpty,"current/newer client skips reinstallation "+version)
    }
    let old=try run(version:"1.14.0",hasUI:true,behavior:"install")
    check(old.0==0 && !old.1.isEmpty && !old.2.isEmpty,"outdated client requests prerequisite and rechecks before upgrade")
    for version in ["1.16.3","1.16.5","1.16.6"] {
        let repaired=try run(version:version,hasUI:true,behavior:"install")
        check(repaired.0==0 && repaired.1=="policy -event "+event+"\n" && !repaired.2.isEmpty,"older patch release requests client repair before upgrade: "+version)
        let retained=try run(version:version,hasUI:true,behavior:"noop")
        check(retained.0 != 0 && !retained.1.isEmpty && retained.2.isEmpty && retained.3.contains("Installed PUSH client is "+version),"successful prerequisite exit cannot continue with older patch release: "+version)
    }
    let uiMissing=try run(version:"1.16.7",hasUI:false,behavior:"install")
    check(uiMissing.0==0 && !uiMissing.1.isEmpty,"missing matching popup UI requests client repair before upgrade")
    let future=try run(version:"1.17.0",hasUI:false,behavior:"install")
    check(future.0 != 0 && future.1.isEmpty && future.2.isEmpty && future.3.contains("will not downgrade"),"damaged newer client is not silently downgraded by older prerequisite")
    let failed=try run(version:nil,hasUI:false,behavior:"fail")
    check(failed.0 != 0 && !failed.1.isEmpty && failed.2.isEmpty,"failed prerequisite cannot request a macOS installation")
    let skipped=try run(version:nil,hasUI:false,behavior:"noop")
    check(skipped.0 != 0 && skipped.2.isEmpty && skipped.3.contains("Review the specific prerequisite/version errors above"),"successful Jamf exit without installed binary still blocks upgrade with actionable diagnostics")
    let manual=try run(version:nil,hasUI:false,behavior:"install",eventEnabled:false)
    check(manual.0 != 0 && manual.1.isEmpty && manual.2.isEmpty,"manual export without reviewed event cannot invoke arbitrary policy")
    let majorMissingMist=try run(version:"1.16.7",hasUI:true,behavior:"install",running:"15.7")
    check(majorMissingMist.0==0 && !majorMissingMist.1.isEmpty && !majorMissingMist.2.isEmpty,"major upgrade requests missing Mist prerequisite even when PUSH is current")
    let oldMist=try run(version:"1.16.7",hasUI:true,behavior:"install",mistVersion:"2.2",running:"15.7")
    check(oldMist.0==0 && !oldMist.1.isEmpty,"older Mist is replaced by the reviewed prerequisite before major discovery")
    let presentMist=try run(version:"1.16.7",hasUI:true,behavior:"fail",mistVersion:"2.3",running:"15.7")
    check(presentMist.0==0 && presentMist.1.isEmpty,"current Mist and PUSH skip prerequisite reinstallation")
    for version in ["2.3 (latest: 2.3)","2.3 (Unable to check for latest version)","2.3.1 (latest: 2.4)"] {
        let result=try run(version:"1.16.7",hasUI:true,behavior:"fail",mistVersion:version,running:"15.7")
        check(result.0==0 && result.1.isEmpty && !result.2.isEmpty,"installed Mist version accepts suffix without reinstalling: "+version)
    }
    for version in ["2.2 (latest: 2.3)","Error checking latest 2.3","2.3-beta"] {
        let result=try run(version:"1.16.7",hasUI:true,behavior:"fail",mistVersion:version,running:"15.7")
        check(result.0 != 0 && result.2.isEmpty,"latest-version text cannot authorize an old or invalid Mist: "+version)
    }
    let retainedOldClient=try run(version:"1.15.2",hasUI:true,behavior:"noop",mistVersion:"2.3 (latest: 2.3)",running:"26.7.3")
    check(retainedOldClient.0 != 0 && retainedOldClient.2.isEmpty && retainedOldClient.3.contains("Installed PUSH client is 1.15.2"),"successful prerequisite exit with old binary identifies exact installed version and blocks upgrade")
    let minorNoMist=try run(version:"1.16.7",hasUI:true,behavior:"fail",running:"26.1")
    check(minorNoMist.0==0 && minorNoMist.1.isEmpty,"same-generation point update does not require Mist")
    let futureMissingMist=try run(version:"1.17.0",hasUI:true,behavior:"install",running:"15.7")
    check(futureMissingMist.0 != 0 && futureMissingMist.1.isEmpty && futureMissingMist.2.isEmpty,"repairing missing Mist cannot downgrade a newer PUSH client")
    // Exercise the actual root/permission checker independently, without an
    // execution path to either the fake or installed CLI/Jamf agent.
    let start=bound.range(of:"trusted_executable() {")!.lowerBound,end=bound.range(of:"client_version_ok() {")!.lowerBound
    _=try put("mock-cli",mockClient("1.16.7"))
    let checker=String(bound[start..<end])+"\ntrusted_executable "+quote(cli.path)+"\n"
    let checkScript=try put("check-ownership",checker),process=Process();process.executableURL=URL(fileURLWithPath:"/bin/bash");process.arguments=[checkScript.path];process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice;try process.run();process.waitUntilExit()
    check(process.terminationStatus != 0,"real ownership checker rejects a user-writable client path")
}

func runBundledDependencyChecks(root:URL,connection:JamfPublisherConnection) async throws {
    let mist=URL(fileURLWithPath:"Resources/mist-cli.2.3.pkg")
    try JamfBundledDependencies.validateMist(mist)
    check(true,"bundled Mist matches the pinned official release checksum")
    let damaged=root.appendingPathComponent("damaged-mist.pkg");try Data("modified".utf8).write(to:damaged)
    do{try JamfBundledDependencies.validateMist(damaged);check(false,"modified Mist rejected")}catch{check(true,"modified bundled Mist is rejected before export")}
    var deployment=JamfDeploymentSettings()
    check(deployment.needsMist,"optional offers automatically select bundled Mist")
    deployment.mode = .required
    let policy=try deployment.document(from:.fresh)
    check(deployment.useWallpaper && policy.setupFlag("compliance.wallpaperEnabled") && policy.setupValue("compliance.nonCompliantWallpaper")==WallpaperPolicy.defaultImage,"required workflow defaults to packaged noncompliant wallpaper")
    check(policy.setupValue("update.targetVersion")=="26.0" && policy.setupFlag("auto.trackLatest"),"first-check wallpaper has a generation floor without pinning discovery to 26.0")
    deployment.wallpaperEnabled=false
    let disabled=try deployment.document(from:.fresh)
    check(!disabled.setupFlag("compliance.wallpaperEnabled") && disabled.setupValue("compliance.nonCompliantWallpaper").isEmpty,"administrator can explicitly disable campaign wallpaper")
    deployment.campaign.target = .current
    check(!deployment.needsMist,"current-generation required updates do not add an unnecessary Mist prerequisite")
    let optional=try SelfServiceKit.profile(policy,major:26)
    check(!optional.setupFlag("compliance.wallpaperEnabled"),"optional offer profiles do not activate independent wallpaper enforcement")
    let kit=root.appendingPathComponent("dependency-kit");try FileManager.default.createDirectory(at:kit,withIntermediateDirectories:false)
    for name in ["PUSH-Client-1.16.7.pkg","PUSH-Repair-Client.pkg","PUSH-SelfService-Profiles.pkg","Jamf-Offer-macOS-26.sh","Jamf-Offer-macOS-27.sh"] {try FileManager.default.copyItem(at:root.appendingPathComponent(name),to:kit.appendingPathComponent(name))}
    let server=FixtureJamfTransport(),api=try JamfPublisherAPI(connection:connection,secret:"fixture",transport:server),publisher=JamfPublisher(api:api);publisher.pollDelayNanoseconds=0
    let project=UUID(),settings=SelfServiceSettings(),group=JamfPublisherGroup(id:9,name:"Approved Pilot")
    let old=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:"without mist")
    let first=try await publisher.publish(old),oldClient=first.objects.first{$0.kind=="policies" && $0.role=="client"}!
    let legacyEvent="push-client-"+project.uuidString.lowercased()+"-0123456789abcdef"
    let legacyXML=try JamfPublisherPolicy.xml(String(decoding:server.policies[oldClient.id]!,as:UTF8.self))
    try legacyXML.nodes(forXPath:"/policy/general/trigger_other").first!.stringValue=legacyEvent
    server.policies[oldClient.id]=legacyXML.xmlData
    let withMist=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:"with mist",mistURL:mist,bindings:JamfObjectBindings(receipt:first))
    check(withMist.clientIdentity != old.clientIdentity && withMist.clientEvent == legacyEvent,"dependency hash changes while the repeatable repair trigger stays stable")
    check(withMist.policies.first!.name == old.policies.first!.name,"adding Mist reuses the repeatable repair policy without a history reset")
    let second=try await publisher.publish(withMist),newClient=second.objects.first{$0.kind=="policies" && $0.role=="client"}!
    check(newClient.id == oldClient.id && server.policies.count==3,"new dependencies update the same repair policy and preserve offer IDs")
    let oldEnabled=try JamfPublisherPolicy.value(server.policies[oldClient.id]!,"/policy/general/enabled")
    check(oldEnabled=="false","superseded client prerequisite is paused")
    let packages=try JamfPublisherPolicy.xml(String(decoding:server.policies[newClient.id]!,as:UTF8.self)).nodes(forXPath:"/policy/package_configuration/packages/package/id")
    check(packages.count==2 && server.packages.count==3,"new prerequisite deploys PUSH and the bundled Mist together")
    let bindings=JamfObjectBindings(receipt:second)!
    check(bindings.clientDependencySignature==withMist.clientIdentity,"saved bindings retain the exact reviewed client/Mist dependency identity")
    let again=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:"repeat",mistURL:mist,bindings:bindings)
    _=try await publisher.publish(again)
    check(server.policies.count==3 && again.policies.first!.name==newClient.name,"unchanged bundled dependencies do not duplicate prerequisite policies on re-publish")
    if let client=ProcessInfo.processInfo.environment["PUSH_REQUIRED_CLIENT"],let output=ProcessInfo.processInfo.environment["PUSH_REQUIRED_FOLDER"] {
        let folder=URL(fileURLWithPath:output+"-custom-wallpaper")
        var custom=ConfigDocument.fresh
        let image=try WallpaperAssetImage.normalizedPNG(Data(contentsOf:URL(fileURLWithPath:"Tests/Fixtures/red-pixel.png")))
        let ref=WallpaperAssetReference(role:"noncompliant",digest:WallpaperAssetImage.digest(image),originalName:"IT custom background.png")
        let staged=root.appendingPathComponent("custom-wallpaper-assets");try FileManager.default.createDirectory(at:staged,withIntermediateDirectories:false);try image.write(to:staged.appendingPathComponent(ref.fileName))
        custom.wallpaperAssets=["noncompliant":ref];custom.edits["compliance.nonCompliantWallpaper"]=ref.deployedPath
        var required=JamfDeploymentSettings();required.mode = .required
        try JamfDeploymentKit.write(document:custom,settings:settings,deployment:required,client:URL(fileURLWithPath:client),to:folder,wallpaperFolder:staged)
        let expanded=root.appendingPathComponent("custom-wallpaper-inspection");try ConfiguredClientBuilder.command("/usr/sbin/pkgutil",["--expand-full",folder.appendingPathComponent("PUSH-Client-1.16.7.pkg").path,expanded.path],folder:root)
        let base=expanded.appendingPathComponent("Payload/Library/Management/PUSH")
        let customImage=try Data(contentsOf:base.appendingPathComponent("assets/wallpapers/"+ref.fileName))
        check(customImage==image,"actual configured client contains the selected custom wallpaper bytes")
        let customYAML=try String(contentsOf:base.appendingPathComponent("config.yaml"),encoding:.utf8)
        check(ConfigDocument.load(customYAML,name:"custom").setupValue("compliance.nonCompliantWallpaper")==ref.deployedPath,"actual wallpaper YAML points at its packaged managed path")
        let offerFolder=URL(fileURLWithPath:output+"-self-service-mist")
        try SelfServiceKit.write(document:.fresh,settings:settings,client:URL(fileURLWithPath:client),to:offerFolder,mist:mist)
        let exportedMist=try Data(contentsOf:offerFolder.appendingPathComponent("Approved-Mist.pkg")),originalMist=try Data(contentsOf:mist)
        check(exportedMist==originalMist,"manual Self Service export includes the verified Mist installer by default through Admin")
    }
    await api.disconnect()
}

func runPolicyStateChecks(root:URL,connection:JamfPublisherConnection) async throws {
    for (literal,expected) in [("false",false),("0",false),(" \nfalse\n ",false),("true",true),("1",true)] {
        let xml=Data("<policy><general><enabled>\(literal)</enabled></general></policy>".utf8)
        let actual=try JamfPublisherPolicy.policyState(xml)
        check(actual==(expected ? .enabled:.disabled),"strict XML enabled flag recognizes boolean form "+literal.trimmingCharacters(in:.whitespacesAndNewlines))
    }
    for (fields,expected) in [("",JamfPublisherPolicy.PolicyState.missing),("<enabled/>",.invalid),("<enabled>yes</enabled>",.invalid),("<enabled>false</enabled><enabled>true</enabled>",.ambiguous)] {
        let xml=Data("<policy><general>\(fields)</general></policy>".utf8)
        let actual=try JamfPublisherPolicy.policyState(xml)
        check(actual==expected,"missing/malformed/ambiguous enabled state never implies disabled")
    }
    let kit=root.appendingPathComponent("policy-state-kit");try FileManager.default.createDirectory(at:kit,withIntermediateDirectories:false)
    for name in ["PUSH-Client-1.16.7.pkg","PUSH-Repair-Client.pkg","PUSH-SelfService-Profiles.pkg","Jamf-Offer-macOS-26.sh","Jamf-Offer-macOS-27.sh"] {try FileManager.default.copyItem(at:root.appendingPathComponent(name),to:kit.appendingPathComponent(name))}
    let server=FixtureJamfTransport(),api=try JamfPublisherAPI(connection:connection,secret:"fixture",transport:server),publisher=JamfPublisher(api:api);publisher.pollDelayNanoseconds=0
    let project=UUID(),settings=SelfServiceSettings(),group=JamfPublisherGroup(id:9,name:"Approved Pilot")
    let initial=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:"state")
    let receipt=try await publisher.publish(initial)
    server.lagReadsOnStateWrite=2
    let beforeEnable=server.requests.count
    let enabled=try await publisher.enablePilot(initial,receipt:receipt)
    check(enabled.enabled,"activation confirms delayed read-back without interpreting old false as failure")
    check(server.requests.dropFirst(beforeEnable).filter{$0.httpMethod=="PUT"}.count==3,"activation sends only one write per policy while retrying reads")
    let pausePlan=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:"state")
    let beforePause=server.requests.count
    let paused=try await publisher.publish(pausePlan)
    check(paused.verified && !paused.enabled,"publishing waits for confirmed pause before replacing scripts/packages")
    let writes=server.requests.dropFirst(beforePause).filter{$0.httpMethod=="PUT" && $0.url?.path.contains("/policies/")==true}
    check(writes.count==6,"pause uses one state write then one reviewed policy update; stale reads never repeat writes")
    let next=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:"state")
    let beforeDisabled=server.requests.count
    _=try await publisher.publish(next)
    let disabledWrites=server.requests.dropFirst(beforeDisabled).filter{$0.httpMethod=="PUT" && $0.url?.path.contains("/policies/")==true}
    check(disabledWrites.count==3,"already-disabled policies skip unnecessary pause writes")
    check(server.requests.filter{$0.httpMethod=="GET"}.allSatisfy{$0.value(forHTTPHeaderField:"Cache-Control")=="no-cache, no-store" && $0.value(forHTTPHeaderField:"Pragma")=="no-cache"},"policy reads explicitly bypass caches")
    server.numericPolicyState=true
    let numeric=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:"numeric")
    let numericReceipt=try await publisher.publish(numeric)
    check(numericReceipt.verified,"XML 0 disabled state passes pause and strict full policy verification")
    let numericEnabled=try await publisher.enablePilot(numeric,receipt:numericReceipt)
    check(numericEnabled.enabled,"XML 1 enabled state confirms explicit activation")
    server.numericPolicyState=false;server.lagReadsOnStateWrite=0;server.ignoreDisable=true
    let refused=try await publisher.prepare(kit:kit,project:project,settings:settings,group:group,draftHash:"refused")
    let refusalBefore=server.requests.count
    do{_=try await publisher.publish(refused);check(false,"unconfirmed pause blocks publishing")}catch{
        check(error.localizedDescription.contains("Policy ID ") && error.localizedDescription.contains("returned enabled") && error.localizedDescription.contains("5 read-back"),"pause failure names exact policy ID, observed state and bounded attempts")
    }
    let afterRefused=server.requests.dropFirst(refusalBefore)
    check(!afterRefused.contains{$0.httpMethod != "GET" && ($0.url?.path.contains("/scripts/")==true || $0.url?.path.contains("/packages")==true)},"unconfirmed pause cannot modify scripts/packages")
    let stored=try JSONDecoder().decode(JamfPublisherReceipt.self,from:Data(contentsOf:kit.appendingPathComponent("Jamf-publish-receipt.json")))
    check(!stored.verified && stored.objects.contains{$0.kind=="pause-attempt"} && stored.message.contains("Unable to confirm pause for policy IDs"),"receipt records failed pause IDs and cleanup uncertainty instead of claiming disabled")
    let missing=Data("<policy><general><name>Missing flag</name></general></policy>".utf8)
    server.policies[999]=missing
    let readsBefore=server.requests.count
    do{_=try await publisher.confirmPolicyState(999,enabled:false);check(false,"missing state cannot confirm pause")}catch{check(error.localizedDescription.contains("999") && error.localizedDescription.contains("missing"),"missing enabled field fails immediately with exact policy ID")}
    check(server.requests.count==readsBefore+1,"malformed state is not repeatedly polled or treated as success")
    await api.disconnect()
}

func runValidationReasonChecks(connection:JamfPublisherConnection) async throws {
    let html=Data("<html><head><title>Conflict</title><style>ignored</style></head><body><h1>Conflict</h1><p>Error: Missing required field self_service_icon.id</p><script>fetch('unsafe')</script></body></html>".utf8)
    let parsed=JamfValidationReason.summary(html,status:409,secrets:[])
    check(parsed=="Error: Missing required field self_service_icon.id","Jamf Classic 409 field validation is extracted from HTML as plain text")
    let json=Data(#"{"errors":[{"description":"Duplicate policy name","code":"CONFLICT"}]}"#.utf8)
    check(JamfValidationReason.summary(json,status:409,secrets:[])=="Duplicate policy name","JSON validation reason is retained")
    let secret="fixture-secret-with-spaces 123",token="fixture-token"
    let risky="Error: password=\"other private value\"; client_secret='another private value'; Authorization: Bearer ABC.def.ghi; \(secret); \(token); https://example.test/?access_token=PRIVATE"
    let clean=JamfValidationReason.sanitized(risky,secrets:[secret,token])
    check(!clean.contains(secret) && !clean.contains(token) && !clean.contains("other private value") && !clean.contains("another private value") && !clean.contains("ABC.def.ghi") && !clean.contains("PRIVATE"),"known secrets, quoted credential values, bearer tokens and token URLs are redacted")
    check(JamfValidationReason.summary(html,status:401,secrets:[])==nil && JamfValidationReason.summary(html,status:403,secrets:[])==nil,"authentication/permission response bodies remain unreported")
    check(JamfValidationReason.summary(Data(repeating:65,count:65537),status:409,secrets:[])==nil,"oversized validation response is omitted")
    check(JamfValidationReason.summary(Data("<!DOCTYPE a [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><p>&secret;</p>".utf8),status:409,secrets:[])==nil,"entity-bearing responses never enter validation diagnostics")
    check(JamfValidationReason.sanitized(String(repeating:"x ",count:2000)).count<=600,"validation messages are length bounded")
    let server=FixtureJamfTransport();server.validationRoute="JSSResource/policies/id/923"
    let api=try JamfPublisherAPI(connection:connection,secret:"fixture-secret",transport:server)
    do{_=try await api.request("PUT","JSSResource/policies/id/923",body:Data("<policy/>".utf8),type:"application/xml");check(false,"HTTP conflict reports field reason")}catch{
        check(error.localizedDescription.contains("HTTP 409") && error.localizedDescription.contains("self_service_icon.id"),"API conflict identifies the server validation field instead of a generic retry hint")
    }
    check(server.requests.filter{$0.httpMethod=="PUT"}.count==1,"validation failure does not automatically repeat a write")
    await api.disconnect()
}
