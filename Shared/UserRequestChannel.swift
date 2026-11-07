// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import Darwin

enum UserRequestChannel {
    static func directory(_ uid:Int)->URL {URL(fileURLWithPath:"/private/tmp/com.push-user-\(uid)")}
    static func write(_ request:UserUpdateRequest)throws {
        let uid=Int(getuid());guard request.userUID==uid else {throw CocoaError(.fileWriteNoPermission)}
        let folder=directory(uid)
        do {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])}
        catch {if !FileManager.default.fileExists(atPath:folder.path){throw error}}
        var info=stat();guard lstat(folder.path,&info)==0,info.st_uid==uid,info.st_mode&S_IFMT==S_IFDIR,info.st_mode&0o077==0 else {throw CocoaError(.fileWriteNoPermission)}
        let file=folder.appendingPathComponent("request.json")
        if FileManager.default.fileExists(atPath:file.path) {var existing=stat();guard lstat(file.path,&existing)==0,existing.st_uid==uid,existing.st_mode&S_IFMT==S_IFREG else {throw CocoaError(.fileWriteNoPermission)}}
        try JSONEncoder().encode(request).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
    /// Reads a fixed basename through directory/file descriptors. No path, program,
    /// configuration content or credential is accepted from the request.
    static func consume(uid:Int,folder:URL?=nil)throws->UserUpdateRequest? {
        let root=folder ?? directory(uid)
        let dir=open(root.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
        guard dir>=0 else {if errno==ENOENT{return nil};throw CocoaError(.fileReadNoPermission)}
        defer{close(dir)}
        var parent=stat();guard fstat(dir,&parent)==0,parent.st_uid==uid,parent.st_mode&S_IFMT==S_IFDIR,parent.st_mode&0o077==0 else {throw CocoaError(.fileReadNoPermission)}
        let fd=openat(dir,"request.json",O_RDONLY|O_NOFOLLOW|O_NONBLOCK)
        guard fd>=0 else {if errno==ENOENT{return nil};throw CocoaError(.fileReadNoPermission)}
        defer{close(fd)}
        var info=stat();guard fstat(fd,&info)==0,info.st_uid==uid,info.st_mode&S_IFMT==S_IFREG,info.st_size>0,info.st_size<=4096,info.st_mode&0o077==0 else {throw CocoaError(.fileReadNoPermission)}
        let file=FileHandle(fileDescriptor:fd,closeOnDealloc:false)
        let data=try file.read(upToCount:4097) ?? Data()
        var latest=stat()
        if fstatat(dir,"request.json",&latest,AT_SYMLINK_NOFOLLOW)==0,latest.st_ino==info.st_ino,latest.st_dev==info.st_dev {_=unlinkat(dir,"request.json",0)}
        guard data.count<=4096 else {throw CocoaError(.fileReadTooLarge)}
        return try JSONDecoder().decode(UserUpdateRequest.self,from:data)
    }
}
