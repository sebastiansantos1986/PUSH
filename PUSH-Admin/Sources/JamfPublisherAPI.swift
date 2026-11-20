// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Security

struct JamfHTTPResponse {let data:Data,status:Int}
protocol JamfHTTPTransport {func send(_ request:URLRequest,upload:URL?) async throws->JamfHTTPResponse}
/// A separate ephemeral session per request; redirects are never followed with
/// a bearer token. TLS uses the OS trust store; there is no trust bypass.
final class JamfURLTransport:JamfHTTPTransport {
    func send(_ request:URLRequest,upload:URL?=nil) async throws->JamfHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            let delegate=JamfBoundedResponse(continuation)
            let config=URLSessionConfiguration.ephemeral
            config.httpCookieStorage=nil;config.httpShouldSetCookies=false;config.urlCredentialStorage=nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData;config.timeoutIntervalForRequest=90;config.timeoutIntervalForResource=900
            let session=URLSession(configuration:config,delegate:delegate,delegateQueue:nil)
            delegate.session=session
            let task:URLSessionTask
            if let upload {task=session.uploadTask(with:request,fromFile:upload)}else{task=session.dataTask(with:request)}
            task.resume()
        }
    }
}
private final class JamfBoundedResponse:NSObject,URLSessionDataDelegate,URLSessionTaskDelegate,@unchecked Sendable {
    private var continuation:CheckedContinuation<JamfHTTPResponse,Error>?
    private var data=Data(),response:HTTPURLResponse?,oversized=false
    var session:URLSession?
    init(_ continuation:CheckedContinuation<JamfHTTPResponse,Error>){self.continuation=continuation}
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void){completionHandler(nil)}
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping (URLSession.ResponseDisposition)->Void){
        self.response=response as? HTTPURLResponse
        if response.expectedContentLength>8_388_608 {oversized=true;completionHandler(.cancel)}else{completionHandler(.allow)}
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data){
        guard self.data.count+data.count<=8_388_608 else {oversized=true;dataTask.cancel();return};self.data.append(data)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
        defer{session.finishTasksAndInvalidate();self.session=nil;continuation=nil}
        guard let continuation else{return}
        if oversized {continuation.resume(throwing:JamfPublisherError("Jamf returned an oversized response."))}
        else if error != nil {continuation.resume(throwing:JamfPublisherError("The Jamf connection failed or timed out. Check connectivity/certificate trust. An interrupted write is not retried automatically; review the server before resuming."))}
        else if let response {continuation.resume(returning:.init(data:data,status:response.statusCode))}
        else {continuation.resume(throwing:JamfPublisherError("Jamf did not return an HTTP response."))}
    }
}
enum JamfPublisherKeychain {
    static let service="com.push.admin.jamf.oauth"
    static func query(_ connection:JamfPublisherConnection)->[String:Any] {[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:connection.secretAccount]}
    static func save(_ secret:String,connection:JamfPublisherConnection)throws {
        var lookup=query(connection)
        let update=[kSecValueData as String:Data(secret.utf8)]
        let result=SecItemUpdate(lookup as CFDictionary,update as CFDictionary)
        if result==errSecItemNotFound {lookup[kSecValueData as String]=Data(secret.utf8);lookup[kSecAttrLabel as String]="PUSH Admin · Jamf API";guard SecItemAdd(lookup as CFDictionary,nil)==errSecSuccess else {throw JamfPublisherError("The API secret could not be saved in your login Keychain.")}}
        else if result != errSecSuccess {throw JamfPublisherError("The API secret could not be updated in your login Keychain.")}
    }
    static func read(connection:JamfPublisherConnection)throws->String {
        var lookup=query(connection);lookup[kSecReturnData as String]=true;lookup[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary,&result)==errSecSuccess,let data=result as? Data,let text=String(data:data,encoding:.utf8) else {throw JamfPublisherError("No accessible saved API secret was found for this server and client ID.")};return text
    }
    static func remove(connection:JamfPublisherConnection)throws {let code=SecItemDelete(query(connection) as CFDictionary);guard code==errSecSuccess || code==errSecItemNotFound else {throw JamfPublisherError("The saved API secret could not be removed.")}}
}
final class JamfPublisherAPI {
    let connection:JamfPublisherConnection,base:URL
    private let transport:any JamfHTTPTransport
    private var secret:String,token="",expires=Date.distantPast
    init(connection:JamfPublisherConnection,secret:String,transport:any JamfHTTPTransport=JamfURLTransport())throws {
        self.connection=connection;base=try connection.validatedURL()
        guard !secret.isEmpty,secret.utf8.count<=16_384 else {throw JamfPublisherError("Enter a valid client secret.")}
        self.secret=secret;self.transport=transport
    }
    static func allowed(method:String,path:String)->Bool {
        let route=path.components(separatedBy:"?")[0]
        if method=="GET" {return ["api/v1/jamf-pro-version","api/v1/cloud-distribution-point","api/v1/packages","JSSResource/computergroups","JSSResource/categories","JSSResource/scripts","JSSResource/policies"].contains(route) || route.range(of:#"^(api/v1/packages|JSSResource/(scripts|policies))/[0-9]+$"#,options:.regularExpression) != nil || route.range(of:#"^JSSResource/(scripts|policies|computergroups)/id/[0-9]+$"#,options:.regularExpression) != nil}
        if method=="POST" {return route=="api/oauth/token" || route=="api/v1/auth/invalidate-token" || route=="api/v1/packages" || route.range(of:#"^api/v1/packages/[0-9]+/upload$"#,options:.regularExpression) != nil || ["JSSResource/categories/id/0","JSSResource/computergroups/id/0","JSSResource/scripts/id/0","JSSResource/policies/id/0"].contains(route) || route.range(of:#"^JSSResource/fileuploads/policies/id/[0-9]+$"#,options:.regularExpression) != nil}
        return method=="PUT" && route.range(of:#"^JSSResource/(scripts|policies|computergroups)/id/[0-9]+$"#,options:.regularExpression) != nil
    }
    private func raw(_ method:String,_ path:String,body:Data?=nil,type:String="application/json",accept:String="application/json",upload:URL?=nil,bearer:Bool=true) async throws->JamfHTTPResponse {
        guard Self.allowed(method:method,path:path),!path.contains(".."),!path.contains("#"),!path.contains("://"),let url=URL(string:path,relativeTo:base.appendingPathComponent("/"))?.absoluteURL,url.host==base.host,url.port==base.port,url.scheme=="https" else {throw JamfPublisherError("An unapproved Jamf operation was refused.")}
        var request=URLRequest(url:url);request.httpMethod=method;request.httpBody=body
        if method=="GET" {request.setValue("no-cache, no-store",forHTTPHeaderField:"Cache-Control");request.setValue("no-cache",forHTTPHeaderField:"Pragma")}
        request.setValue(accept,forHTTPHeaderField:"Accept");request.setValue(type,forHTTPHeaderField:"Content-Type")
        if bearer {request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")}
        return try await transport.send(request,upload:upload)
    }
    private func authorize() async throws {
        if !token.isEmpty,expires>Date().addingTimeInterval(45){return}
        let response=try await raw("POST","api/oauth/token",body:JamfPublisherPolicy.form(["grant_type":"client_credentials","client_id":connection.clientID,"client_secret":secret]),type:"application/x-www-form-urlencoded",bearer:false)
        guard response.status==200,let json=try? JSONSerialization.jsonObject(with:response.data) as? [String:Any],let value=json["access_token"] as? String,!value.isEmpty,!value.contains("\r"),!value.contains("\n"),value.utf8.count<=16384,let lifetime=json["expires_in"] as? NSNumber,lifetime.doubleValue>0 else {throw JamfPublisherError("Jamf authentication failed. Check the client ID, secret and enabled API client. No server response containing credentials was logged.")}
        token=value;expires=Date().addingTimeInterval(min(86400,lifetime.doubleValue))
    }
    func request(_ method:String,_ path:String,body:Data?=nil,type:String="application/json",accept:String="application/json",upload:URL?=nil) async throws->JamfHTTPResponse {
        try await authorize()
        let response=try await raw(method,path,body:body,type:type,accept:accept,upload:upload)
        guard (200...299).contains(response.status) else {
            let hint=response.status==403 ? "Check the API role's permissions.":response.status==401 ? "Reconnect to refresh authorization.":(300...399).contains(response.status) ? "Redirects are refused; use the direct HTTPS server origin.":"Review the server state before retrying an interrupted publish."
            let detail=JamfValidationReason.summary(response.data,status:response.status,secrets:[secret,token])
            throw JamfPublisherError("Jamf \(method) \(path.components(separatedBy:"?")[0]) returned HTTP \(response.status). "+(detail.map{"Jamf validation: "+$0+". "} ?? "")+hint)
        }
        return response
    }
    func json(_ method:String,_ path:String,object:[String:Any]?=nil) async throws->[String:Any] {
        let body=try object.map{try JSONSerialization.data(withJSONObject:$0,options:[.sortedKeys])}
        let response=try await request(method,path,body:body)
        guard let result=try? JSONSerialization.jsonObject(with:response.data) as? [String:Any] else {throw JamfPublisherError("Jamf returned an unsupported JSON object.")};return result
    }
    func collection(_ path:String,key:String) async throws->[[String:Any]] {try JamfPublisherPolicy.objects(try await request("GET",path).data,key:key)}
    func packages() async throws->[[String:Any]] {
        var results:[[String:Any]]=[]
        for page in 0..<200 {
            let json=try await self.json("GET","api/v1/packages?page=\(page)&page-size=100&sort=id%3Aasc")
            guard let items=json["results"] as? [[String:Any]],let total=json["totalCount"] as? Int else {throw JamfPublisherError("Unsupported package pagination response.")}
            results+=items;if results.count>=total{return results}
            guard !items.isEmpty else {throw JamfPublisherError("Jamf package pagination stopped before all results were read.")}
        }
        throw JamfPublisherError("Too many Jamf packages for this publisher's bounded lookup.")
    }
    func disconnect() async {if !token.isEmpty {_ = try? await raw("POST","api/v1/auth/invalidate-token")};token="";secret="";expires = .distantPast}
    func upload(_ file:URL,fileName:String,field:String,to path:String) async throws {
        guard fileName.range(of:#"^[A-Za-z0-9._-]+$"#,options:.regularExpression) != nil else {throw JamfPublisherError("Unsafe upload filename.")}
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("push-jamf-upload-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:folder)}
        let spool=folder.appendingPathComponent("body")
        guard FileManager.default.createFile(atPath:spool.path,contents:nil,attributes:[.posixPermissions:0o600]) else {throw JamfPublisherError("Cannot stage the package upload.")}
        let output=try FileHandle(forWritingTo:spool),input=try FileHandle(forReadingFrom:file)
        defer{try? output.close();try? input.close()}
        let boundary="PUSH"+UUID().uuidString.replacingOccurrences(of:"-",with:"")
        let mime=fileName.hasSuffix(".png") ? "image/png":"application/octet-stream"
        try output.write(contentsOf:Data(("--"+boundary+"\r\nContent-Disposition: form-data; name=\""+field+"\"; filename=\""+fileName+"\"\r\nContent-Type: "+mime+"\r\n\r\n").utf8))
        var total=0
        while let bytes=try input.read(upToCount:1_048_576),!bytes.isEmpty {total+=bytes.count;guard total<=134_217_728 else {throw JamfPublisherError("Upload exceeds the 128 MB limit.")};try output.write(contentsOf:bytes)}
        try output.write(contentsOf:Data(("\r\n--"+boundary+"--\r\n").utf8));try output.synchronize()
        _=try await request("POST",path,type:"multipart/form-data; boundary="+boundary,upload:spool)
    }
}
