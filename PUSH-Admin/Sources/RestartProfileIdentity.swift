// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Security
import CryptoKit

struct RestartProfileIdentity {
    var teamID:String
    var requirement:String
    var sha256:String
    func valid(for team:String)->Bool {teamID==team && team.count==10 && !requirement.isEmpty && requirement.count<16384 && !requirement.contains("cdhash") && sha256.count==64}
    /// Inspects the selected code signature only; never executes the binary.
    static func inspect(_ url:URL)throws->Self {
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard url.lastPathComponent=="push-cli",values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? Int.max)<52_428_800 else {throw DeploymentBundleError.invalid("Choose the production-signed push-cli executable, smaller than 50 MB.")}
        var code:SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL,[],&code)==errSecSuccess,let code,SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),nil)==errSecSuccess else {throw DeploymentBundleError.invalid("The selected executable does not have a valid code signature.")}
        var info:CFDictionary?
        guard SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&info)==errSecSuccess,let dictionary=info as? [String:Any],let team=dictionary[kSecCodeInfoTeamIdentifier as String] as? String,team.count==10 else {throw DeploymentBundleError.invalid("A stable Apple Developer signing team is required. Ad-hoc signatures cannot generate the restart approval.")}
        var developerID:SecRequirement?
        let developerRule="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \""+team+"\""
        guard SecRequirementCreateWithString(developerRule as CFString,[],&developerID)==errSecSuccess,let developerID,SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),developerID)==errSecSuccess else {throw DeploymentBundleError.invalid("Select a valid Developer ID Application-signed PUSH executable. Development and ad-hoc signatures are not production identities.")}
        var requirement:SecRequirement?;var text:CFString?
        guard SecCodeCopyDesignatedRequirement(code,[],&requirement)==errSecSuccess,let requirement,SecRequirementCopyString(requirement,[],&text)==errSecSuccess,let text else {throw DeploymentBundleError.invalid("The executable's designated requirement could not be read.")}
        let digest=SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined()
        let identity=Self(teamID:team,requirement:text as String,sha256:digest)
        guard identity.valid(for:team) else {throw DeploymentBundleError.invalid("The signature requirement is not stable across production updates.")}
        return identity
    }
}
