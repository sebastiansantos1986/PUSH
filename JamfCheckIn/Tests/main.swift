// JamfCheckIn — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
var checks=0
func check(_ value:@autoclosure ()->Bool,_ label:String){guard value() else {fatalError("FAIL: "+label)};checks+=1;print("PASS: "+label)}
var status=StatusSnapshot()
status.running="27.0";status.target="27.2";status.policyAvailable=true;status.enabled=true;status.dryRun=false;status.requestsEnabled=true;status.monitor=true
check(!status.canRequest,"legacy installations without protocol metadata cannot receive unsupported requests")
status.protocolReady=true
check(status.canRequest,"matching enabled backend permits a guarded request")
status.pending=true
check(!status.canRequest && status.title.contains("verification"),"pending reboot verification blocks duplicate update requests")
status.pending=false;status.monitor=nil
check(!status.canRequest && status.title.contains("unknown"),"unknown service status cannot become permission to install")
status.monitor=false
check(!status.canRequest && status.title.contains("stopped"),"paused service explains why no request can run")
status.monitor=true;status.dryRun=true
check(!status.canRequest,"dry-run status never enables live requests")
status.dryRun=false;status.running="27.2.0"
check(status.compliant && !status.canRequest,"numeric-equivalent versions remain compliant")
status.running="27.0";status.target="bad"
check(!status.canRequest,"invalid targets cannot become actionable requests")
status.target="27.2";status.recovery=InstallRecoveryRecord(target:"27.2",reason:"Network unavailable",kind:.network,failedAt:Date())
check(status.title=="Update needs attention","saved failure appears in the existing JamfCheckIn card")
check(!status.automaticRecoveryActive,"unverified saved failures do not invent an active automatic countdown")
let deadline=Date().addingTimeInterval(600)
let notice=RecoveryNotice(target:"27.2",reason:"Network unavailable",retryAt:deadline,automatic:true,explanation:"Fixture")
check(notice.remaining(at:deadline.addingTimeInterval(-0.1))==1 && !notice.countdownDue(at:deadline.addingTimeInterval(-0.1)),"countdown never fires before its absolute saved deadline")
check(notice.countdownDue(at:deadline),"countdown becomes due only at the saved deadline")
let request=UserUpdateRequest(userUID:501,target:"27.2",action:.install,issuedAt:Date())
check(UserUpdateRequest.valid(request,owner:501,target:"27.2.0",now:Date()),"request binds to the normalized managed target")
check(!UserUpdateRequest.valid(request,owner:502,target:"27.2",now:Date()),"request is rejected for a different console user")
check(!UserUpdateRequest.valid(request,owner:501,target:"27.3",now:Date()),"request cannot follow an unreviewed target change")
print("Passed \(checks) JamfCheckIn offline checks. No live status refresh, request, app, Jamf command or update was executed.")
