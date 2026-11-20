// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

enum JamfBundledDependencies {
    static let mistVersion="2.3"
    static let mistSHA256="ad4200e342535e7744ed6db04226b28403fd44f4d031e255f1de8d532fc89a69"
    static func mist(bundle:Bundle = .main)throws->URL {
        guard let url=bundle.url(forResource:"mist-cli.2.3",withExtension:"pkg") else {throw JamfPublisherError("The bundled Mist prerequisite is missing. Reinstall the complete Admin release.")}
        try validateMist(url)
        return url
    }
    static func validateMist(_ url:URL)throws {
        let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? Int.max)<10_485_760,DeploymentBundle.digest(try Data(contentsOf:url))==mistSHA256 else {throw JamfPublisherError("Bundled Mist integrity verification failed. Reinstall Admin; do not substitute an unverified package.")}
    }
}
