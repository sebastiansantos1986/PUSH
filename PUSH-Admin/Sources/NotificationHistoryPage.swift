// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import Foundation

struct NotificationHistoryPage:View {
    var navigate:(AdminPage)->Void
    @State private var events:[NotificationHistoryEvent]=[]
    @State private var issue:String?
    @State private var checked:Date?
    @State private var includePreviews=false
    @State private var selection="All"
    private var entries:[NotificationTimelineEntry] {NotificationTimelineEntry.group(events.filter{(includePreviews || $0.mode != "preview") && (selection=="All" || $0.state==selection)})}
    private func refresh() {
        do {events=try NotificationHistoryReader.read("/Library/Management/PUSH/notification-history.json").events;issue=nil}
        catch {issue="Saved history could not be read. No checks or prompts were started."}
        checked=Date()
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                PageHeading(eyebrow:"Notification history",title:"Know what happened to the reminder.",subtitle:"Window appearance, user choices, delays and failures are separate saved observations.")
                HStack{Button("Refresh saved history"){refresh()};Button("Review monitoring"){navigate(.readiness)};Spacer();Toggle("Include engine previews",isOn:$includePreviews).toggleStyle(.switch)}
                Picker("State",selection:$selection){Text("All states").tag("All");ForEach(Array(Set(events.map{$0.state})).sorted(),id:\.self){Text($0).tag($0)}}
                Text("Read locally "+ReadinessSnapshot.stamp(checked)+". A window appearance is not proof the user read it. Nonblocking launches remain unconfirmed unless a visibility signal was received. A stopped monitor cannot record missed attempts.").font(.caption).foregroundStyle(.secondary)
                if let issue {Label(issue,systemImage:"exclamationmark.triangle").foregroundStyle(.orange)}
                if entries.isEmpty {ContentUnavailableView("No matching history yet",systemImage:"clock.badge.questionmark",description:Text("The updated engine records new attempts when it runs. Existing old logs are not invented as delivery records."))}
                LazyVStack(spacing:12) {
                    ForEach(entries){entry in
                        AdminCard {
                            HStack{Text(entry.last.state).font(.headline);Spacer();Text(entry.status).font(.callout.weight(.semibold)).foregroundStyle(entry.last.outcome=="failed" ? Color.orange:Color.primary)}
                            Text(entry.last.reason).textSelection(.enabled)
                            HStack{Text(ReadinessSnapshot.stamp(entry.last.date));Text(entry.last.mode=="preview" ? "SIMULATED ENGINE PREVIEW":entry.last.mode.uppercased());if let target=entry.last.target {Text("Configured target "+target)}}.font(.caption).foregroundStyle(.secondary)
                            if !["wallpaper","menuRequest"].contains(entry.last.state) {Label(entry.displayed ? "Window appearance confirmed":"No confirmed window appearance",systemImage:entry.displayed ? "checkmark.circle":"questionmark.circle").font(.caption).foregroundStyle(.secondary)}
                            if let retry=entry.last.retryAt {Text("Eligible for recheck after "+ReadinessSnapshot.stamp(retry)+"; policy and service availability still apply.").font(.caption).foregroundStyle(.secondary)}
                        }
                    }
                }
            }.padding(28).frame(maxWidth:1200,alignment:.leading)
        }.onAppear{refresh()}
    }
}
