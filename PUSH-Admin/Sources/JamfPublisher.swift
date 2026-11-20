// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

final class JamfPublisher {
    let api:JamfPublisherAPI
    var progress:(String)->Void={_ in}
    var pollDelayNanoseconds:UInt64=2_000_000_000
    let receiptSearchRoot:URL?
    init(api:JamfPublisherAPI,receiptSearchRoot:URL?=nil){self.api=api;self.receiptSearchRoot=receiptSearchRoot}
    func inspect() async throws->JamfPublisherSnapshot {
        let version=try await api.json("GET","api/v1/jamf-pro-version")
        guard let number=version["version"] as? String,let parts=versionParts(String(number.split(separator:"-").first ?? "")),!parts.lexicographicallyPrecedes([11,5,0]) else {throw JamfPublisherError("Automated publishing requires Jamf Pro 11.5 or later. The export kit remains available.")}
        let distribution=try await api.json("GET","api/v1/cloud-distribution-point")
        guard let kind=distribution["cdnType"] as? String,["JAMF_CLOUD","AMAZON_S3","AKAMAI","RACKSPACE_CLOUD_FILES"].contains(kind) else {throw JamfPublisherError("No supported cloud distribution point was detected. File-share distribution needs the existing export kit/Jamf Sync; no server objects were changed.")}
        let groups=try await api.collection("JSSResource/computergroups",key:"computer_groups")
        let categories=try await api.collection("JSSResource/categories",key:"categories")
        _=try await api.collection("JSSResource/scripts",key:"scripts")
        _=try await api.collection("JSSResource/policies",key:"policies")
        _=try await api.packages()
        let available=groups.compactMap{object->JamfPublisherGroup? in guard let id=JamfPublisherPolicy.id(object),id>0,let name=object["name"] as? String else{return nil};return .init(id:id,name:name)}.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
        let category=categories.first{$0["name"] as? String=="PUSH"}.flatMap(JamfPublisherPolicy.id)
        return .init(groups:available,categoryID:category,version:number,distribution:kind)
    }
    func prepare(kit:URL,project:UUID,settings:SelfServiceSettings,group:JamfPublisherGroup?,draftHash:String,mistURL:URL?=nil,bindings:JamfObjectBindings?=nil,deployment:JamfDeploymentSettings=JamfDeploymentSettings()) async throws->JamfPublisherPlan {
        try deployment.validate()
        if deployment.mode.includesOffers {try settings.validate()}
        let client=try JamfPublisherFile(kit.appendingPathComponent(deployment.mode == .offer ? "PUSH-Repair-Client.pkg":"PUSH-Client-1.16.7.pkg"),prefix:"PUSH-Client-1.16.7")
        let repairClient=try deployment.mode == .both ? JamfPublisherFile(kit.appendingPathComponent("PUSH-Repair-Client.pkg"),prefix:"PUSH-Client-1.16.7"):nil
        let profiles=try deployment.mode.includesOffers ? JamfPublisherFile(kit.appendingPathComponent("PUSH-SelfService-Profiles.pkg"),prefix:"PUSH-Offers"):nil
        if deployment.mode.requiresCampaign {
            let saved=try JSONDecoder().decode(JamfDeploymentSettings.self,from:Data(contentsOf:kit.appendingPathComponent("Jamf-deployment.json")))
            guard saved.mode==deployment.mode,saved.campaign==deployment.campaign else {throw JamfPublisherError("The required deployment does not match the prepared kit. Build/review again.")}
            try deployment.validatePolicy(String(contentsOf:kit.appendingPathComponent("Required-update-config.yaml"),encoding:.utf8))
        }
        let mist=try mistURL.map{try JamfPublisherFile($0,prefix:"PUSH-Mist")}
        let clientIdentity=mist.map{DeploymentBundle.digest(Data((client.sha256+"|"+$0.sha256).utf8))} ?? client.sha256
        if deployment.mode.includesOffers {
            let event="push-client-"+project.uuidString.lowercased()+"-repair"
            for major in settings.majors {_ = try SelfServiceKit.binding(Data(contentsOf:kit.appendingPathComponent("Jamf-Offer-macOS-\(major).sh")),event:event)}
        }
        let prefix="PUSH "+project.uuidString+" · "
        var policies=[JamfPublisherPolicyItem(role:"client",name:prefix+"Client "+String(clientIdentity.prefix(16)),title:deployment.mode.requiresCampaign ? "PUSH required-update campaign":"PUSH client prerequisite",description:deployment.mode.requiresCampaign ? deployment.summary:"Install the PUSH client only. No macOS upgrade is requested by this policy.",major:nil,eventOnlyRepair:deployment.mode == .offer)]
        if deployment.mode == .both {policies.append(.init(role:"client-repair",name:prefix+"Client Repair",title:"PUSH Self Service client repair",description:"Repair PUSH and Mist only when requested by a Self Service offer. Existing configuration and credentials are preserved.",major:nil,eventOnlyRepair:true))}
        policies+=(deployment.mode.includesOffers ? settings.majors:[]).map{.init(role:"macOS-\($0)",name:prefix+"macOS \($0)",title:settings.title($0),description:settings.description($0),major:$0)}
        let scripts=try await api.collection("JSSResource/scripts",key:"scripts"),remotePolicies=try await api.collection("JSSResource/policies",key:"policies")
        let linked=bindings.flatMap{$0.server==api.base.absoluteString && $0.project==project ? $0:nil}
        let records=JamfPublishedRecord.records(root:receiptSearchRoot,kit:kit,server:api.base.absoluteString,project:project)
        var existing:[JamfPublisherRemote]=[]
        for (kind,objects,names) in [("scripts",scripts,(deployment.mode.includesOffers ? settings.majors:[]).map{prefix+"macOS \($0)"}),("policies",remotePolicies,remotePolicies.compactMap{$0["name"] as? String}.filter{$0.hasPrefix(prefix+"Client ") || $0==prefix+"macOS 26" || $0==prefix+"macOS 27"})] {
            for name in Set(names) {
                let matches=objects.filter{$0["name"] as? String==name}
                guard matches.count<=1 else {throw JamfPublisherError("Duplicate owned Jamf object names were found. Resolve them before publishing.")}
                if let object=matches.first,let id=JamfPublisherPolicy.id(object),id>0 {
                    let data=try await api.request("GET","JSSResource/\(kind)/id/\(id)",accept:"application/xml").data
                    guard try JamfPublisherPolicy.value(data,kind=="policies" ? "/policy/general/name":"/script/name")==name else {throw JamfPublisherError("A Jamf object changed identity while reviewing.")}
                    if kind=="scripts" {guard try JamfPublisherPolicy.value(data,"/script/notes").contains("PUSH-Deployment:"+project.uuidString) else {throw JamfPublisherError("An existing script lacks this deployment's ownership marker. It was not changed.")}}
                    existing.append(.init(id:id,kind:kind,name:name,xml:data,role:kind=="policies" ? policies.first(where:{$0.name==name})?.role:nil))
                }
            }
        }
        // Receipts bind roles to immutable server IDs. Display names may be
        // edited in Admin or Jamf without creating another policy on re-publish.
        for item in policies {
            let binding=JamfPublishedRecord.policyBinding(item.role,records:records,clientFile:item.role=="client" && !item.eventOnlyRepair ? client.fileName:nil,dependencySignature:item.eventOnlyRepair || mist==nil ? nil:clientIdentity)
            let linkedID=(item.role != "client" || item.eventOnlyRepair || (linked?.clientFile==client.fileName && (mist==nil || linked?.clientDependencySignature==clientIdentity))) ? linked?.policyIDs[item.role]:nil
            if let boundID=linkedID ?? binding?.id {
                if let index=existing.firstIndex(where:{$0.kind=="policies" && $0.id==boundID}) {existing[index].role=item.role;continue}
                guard remotePolicies.contains(where:{JamfPublisherPolicy.id($0)==boundID}) else {throw JamfPublisherError("A recorded published policy was deleted. Review the deployment identity before creating a replacement.")}
                let xml=try await api.request("GET","JSSResource/policies/id/\(boundID)",accept:"application/xml").data
                let name=try JamfPublisherPolicy.value(xml,"/policy/general/name")
                guard !name.isEmpty else {throw JamfPublisherError("The bound policy name could not be verified.")}
                existing.append(.init(id:boundID,kind:"policies",name:name,xml:xml,role:item.role))
            }
        }
        // Include retired policies by recorded ID so a renamed, removed offer
        // or older client prerequisite is still paused during re-publishing.
        let ownedIDs=Set(records.flatMap{$0.receipt.objects.filter{$0.kind=="policies"}.map(\.id)}+Array(linked?.policyIDs.values ?? Dictionary<String,Int>().values))
        for id in ownedIDs where !existing.contains(where:{$0.kind=="policies" && $0.id==id}) && remotePolicies.contains(where:{JamfPublisherPolicy.id($0)==id}) {
            let xml=try await api.request("GET","JSSResource/policies/id/\(id)",accept:"application/xml").data
            existing.append(.init(id:id,kind:"policies",name:try JamfPublisherPolicy.value(xml,"/policy/general/name"),xml:xml,role:nil))
        }
        policies=policies.map{item in
            guard let remote=existing.first(where:{$0.kind=="policies" && $0.role==item.role}) else{return item}
            return .init(role:item.role,name:remote.name,title:item.title,description:item.description,major:item.major,eventOnlyRepair:item.eventOnlyRepair)
        }
        let groups=try await api.collection("JSSResource/computergroups",key:"computer_groups")
        var resolvedGroup=group
        if resolvedGroup==nil,let id=linked?.groupID,let object=groups.first(where:{JamfPublisherPolicy.id($0)==id}),let name=object["name"] as? String {resolvedGroup = .init(id:id,name:name)}
        if resolvedGroup==nil,let binding=records.compactMap({$0.receipt.objects.first{$0.kind=="groups"}}).first,let object=groups.first(where:{JamfPublisherPolicy.id($0)==binding.id}),let name=object["name"] as? String {resolvedGroup = .init(id:binding.id,name:name)}
        if let group=resolvedGroup {guard groups.contains(where:{JamfPublisherPolicy.id($0)==group.id && $0["name"] as? String==group.name}) else {throw JamfPublisherError("The selected pilot group changed. Refresh the connection and choose it again.")}}
        let name="PUSH Pilot "+project.uuidString
        let icon=kit.appendingPathComponent("Self-Service-Icon.png")
        var hashes:[String:String]=[:]
        for file in try FileManager.default.contentsOfDirectory(at:kit,includingPropertiesForKeys:[.isRegularFileKey]) where !["Jamf-publish-receipt.json","Jamf-publish-summary.txt"].contains(file.lastPathComponent) {
            guard (try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])).isRegularFile==true,(try file.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else {throw JamfPublisherError("The prepared kit contains an unexpected file.")}
            hashes[file.lastPathComponent]=DeploymentBundle.digest(try Data(contentsOf:file))
        }
        return .init(project:project,connection:api.connection,kit:kit,group:resolvedGroup,groupName:resolvedGroup?.name ?? name,client:client,profiles:profiles,mist:mist,settings:settings,icon:FileManager.default.fileExists(atPath:icon.path) ? icon:nil,deployment:deployment,repairClient:repairClient,fileHashes:hashes,policies:policies,existing:existing,draftHash:draftHash)
    }
    private func receiptURL(_ plan:JamfPublisherPlan)->URL {plan.kit.appendingPathComponent("Jamf-publish-receipt.json")}
    private func save(_ receipt:JamfPublisherReceipt,plan:JamfPublisherPlan)throws {
        let data=try JSONEncoder().encode(receipt)
        try data.write(to:receiptURL(plan),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:receiptURL(plan).path)
        let summary=plan.kit.appendingPathComponent("Jamf-publish-summary.txt")
        let text=JamfPublishSuccess(plan:plan,receipt:receipt)?.text ?? ("PUSH Jamf publish — incomplete / not confirmed\nServer: "+receipt.server+"\n"+receipt.message+"\n"+receipt.objects.map{"\($0.kind) · ID \($0.id) · \($0.name)"}.joined(separator:"\n"))
        try Data(text.utf8).write(to:summary,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:summary.path)
    }
    private func id(_ response:JamfHTTPResponse)throws->Int {
        if let json=try? JSONSerialization.jsonObject(with:response.data) as? [String:Any],let id=JamfPublisherPolicy.id(json),id>0 {return id}
        if let value=try? JamfPublisherPolicy.value(response.data,"/*/id"),let id=Int(value),id>0{return id}
        throw JamfPublisherError("Jamf accepted a write but did not return an object ID. Review the server before resuming; no blind retry was made.")
    }
    private func record(_ kind:String,_ id:Int,_ name:String,receipt:inout JamfPublisherReceipt,plan:JamfPublisherPlan,action:String?=nil,role:String?=nil)throws {
        if !receipt.objects.contains(where:{$0.kind==kind && $0.id==id}) {receipt.objects.append(.init(kind:kind,id:id,name:name,action:action,role:role))};try save(receipt,plan:plan)
    }
    private func ensurePackage(_ file:JamfPublisherFile,category:Int,marker:String,receipt:inout JamfPublisherReceipt,plan:JamfPublisherPlan) async throws->Int {
        let matches=try await api.packages().filter{$0["fileName"] as? String==file.fileName}
        guard matches.count<=1 else {throw JamfPublisherError("Ambiguous package filename on Jamf. Nothing was overwritten.")}
        let packageID:Int
        if let object=matches.first,let found=JamfPublisherPolicy.id(object),found>0 {
            let remote=try await api.json("GET","api/v1/packages/\(found)")
            guard (remote["notes"] as? String ?? "").contains(marker+" SHA256:"+file.sha256) else {throw JamfPublisherError("A matching package filename lacks the expected ownership/hash marker. It was not overwritten.")}
            packageID=found
            if JamfPublisherPolicy.packageReady(remote,file:file){try record("packages",found,file.fileName,receipt:&receipt,plan:plan);return found}
            if remote["cloudTransferStatus"] as? String=="READY" {throw JamfPublisherError("Jamf reports a ready package with unverified/mismatched hash or size. Review it in Jamf before proceeding.")}
        }else{
            progress("Creating package record: "+file.fileName)
            let response=try await api.request("POST","api/v1/packages",body:JSONSerialization.data(withJSONObject:JamfPublisherPolicy.packageMetadata(file,category:category,marker:marker),options:[.sortedKeys]))
            packageID=try id(response)
        }
        try record("packages",packageID,file.fileName,receipt:&receipt,plan:plan)
        progress("Uploading "+file.fileName+"…")
        // Repeat only on a new, explicit Publish/Resume action. There are no
        // automatic write retries following an uncertain network failure.
        try await api.upload(file.url,fileName:file.fileName,field:"file",to:"api/v1/packages/\(packageID)/upload")
        for attempt in 0..<12 {
            let remote=try await api.json("GET","api/v1/packages/\(packageID)")
            if JamfPublisherPolicy.packageReady(remote,file:file){return packageID}
            if remote["cloudTransferStatus"] as? String=="ERROR" {throw JamfPublisherError("Jamf reported a package transfer error. Policies remain disabled.")}
            progress("Waiting for Jamf to verify package availability/hash (\(attempt+1)/12)…")
            try await Task.sleep(nanoseconds:pollDelayNanoseconds)
        }
        throw JamfPublisherError("Upload was accepted, but Jamf has not yet confirmed READY status, size and a matching hash. Policies remain disabled. Build/review again to resume after inventory catches up.")
    }
    /// One write, followed only by bounded reads. An accepted PUT is not proof
    /// that every Jamf replica already returns the requested state.
    func confirmPolicyState(_ id:Int,enabled:Bool) async throws->Data {
        let expected:JamfPublisherPolicy.PolicyState=enabled ? .enabled:.disabled
        var last:JamfPublisherPolicy.PolicyState = .missing
        for attempt in 0..<5 {
            let data=try await api.request("GET","JSSResource/policies/id/\(id)",accept:"application/xml").data
            last=try JamfPublisherPolicy.policyState(data)
            if last==expected {return data}
            guard last == .enabled || last == .disabled else {throw JamfPublisherError("Policy ID \(id): general/enabled is \(last.rawValue). No confirmed state transition; review this policy in Jamf.")}
            if attempt<4 {
                progress("Policy ID \(id): waiting for \(expected.rawValue) confirmation (\(attempt+1)/5); Jamf returned \(last.rawValue)…")
                try await Task.sleep(nanoseconds:pollDelayNanoseconds)
            }
        }
        throw JamfPublisherError("Policy ID \(id): expected \(expected.rawValue), but Jamf returned \(last.rawValue) after 5 read-back checks. Review this policy's Enabled setting in Jamf; publication cannot continue without confirmation.")
    }
    private func pausePolicy(_ id:Int,current:Data) async throws {
        let state=try JamfPublisherPolicy.policyState(current)
        guard state == .enabled || state == .disabled else {throw JamfPublisherError("Policy ID \(id): general/enabled is \(state.rawValue); no state write was made.")}
        if state == .enabled {
            _=try await api.request("PUT","JSSResource/policies/id/\(id)",body:JamfPublisherPolicy.changingEnabled(current,to:false),type:"application/xml")
        }
        _=try await confirmPolicyState(id,enabled:false)
    }
    func publish(_ plan:JamfPublisherPlan) async throws->JamfPublisherReceipt {
        guard plan.connection==api.connection else {throw JamfPublisherError("The reviewed Jamf connection changed. Review again.")}
        try plan.deployment.validate()
        var receipt=JamfPublisherReceipt(server:api.base.absoluteString,project:plan.project)
        receipt.clientDependencySignature=plan.clientIdentity
        do {
            for (name,digest) in plan.fileHashes {
                let file=plan.kit.appendingPathComponent(name)
                guard (try file.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true,DeploymentBundle.digest(try Data(contentsOf:file))==digest else {throw JamfPublisherError("A prepared kit file changed after review. Build/review again.")}
            }
            if let mist=plan.mist {guard DeploymentBundle.digest(try Data(contentsOf:mist.url))==mist.sha256 else {throw JamfPublisherError("The approved Mist package changed after review.")}}
            // Reject drift before the first configuration write; never silently
            // replace someone else's edits after the review was prepared.
            for object in plan.existing {
                let current=try await api.request("GET","JSSResource/\(object.kind)/id/\(object.id)",accept:"application/xml").data
                guard DeploymentBundle.digest(current)==object.digest else {throw JamfPublisherError("A reviewed Jamf object changed. Build/review again; it was not overwritten.")}
            }
            for object in plan.existing where object.kind=="policies" {
                progress("Pausing existing owned policy: "+object.name)
                try record("pause-attempt",object.id,object.name,receipt:&receipt,plan:plan)
                try await pausePolicy(object.id,current:object.xml)
                try record("paused-policy",object.id,object.name,receipt:&receipt,plan:plan)
            }
            let categories=try await api.collection("JSSResource/categories",key:"categories")
            var category=categories.first{$0["name"] as? String=="PUSH"}.flatMap(JamfPublisherPolicy.id)
            if category==nil {category=try id(await api.request("POST","JSSResource/categories/id/0",body:Data("<category><name>PUSH</name><priority>9</priority></category>".utf8),type:"application/xml"))}
            guard let category,category>0 else {throw JamfPublisherError("The PUSH category could not be verified.")}
            try record("categories",category,"PUSH",receipt:&receipt,plan:plan)
            var group=plan.group?.id
            var createdGroup=false
            if group==nil {
                let groups=try await api.collection("JSSResource/computergroups",key:"computer_groups")
                group=groups.first{$0["name"] as? String==plan.groupName}.flatMap(JamfPublisherPolicy.id)
                if group==nil {createdGroup=true;group=try id(await api.request("POST","JSSResource/computergroups/id/0",body:Data(("<computer_group><name>"+JamfPublisherPolicy.escape(plan.groupName)+"</name><is_smart>false</is_smart><computers/></computer_group>").utf8),type:"application/xml"))}
            }
            guard let group,group>0 else {throw JamfPublisherError("The pilot group could not be verified.")}
            try record("groups",group,plan.group?.name ?? plan.groupName,receipt:&receipt,plan:plan,action:createdGroup ? "Created empty group":"Used existing group")
            let clientID=try await ensurePackage(plan.client,category:category,marker:"PUSH-Client",receipt:&receipt,plan:plan)
            let repairClientID:Int
            if let repair=plan.repairClient {repairClientID=try await ensurePackage(repair,category:category,marker:"PUSH-Client",receipt:&receipt,plan:plan)}else{repairClientID=clientID}
            let profileID:Int?
            if let profiles=plan.profiles {profileID=try await ensurePackage(profiles,category:category,marker:plan.marker,receipt:&receipt,plan:plan)}else{profileID=nil}
            let mistID:Int?
            if let mist=plan.mist {mistID=try await ensurePackage(mist,category:category,marker:"PUSH-Mist",receipt:&receipt,plan:plan)}else{mistID=nil}
            for item in plan.policies {
                let scriptID:Int?
                if let major=item.major {
                    let scriptName="PUSH "+plan.project.uuidString+" · macOS \(major)"
                    let bytes=try SelfServiceKit.binding(Data(contentsOf:plan.kit.appendingPathComponent("Jamf-Offer-macOS-\(major).sh")),event:plan.clientEvent)
                    let xml=JamfPublisherPolicy.script(name:scriptName,content:String(decoding:bytes,as:UTF8.self),marker:plan.marker)
                    if let prior=plan.existing.first(where:{$0.kind=="scripts" && $0.name==scriptName}) {_=try await api.request("PUT","JSSResource/scripts/id/\(prior.id)",body:xml,type:"application/xml");scriptID=prior.id}
                    else{scriptID=try id(await api.request("POST","JSSResource/scripts/id/0",body:xml,type:"application/xml"))}
                    guard let scriptID else {throw JamfPublisherError("The offer script was not created.")}
                    try record("scripts",scriptID,scriptName,receipt:&receipt,plan:plan)
                    let saved=try await api.request("GET","JSSResource/scripts/id/\(scriptID)",accept:"application/xml").data
                    receipt.fingerprints["scripts/\(scriptID)"]=DeploymentBundle.digest(saved)
                    try save(receipt,plan:plan)
                    let plain=try JamfPublisherPolicy.value(saved,"/script/script_contents"),encoded=try JamfPublisherPolicy.value(saved,"/script/script_contents_encoded")
                    guard plain==String(decoding:bytes,as:UTF8.self) || Data(base64Encoded:encoded)==bytes else {throw JamfPublisherError("Jamf script read-back did not match the reviewed script.")}
                }else{scriptID=nil}
                guard let packageID=item.major==nil ? (item.eventOnlyRepair ? repairClientID:clientID):profileID else {throw JamfPublisherError("The offer profiles package is missing.")}
                let xml=JamfPublisherPolicy.policy(item,scope:group,category:category,package:packageID,script:scriptID,marker:plan.marker,extraPackage:item.major==nil ? mistID:nil,clientEvent:plan.clientEvent)
                let policyID:Int
                if let prior=plan.existing.first(where:{$0.kind=="policies" && $0.name==item.name}) {_=try await api.request("PUT","JSSResource/policies/id/\(prior.id)",body:xml,type:"application/xml");policyID=prior.id}
                else {policyID=try id(await api.request("POST","JSSResource/policies/id/0",body:xml,type:"application/xml"))}
                try record("policies",policyID,item.name,receipt:&receipt,plan:plan,action:plan.existing.contains(where:{$0.kind=="policies" && $0.name==item.name}) ? "Updated":"Created",role:item.role)
                if let icon=plan.icon,item.major != nil {try await api.upload(icon,fileName:"PUSH-icon.png",field:"name",to:"JSSResource/fileuploads/policies/id/\(policyID)")}
                let saved=try await api.request("GET","JSSResource/policies/id/\(policyID)",accept:"application/xml").data
                if plan.icon != nil,item.major != nil {
                    guard let iconID=Int(try JamfPublisherPolicy.value(saved,"/policy/self_service/self_service_icon/id")),iconID>0 else {throw JamfPublisherError("Jamf did not confirm the Self Service icon attachment. Policies remain disabled.")}
                }
                do {try JamfPublisherPolicy.verifyPolicy(saved,item:item,scope:group,package:packageID,script:scriptID,enabled:false,extraPackage:item.major==nil ? mistID:nil,clientEvent:plan.clientEvent)}
                catch {throw JamfPublisherError("Policy ID \(policyID): "+error.localizedDescription)}
                receipt.fingerprints["policies/\(policyID)"]=DeploymentBundle.digest(saved)
                try save(receipt,plan:plan)
            }
            receipt.verified=true;receipt.message="Uploaded and read-back verified. Policies are disabled. Review the pilot before enabling."
            try save(receipt,plan:plan);return receipt
        }catch{
            receipt.verified=false;receipt.enabled=false
            var uncertain:[String]=[],cleanupDetails:[String]=[]
            for id in Set(receipt.objects.filter{$0.kind=="policies" || $0.kind=="paused-policy" || $0.kind=="pause-attempt"}.map(\.id)) {
                do {
                    let current=try await api.request("GET","JSSResource/policies/id/\(id)",accept:"application/xml").data
                    try await pausePolicy(id,current:current)
                }catch{uncertain.append(String(id));cleanupDetails.append("Policy ID \(id): "+JamfValidationReason.sanitized(error.localizedDescription))}
            }
            receipt.message="Publish stopped: "+error.localizedDescription+" Policies were requested disabled. Review the recorded objects before resuming."+(uncertain.isEmpty ? "":" Unable to confirm pause for policy IDs "+uncertain.joined(separator:", ")+". Cleanup details: "+cleanupDetails.prefix(3).joined(separator:"; "))
            try? save(receipt,plan:plan);throw JamfPublisherError(receipt.message)
        }
    }
    func enablePilot(_ plan:JamfPublisherPlan,receipt:JamfPublisherReceipt) async throws->JamfPublisherReceipt {
        guard receipt.verified,!receipt.enabled,receipt.server==api.base.absoluteString,receipt.project==plan.project else {throw JamfPublisherError("Publish and verify this exact deployment before enabling.")}
        try plan.deployment.validate()
        var result=receipt
        let policies=receipt.objects.filter{$0.kind=="policies"}
        guard policies.count==plan.policies.count,let group=receipt.objects.first(where:{$0.kind=="groups"})?.id else {throw JamfPublisherError("The saved publish result is incomplete.")}
        var reviewed:[(Int,Data)]=[]
        do {
            for file in ([plan.client]+(plan.repairClient.map{[$0]} ?? [])+(plan.profiles.map{[$0]} ?? []))+(plan.mist.map{[$0]} ?? []) {
                guard let object=receipt.objects.first(where:{$0.kind=="packages" && $0.name==file.fileName}),try await JamfPublisherPolicy.packageReady(api.json("GET","api/v1/packages/\(object.id)"),file:file) else {throw JamfPublisherError("Package availability/integrity must be verified again before enabling.")}
            }
            for script in receipt.objects where script.kind=="scripts" {
                let current=try await api.request("GET","JSSResource/scripts/id/\(script.id)",accept:"application/xml").data
                guard receipt.fingerprints["scripts/\(script.id)"]==DeploymentBundle.digest(current) else {throw JamfPublisherError("A published script changed. Publish/review again before enabling.")}
            }
            for policy in policies {
                guard let item=plan.policies.first(where:{$0.name==policy.name}),let package=receipt.objects.first(where:{$0.kind=="packages" && $0.name==plan.packageFile(for:item)?.fileName})?.id else {throw JamfPublisherError("The reviewed policy mapping is incomplete.")}
                let scriptName=item.major.map{"PUSH "+plan.project.uuidString+" · macOS \($0)"}
                let script=receipt.objects.first(where:{$0.kind=="scripts" && $0.name==scriptName})?.id
                let data=try await api.request("GET","JSSResource/policies/id/\(policy.id)",accept:"application/xml").data
                guard receipt.fingerprints["policies/\(policy.id)"]==DeploymentBundle.digest(data) else {throw JamfPublisherError("A published policy changed. Publish/review again before enabling.")}
                let extra=item.major==nil ? receipt.objects.first(where:{$0.kind=="packages" && $0.name==plan.mist?.fileName})?.id:nil
                try JamfPublisherPolicy.verifyPolicy(data,item:item,scope:group,package:package,script:script,enabled:false,extraPackage:extra,clientEvent:plan.clientEvent)
                reviewed.append((policy.id,data))
            }
            // Client policy first. No command runs here: Jamf schedules it at a
            // future check-in; upgrade offers still require the user's click.
            for (id,data) in reviewed {
                let body=try JamfPublisherPolicy.changingEnabled(data,to:true)
                _=try await api.request("PUT","JSSResource/policies/id/\(id)",body:body,type:"application/xml")
                _=try await confirmPolicyState(id,enabled:true)
            }
            result.enabled=true;result.message=plan.deployment.mode.requiresCampaign ? "Pilot enabled. The configured client may install at check-in and start hourly toasts, daily reminders and deadline enforcement after its first five-minute check.":"Pilot enabled. Offers repair missing/outdated prerequisites on demand; macOS upgrades require a user selecting an offer."
            try save(result,plan:plan);return result
        }catch{
            result.verified=false;result.enabled=false
            // Best effort pause on partial activation; never claim atomic rollback
            // across network failures. IDs remain in the on-disk receipt.
            var failed:[String]=[]
            for (id,_) in reviewed {do{let current=try await api.request("GET","JSSResource/policies/id/\(id)",accept:"application/xml").data;try await pausePolicy(id,current:current)}catch{failed.append(String(id))}}
            result.message="Activation stopped. "+error.localizedDescription+(failed.isEmpty ? " Policies were requested disabled; verify in Jamf.":" Could not confirm pause for policy IDs: "+failed.joined(separator:", ")+". Review them in Jamf immediately.")
            try? save(result,plan:plan);throw JamfPublisherError(result.message)
        }
    }
}
