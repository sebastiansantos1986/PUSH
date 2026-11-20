// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct JamfObjectBindings:Codable {
    var server:String,project:UUID,policyIDs:[String:Int],groupID:Int,clientFile:String?
    var clientDependencySignature:String?=nil
    init?(receipt:JamfPublisherReceipt){
        guard receipt.verified,let group=receipt.objects.first(where:{$0.kind=="groups" && $0.id>0}) else{return nil}
        clientDependencySignature=receipt.clientDependencySignature
        server=receipt.server;project=receipt.project;groupID=group.id;policyIDs=[:]
        clientFile=receipt.objects.first{$0.kind=="packages" && $0.name.hasPrefix("PUSH-Client-")}?.name
        for object in receipt.objects where object.kind=="policies" {if let role=JamfPublishedRecord.role(object,project:receipt.project){policyIDs[role]=object.id}}
    }
}
struct JamfPublishedRecord {
    let url:URL,receipt:JamfPublisherReceipt
    static func role(_ object:JamfPublisherReceipt.Object,project:UUID)->String? {
        if let role=object.role,["client","macOS-26","macOS-27"].contains(role){return role}
        let prefix="PUSH "+project.uuidString+" · "
        if object.name.hasPrefix(prefix+"Client "){return "client"}
        for major in [26,27] where object.name==prefix+"macOS \(major)" {return "macOS-\(major)"}
        return nil
    }
    static func records(root:URL?,kit:URL?=nil,server:String,project:UUID)->[Self] {
        var urls:[URL]=[]
        if let kit {urls.append(kit.appendingPathComponent("Jamf-publish-receipt.json"))}
        if let root,let folders=try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey]) {
            for folder in folders.prefix(1000) where (try? folder.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink)==false {urls.append(folder.appendingPathComponent("Jamf-publish-receipt.json"))}
        }
        return Array(Set(urls)).compactMap{url in
            guard let values=try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? Int.max)<1_048_576,let data=try? Data(contentsOf:url),let receipt=try? JSONDecoder().decode(JamfPublisherReceipt.self,from:data),receipt.server==server,receipt.project==project else{return nil}
            return .init(url:url,receipt:receipt)
        }.sorted{a,b in
            let left=(try? a.url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right=(try? b.url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left>right
        }
    }
    static func policyBinding(_ role:String,records:[Self],clientFile:String?=nil,dependencySignature:String?=nil)->JamfPublisherReceipt.Object? {
        for record in records {
            if role=="client",let dependencySignature,record.receipt.clientDependencySignature != dependencySignature {continue}
            if role=="client",let clientFile,!record.receipt.objects.contains(where:{$0.kind=="packages" && $0.name==clientFile}) {continue}
            if let object=record.receipt.objects.first(where:{$0.kind=="policies" && self.role($0,project:record.receipt.project)==role}) {return object}
        }
        return nil
    }
}
struct JamfNameReview:Identifiable {
    let id=UUID()
    struct Item:Identifiable {let id:Int,name:String,kind:String,role:String,xml:Data}
    let record:JamfPublishedRecord,policies:[Item],group:Item
    var server:String {record.receipt.server}
}
struct JamfNameResult:Identifiable {
    let id=UUID()
    let server:String,group:String,groupID:Int,policies:[JamfPublisherReceipt.Object],bindings:JamfObjectBindings?
    var text:String {(["Names updated in Jamf","Server: "+server,"Group: \(group) · ID \(groupID)",""]+policies.map{"\($0.name) · Policy ID \($0.id)"}+["","Existing Jamf IDs, policy settings and group criteria/membership were preserved."]).joined(separator:"\n")}
}
enum JamfNamePolicy {
    static func validated(_ value:String)throws->String {
        let name=value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count<=200,!name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else {throw JamfPublisherError("Use a name of 1–200 characters without line breaks or control characters.")};return name
    }
    static func renamed(_ xml:Data,kind:String,name:String)throws->Data {
        let document=try JamfPublisherPolicy.xml(String(decoding:xml,as:UTF8.self))
        let nodes=try document.nodes(forXPath:kind=="policies" ? "/policy/general/name":"/computer_group/name")
        guard nodes.count==1 else {throw JamfPublisherError("The Jamf item has an unsupported name field.")}
        nodes[0].stringValue=try validated(name)
        return document.xmlData
    }
    private static func canonical(_ node:XMLNode)->String {
        if let element=node as? XMLElement {
            let attributes=(element.attributes ?? []).map{($0.name ?? "")+"="+($0.stringValue ?? "")}.sorted().joined(separator:"|")
            return "<"+(element.name ?? "")+"["+attributes+"]>"+(element.children ?? []).map(canonical).joined()+"</>"
        }
        if node.kind == .text {let text=node.stringValue ?? "";return text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "":text}
        return node.xmlString
    }
    static func protectedSignature(_ data:Data,kind:String)throws->String {
        let doc=try JamfPublisherPolicy.xml(String(decoding:data,as:UTF8.self))
        let path=kind=="policies" ? "/policy/general/name":"/computer_group/name"
        for node in try doc.nodes(forXPath:path) {node.detach()}
        // Group renaming can refresh scope display labels; IDs remain protected.
        if kind=="policies" {for node in try doc.nodes(forXPath:"/policy/scope//computer_group/name") {node.detach()}}
        // Smart membership is computed and can legitimately refresh; its ordered
        // criteria and all other group settings remain in the signature.
        if kind=="computergroups",try JamfPublisherPolicy.value(data,"/computer_group/is_smart")=="true" {
            for node in try doc.nodes(forXPath:"/computer_group/computers") {node.detach()}
        }
        guard let root=doc.rootElement() else {throw JamfPublisherError("Missing Jamf object root.")}
        return DeploymentBundle.digest(Data(canonical(root).utf8))
    }
}
final class JamfNameEditor {
    let api:JamfPublisherAPI
    init(api:JamfPublisherAPI){self.api=api}
    func review(record:JamfPublishedRecord) async throws->JamfNameReview {
        guard record.receipt.server==api.base.absoluteString,record.receipt.verified,let group=record.receipt.objects.first(where:{$0.kind=="groups" && $0.id>0}) else {throw JamfPublisherError("Choose a successfully published setup for this server before editing names.")}
        var policies:[JamfNameReview.Item]=[]
        for object in record.receipt.objects where object.kind=="policies" {
            guard object.id>0,let role=JamfPublishedRecord.role(object,project:record.receipt.project) else {throw JamfPublisherError("A policy lacks a recognized workflow identity. It was not selected for renaming.")}
            let xml=try await api.request("GET","JSSResource/policies/id/\(object.id)",accept:"application/xml").data
            let name=try JamfPublisherPolicy.value(xml,"/policy/general/name")
            guard !name.isEmpty else {throw JamfPublisherError("The published policy could not be read.")}
            policies.append(.init(id:object.id,name:name,kind:"policies",role:role,xml:xml))
        }
        guard !policies.isEmpty else {throw JamfPublisherError("No published policies are recorded for this workflow.")}
        let xml=try await api.request("GET","JSSResource/computergroups/id/\(group.id)",accept:"application/xml").data
        let name=try JamfPublisherPolicy.value(xml,"/computer_group/name"),smart=try JamfPublisherPolicy.value(xml,"/computer_group/is_smart")
        guard !name.isEmpty,["true","false"].contains(smart) else {throw JamfPublisherError("The pilot computer group could not be verified.")}
        return .init(record:record,policies:policies,group:.init(id:group.id,name:name,kind:"computergroups",role:smart=="true" ? "smart":"static",xml:xml))
    }
    func apply(_ review:JamfNameReview,policyNames:[Int:String],groupName:String) async throws->JamfNameResult {
        guard review.server==api.base.absoluteString else {throw JamfPublisherError("The reviewed server changed.")}
        let groupName=try JamfNamePolicy.validated(groupName)
        var names:[Int:String]=[:]
        for item in review.policies {names[item.id]=try JamfNamePolicy.validated(policyNames[item.id] ?? item.name)}
        guard Set(names.values.map{$0.lowercased()}).count==names.count else {throw JamfPublisherError("Give each policy a distinct name.")}
        let serverPolicies=try await api.collection("JSSResource/policies",key:"policies")
        for (id,name) in names {guard !serverPolicies.contains(where:{JamfPublisherPolicy.id($0) != id && ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame}) else {throw JamfPublisherError("Another policy already uses the requested name. No names were changed.")}}
        let groups=try await api.collection("JSSResource/computergroups",key:"computer_groups")
        guard !groups.contains(where:{JamfPublisherPolicy.id($0) != review.group.id && ($0["name"] as? String)?.caseInsensitiveCompare(groupName) == .orderedSame}) else {throw JamfPublisherError("Another group already uses the requested name. No names were changed.")}
        let changes=(review.policies+[review.group]).filter{($0.kind=="policies" ? names[$0.id]:groupName) != $0.name}
        guard !changes.isEmpty else {throw JamfPublisherError("Enter at least one changed name before saving.")}
        for item in changes {
            let xml=try await api.request("GET","JSSResource/\(item.kind)/id/\(item.id)",accept:"application/xml").data
            guard DeploymentBundle.digest(xml)==DeploymentBundle.digest(item.xml) else {throw JamfPublisherError("A reviewed item changed on the server. Reload names before saving.")}
        }
        var updated:[JamfNameReview.Item]=[]
        do {
            // Policies first; a group rename may update their scope label text.
            for item in changes {
                let name=item.kind=="policies" ? names[item.id]!:groupName
                let body=try JamfNamePolicy.renamed(item.xml,kind:item.kind,name:name)
                updated.append(item)
                _=try await api.request("PUT","JSSResource/\(item.kind)/id/\(item.id)",body:body,type:"application/xml")
                let readback=try await api.request("GET","JSSResource/\(item.kind)/id/\(item.id)",accept:"application/xml").data
                let path=item.kind=="policies" ? "/policy/general/name":"/computer_group/name"
                guard try JamfPublisherPolicy.value(readback,path)==name else {throw JamfPublisherError("Jamf did not retain the requested name.")}
                let before=try JamfNamePolicy.protectedSignature(item.xml,kind:item.kind),after=try JamfNamePolicy.protectedSignature(readback,kind:item.kind)
                guard before==after else {throw JamfPublisherError("A setting other than the name changed. Review this item in Jamf.")}
            }
            var receipt=review.record.receipt
            receipt.objects=receipt.objects.map{object in
                var copy=object
                if object.kind=="policies",let name=names[object.id],let item=review.policies.first(where:{$0.id==object.id}) {copy.name=name;copy.role=item.role;copy.action=name==item.name ? object.action:"Renamed"}
                if object.kind=="groups",object.id==review.group.id {copy.name=groupName;copy.action=groupName==review.group.name ? object.action:"Renamed"}
                return copy
            }
            for item in review.policies {
                let data=try await api.request("GET","JSSResource/policies/id/\(item.id)",accept:"application/xml").data
                guard try JamfPublisherPolicy.value(data,"/policy/general/name")==names[item.id],try JamfNamePolicy.protectedSignature(data,kind:"policies")==JamfNamePolicy.protectedSignature(item.xml,kind:"policies") else {throw JamfPublisherError("A policy changed during final verification. Inspect the recorded IDs in Jamf.")}
                receipt.fingerprints["policies/\(item.id)"]=DeploymentBundle.digest(data)
            }
            receipt.message="Published names updated on the same Jamf IDs. Existing settings were preserved."
            try JSONEncoder().encode(receipt).write(to:review.record.url,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:review.record.url.path)
            let result=JamfNameResult(server:review.server,group:groupName,groupID:review.group.id,policies:receipt.objects.filter{$0.kind=="policies"},bindings:JamfObjectBindings(receipt:receipt))
            try Data(result.text.utf8).write(to:review.record.url.deletingLastPathComponent().appendingPathComponent("Jamf-publish-summary.txt"),options:.atomic)
            return result
        }catch{
            // An interrupted remote operation cannot be claimed atomic. IDs are
            // named for inspection; retry only after loading a fresh review.
            let ids=updated.map{"\($0.kind)/\($0.id)"}.joined(separator:", ")
            throw JamfPublisherError("Name update stopped. "+error.localizedDescription+" Inspect these attempted items in Jamf before reloading: "+ids)
        }
    }
}
