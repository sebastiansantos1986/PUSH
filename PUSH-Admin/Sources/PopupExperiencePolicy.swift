// PUSH / Regina Pro notification patterns — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation

struct PopupPresentation:Codable,Equatable {
    var width:Double=480,height:Double=680
    var greetingTemplate="Hello {fullName}"
    var bannerText="Your IT team · macOS preview"
    var bannerImage:Data?
    func validated()throws->Self {
        guard width.isFinite,height.isFinite,(360...900).contains(width),(240...1000).contains(height),greetingTemplate.count<=160,bannerText.count<=200,(bannerImage?.count ?? 0)<=262144 else {throw MajorUpgradeDemoError.invalid("Choose width 360–900, height 240–1000, short banner/greeting text and a banner PNG below 256 KB.")}
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
