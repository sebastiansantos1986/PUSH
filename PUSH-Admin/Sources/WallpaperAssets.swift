// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

struct WallpaperAssetReference:Codable {
    var role:String
    var digest:String
    var originalName:String
    var fileName:String {WallpaperPolicy.assetName(digest:digest,role:role) ?? "invalid"}
    var deployedPath:String {WallpaperPolicy.managedDirectory+"/"+fileName}
    var valid:Bool {WallpaperPolicy.assetName(digest:digest,role:role) != nil}
}
struct StagedWallpaperFile {let url:URL;let fileName:String}
enum WallpaperAssetImage {
    static func normalizedPNG(_ data:Data)throws->Data {
        guard data.count<=52_428_800,let source=CGImageSourceCreateWithData(data as CFData,nil),let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:4096,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {throw AdminError.message("Choose a readable static image smaller than 50 MB.")}
        let output=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(output,UTType.png.identifier as CFString,1,nil) else {throw AdminError.message("Image conversion could not start.")}
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination),output.length<=20_971_520 else {throw AdminError.message("The converted image is too large. Choose a smaller background.")}
        return output as Data
    }
    static func digest(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func read(_ ref:WallpaperAssetReference,folder:URL)throws->Data {
        guard ref.valid else {throw AdminError.message("The saved wallpaper reference is invalid. Choose the image again.")}
        let path=folder.appendingPathComponent(ref.fileName)
        let values=try path.resourceValues(forKeys:[.isSymbolicLinkKey,.fileSizeKey])
        guard values.isSymbolicLink != true,(values.fileSize ?? Int.max)<=20_971_520 else {throw AdminError.message("The staged wallpaper is not a protected image file.")}
        let data=try Data(contentsOf:path)
        guard digest(data)==ref.digest,NSImage(data:data) != nil else {throw AdminError.message("The staged wallpaper changed. Choose the image again before deploying.")}
        return data
    }
}
extension AdminStore {
    var wallpaperAssetDirectory:URL {draftURL.deletingLastPathComponent().appendingPathComponent("WallpaperAssets")}
    func chooseWallpaper(role:String) {
        guard ["noncompliant","compliant"].contains(role) else{return}
        let panel=NSOpenPanel();panel.allowedContentTypes=[.image];panel.allowsMultipleSelection=false
        panel.message="Choose a static desktop background. PUSH stores a normalized PNG in its working directory; the original is not modified."
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {
            let properties=try url.resourceValues(forKeys:[.fileSizeKey]);guard (properties.fileSize ?? Int.max)<=52_428_800 else {throw AdminError.message("Choose an image smaller than 50 MB.")}
            let data=try WallpaperAssetImage.normalizedPNG(Data(contentsOf:url))
            let ref=WallpaperAssetReference(role:role,digest:WallpaperAssetImage.digest(data),originalName:url.lastPathComponent)
            try FileManager.default.createDirectory(at:wallpaperAssetDirectory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let file=wallpaperAssetDirectory.appendingPathComponent(ref.fileName)
            try data.write(to:file,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
            var assets=document.wallpaperAssets ?? [:];assets[role]=ref;document.wallpaperAssets=assets
            document.edits[role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper"]=ref.deployedPath
            notice="Wallpaper staged and added to the preview. Export or Apply deploys it; your current desktop was not changed."
        } catch {notice=error.localizedDescription}
    }
    func useDefaultWallpaper() {
        document.edits["compliance.nonCompliantWallpaper"]=WallpaperPolicy.defaultImage
        document.wallpaperAssets?.removeValue(forKey:"noncompliant")
    }
    func restorePersonalWallpaperChoice() {
        document.edits["compliance.compliantWallpaper"]=""
        document.wallpaperAssets?.removeValue(forKey:"compliant")
    }
    func stageWallpaperFiles(in folder:URL)throws->[StagedWallpaperFile] {
        var result:[StagedWallpaperFile]=[]
        for (role,ref) in document.wallpaperAssets ?? [:] {
            let key=role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper"
            guard role==ref.role,ref.valid else {throw AdminError.message("Invalid wallpaper asset role.")}
            guard document.setupValue(key)==ref.deployedPath else {continue}
            let data=try WallpaperAssetImage.read(ref,folder:wallpaperAssetDirectory)
            let destination=folder.appendingPathComponent(ref.fileName)
            if FileManager.default.fileExists(atPath:destination.path),(try? Data(contentsOf:destination)) != data {throw AdminError.message("A wallpaper file with different content already exists in the selected folder. Choose another export folder.")}
            try data.write(to:destination,options:.atomic)
            result.append(.init(url:destination,fileName:ref.fileName))
        }
        return result
    }
    func wallpaperPreview(role:String)->NSImage? {
        if let ref=document.wallpaperAssets?[role],let data=try? WallpaperAssetImage.read(ref,folder:wallpaperAssetDirectory) {return NSImage(data:data)}
        let key=role=="noncompliant" ? "compliance.nonCompliantWallpaper":"compliance.compliantWallpaper"
        let path=document.setupValue(key)
        if path==WallpaperPolicy.defaultImage,let resource=Bundle.main.url(forResource:"PUSH-NonCompliant",withExtension:"png") {return NSImage(contentsOf:resource)}
        return path.isEmpty ? nil:NSImage(contentsOfFile:path)
    }
}
