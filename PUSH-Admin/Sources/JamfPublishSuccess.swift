// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

/// Only verified receipts can produce a real success report. No API secret,
/// access token or endpoint password is part of this presentation model.
struct JamfPublishSuccess:Identifiable {
    struct Row:Identifiable {
        let id:Int,name:String,purpose:String,action:String
    }
    let id=UUID()
    let server:String,group:Row,policies:[Row],enabled:Bool,isPreview:Bool
    var requiredCampaign=false
    var title:String {isPreview ? "Success popup preview":enabled ? "Your pilot is enabled":"Published to Jamf"}
    var subtitle:String {
        if isPreview {return "Example names and IDs — nothing was created or enabled."}
        return enabled ? "The reviewed policies are enabled for the pilot group below.":"Setup verified. All policies are disabled until you enable the pilot."
    }
    var nextStep:String {
        if isPreview {return "This is a display-only example. A real publish result uses the actual Jamf names and IDs."}
        if enabled {return requiredCampaign ? "The configured client may install at check-in, then show hourly toasts and daily reminders and enforce the reviewed deadline. Verify delivery and authorization on a pilot.":"When an offer is clicked, missing/outdated prerequisites are repaired on demand and verified before continuing. Working current clients skip reinstallation; no policy-history reset is needed."}
        return "Review these items in Jamf. If this is a newly created group, add your approved pilot Macs. Choose Enable for pilot separately when you are ready."
    }
    init?(plan:JamfPublisherPlan,receipt:JamfPublisherReceipt){
        let groups=receipt.objects.filter{$0.kind=="groups"},objects=receipt.objects.filter{$0.kind=="policies"}
        guard receipt.verified,receipt.project==plan.project,receipt.server==(try? plan.connection.validatedURL().absoluteString),groups.count==1,let group=groups.first,group.id>0,objects.count==plan.policies.count,Set(objects.map(\.name))==Set(plan.policies.map(\.name)),objects.allSatisfy({$0.id>0}),Set(objects.map(\.id)).count==objects.count else{return nil}
        self.server=receipt.server;self.enabled=receipt.enabled;isPreview=false;requiredCampaign=plan.deployment.mode.requiresCampaign
        self.group = .init(id:group.id,name:group.name,purpose:"Pilot scope",action:group.action ?? "Pilot group")
        policies=plan.policies.compactMap{item in
            guard let object=objects.first(where:{$0.name==item.name}) else{return nil}
            return .init(id:object.id,name:object.name,purpose:item.title,action:object.action ?? "Published")
        }
    }
    private init(server:String,group:Row,policies:[Row],enabled:Bool,isPreview:Bool){self.server=server;self.group=group;self.policies=policies;self.enabled=enabled;self.isPreview=isPreview}
    static var preview:Self {
        .init(server:"https://example.invalid",group:.init(id:1001,name:"EXAMPLE · PUSH Pilot",purpose:"Pilot scope",action:"Created empty group"),policies:[
            .init(id:2001,name:"EXAMPLE · PUSH Client prerequisite",purpose:"Install PUSH client",action:"Created"),
            .init(id:2002,name:"EXAMPLE · Offer macOS Tahoe 26",purpose:"Self Service · macOS 26",action:"Created"),
            .init(id:2003,name:"EXAMPLE · Offer macOS 27",purpose:"Self Service · macOS 27",action:"Created")
        ],enabled:false,isPreview:true)
    }
    var text:String {
        var lines=[isPreview ? "SIMULATION ONLY — no Jamf items were created":title,"Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS","Server: "+server,subtitle,"","PILOT GROUP",group.name,"Jamf ID: \(group.id) · "+group.action,"","POLICIES"]
        for item in policies {lines += [item.name,"Jamf ID: \(item.id) · "+item.action,"Purpose: "+item.purpose,"State: "+(enabled ? "Enabled for pilot":"Disabled"),""]}
        lines.append(nextStep)
        return lines.joined(separator:"\n")+"\n"
    }
}
