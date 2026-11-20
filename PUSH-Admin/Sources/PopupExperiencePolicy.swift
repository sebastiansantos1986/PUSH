// PUSH / Regina Pro notification patterns — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct PopupPresentation:Codable,Equatable {
    var width:Double=480,height:Double=680
    var greetingTemplate="Hello {fullName}"
    var bannerText="Your IT team · macOS preview"
    var bannerImage:Data?
    func validated()throws->Self {
        guard width.isFinite,height.isFinite,(360...900).contains(width),(200...1000).contains(height),greetingTemplate.count<=160,bannerText.count<=200,(bannerImage?.count ?? 0)<=262144 else {throw MajorUpgradeDemoError.invalid("Choose width 360–900, height 200–1000, short banner/greeting text and a banner PNG below 256 KB.")}
        if let image=bannerImage,!image.starts(with:Data([137,80,78,71,13,10,26,10])) {throw MajorUpgradeDemoError.invalid("Use a normalized PNG banner.")}
        return self
    }
    func greeting(fullName:String,username:String)->String {
        func clean(_ value:String)->String {String(value.unicodeScalars.filter{!CharacterSet.controlCharacters.contains($0)}.map(String.init).joined().prefix(100)).trimmingCharacters(in:.whitespaces)}
        let account=clean(username),name=clean(fullName).isEmpty ? (account.isEmpty ? "there":account):clean(fullName)
        return greetingTemplate.replacingOccurrences(of:"{fullName}",with:name).replacingOccurrences(of:"{firstName}",with:String(name.split(separator:" ").first ?? "there")).replacingOccurrences(of:"{username}",with:account)
    }
}
struct MajorOfferSettings:Codable {
    var schemaVersion=1
    var presentation=PopupPresentation()
    var currentExample="26.0",targetExample="27.0"
    var duration:Double=20
    var options:MajorUpgradeDemoOptions {get throws {try .init(current:currentExample,target:targetExample,duration:duration)}}
    func validated()throws->Self {
        guard schemaVersion==1 else {throw MajorUpgradeDemoError.invalid("Unsupported major-offer configuration schema.")}
        _=try presentation.validated();_=try options;return self
    }
    static let installedPath="/Library/Management/PUSH/major-offer.json"
    static func installed()->Self {
        guard let handle=try? FileHandle(forReadingFrom:URL(fileURLWithPath:installedPath)) else{return Self()};defer{try? handle.close()}
        guard let data=try? handle.read(upToCount:524289),data.count<=524288,let settings=try? JSONDecoder().decode(Self.self,from:data),let valid=try? settings.validated() else{return Self()}
        return valid
    }
}
struct SinglePopupNotice:Codable {
    var title:String,message:String
    var primary="Got it",secondary="Close",style="info",kind="alert"
    var timeout:Int=60,debug=false
    var presentation=PopupPresentation()
    func validated()throws->Self {
        guard !title.isEmpty,title.count<=160,!message.isEmpty,message.count<=3000,!primary.isEmpty,primary.count<=40,secondary.count<=40,["info","warning","error","success"].contains(style),["alert","toast"].contains(kind),(0...900).contains(timeout) else {throw MajorUpgradeDemoError.invalid("Invalid standalone notice: use a short title/message, alert or toast, supported style and timeout 0–900.")}
        _=try presentation.validated();return self
    }
    func payload()throws->String {
        _=try validated();var copy=self;copy.presentation.bannerImage=nil
        let data=try JSONEncoder().encode(copy);guard data.count<24000 else {throw MajorUpgradeDemoError.invalid("Notice payload is too large.")};return data.base64EncodedString()
    }
    static func decode(_ text:String)throws->Self {
        guard text.count<32768,let data=Data(base64Encoded:text) else {throw MajorUpgradeDemoError.invalid("Invalid notice payload.")}
        return try JSONDecoder().decode(Self.self,from:data).validated()
    }
}

// Content height is measured by SwiftUI. The configured height is a ceiling,
// not a demand for empty space. The footer stays outside the scrolling body.
struct NoticeWindowLayout {
    static func size(width:Double,heightLimit:Double,measuredHeight:Double,screenWidth:Double,screenHeight:Double)->(width:Double,height:Double) {
        let availableWidth=max(1,screenWidth-40),availableHeight=max(1,screenHeight-80)
        let w=min(max(360,width),availableWidth)
        let cap=min(max(200,heightLimit),availableHeight)
        return (w,min(cap,max(min(200,cap),ceil(measuredHeight))))
    }
}
struct NoticeResponseState {
    private(set) var result:Int32?
    mutating func respond(_ code:Int32)->Bool {
        guard result==nil,[Int32(0),2,5].contains(code) else{return false}
        result=code;return true
    }
    mutating func tick(remaining:inout Int,timeout:Int)->Bool {
        guard result==nil,timeout>0 else{return false}
        remaining=max(0,remaining-1)
        return remaining==0 && respond(5)
    }
}
// Small block parser retains heading/list structure that a single SwiftUI Text
// would flatten. Inline formatting uses Foundation; no HTML or image fetcher.
enum NoticeMarkdown {
    enum Block:Equatable {case paragraph(String),heading(Int,String),bullet(String),numbered(String,String),quote(String),code(String)}
    static func allowsLink(_ url:URL)->Bool { ["https","http","mailto"].contains(url.scheme?.lowercased() ?? "") }
    static func inline(_ source:String)->AttributedString {
        var value=(try? AttributedString(markdown:source,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        let rejected=value.runs.compactMap {run -> Range<AttributedString.Index>? in
            guard let link=run.link,!allowsLink(link) else{return nil};return run.range
        }
        for range in rejected {value[range].link=nil}
        return value
    }
    static func blocks(_ source:String)->[Block] {
        var output:[Block]=[],paragraph:[String]=[],code:[String]=[],inCode=false
        func flush(){if !paragraph.isEmpty {output.append(.paragraph(paragraph.joined(separator:"\n")));paragraph=[]}}
        for raw in source.components(separatedBy:.newlines) {
            let line=raw.trimmingCharacters(in:.whitespaces)
            if line.hasPrefix("```") {flush();if inCode {output.append(.code(code.joined(separator:"\n")));code=[]};inCode.toggle();continue}
            if inCode {code.append(raw);continue}
            if line.isEmpty {flush();continue}
            let hashes=line.prefix(while:{$0=="#"}).count
            if (1...6).contains(hashes),line.dropFirst(hashes).first==" " {flush();output.append(.heading(hashes,String(line.dropFirst(hashes+1))));continue}
            if ["- ","* ","+ "].contains(where:{line.hasPrefix($0)}) {flush();output.append(.bullet(String(line.dropFirst(2))));continue}
            if line.hasPrefix("> ") {flush();output.append(.quote(String(line.dropFirst(2))));continue}
            let digits=line.prefix(while:{$0.isNumber && $0.isASCII})
            if !digits.isEmpty,digits.count<=4,line.dropFirst(digits.count).hasPrefix(". ") {flush();output.append(.numbered(String(digits)+".",String(line.dropFirst(digits.count+2))));continue}
            paragraph.append(raw)
        }
        flush();if inCode {output.append(.code(code.joined(separator:"\n")))}
        return output
    }
}
