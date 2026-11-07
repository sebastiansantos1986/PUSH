// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
struct NotificationTimelineEntry:Identifiable {
    let id:String
    let events:[NotificationHistoryEvent]
    var last:NotificationHistoryEvent {events.last!}
    var displayed:Bool {events.contains{$0.outcome=="displayed"}}
    var status:String {
        if last.outcome=="requested" {return "Delivery unconfirmed"}
        if last.state=="wallpaper" && last.outcome=="applied" {return "Wallpaper changed"}
        return ["response":"User response","displayed":"Window appeared","failed":"Failed","delayed":"Delayed","timeout":"Timed out","applied":"Applied","completed":"Completed"][last.outcome] ?? last.outcome
    }
    static func group(_ events:[NotificationHistoryEvent])->[Self] {
        Dictionary(grouping:events,by:{$0.attempt}).map{.init(id:$0.key,events:$0.value.sorted{$0.date<$1.date})}.sorted{$0.last.date>$1.last.date}
    }
}
enum NotificationHistoryReader {
    static func read(_ path:String)throws->NotificationHistoryDocument {
        guard FileManager.default.fileExists(atPath:path) else{return .init()}
        let input=try FileHandle(forReadingFrom:URL(fileURLWithPath:path));defer{try? input.close()}
        let data=try input.read(upToCount:1_048_577) ?? Data()
        guard data.count<=1_048_576 else {throw AdminError.message("History is larger than expected. Review the local file before retrying.")}
        return try JSONDecoder().decode(NotificationHistoryDocument.self,from:data)
    }
}
