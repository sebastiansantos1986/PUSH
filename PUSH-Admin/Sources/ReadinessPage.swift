// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct ReadinessPage: View {
    @EnvironmentObject var store:AdminStore
    var navigate:(AdminPage)->Void
    private func color(_ tone:DashboardTone)->Color {
        switch tone {case .good:return .green;case .attention:return .orange;case .waiting:return .blue;case .inactive:return .secondary;case .unknown:return .purple}
    }
    private func route(_ route:DashboardRoute)->AdminPage {
        switch route {case .monitoring:return .deployment;case .macPolicy:return .configuration;case .apps:return .apps;case .entra:return .entra}
    }
    private func copy(_ text:String) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("Readiness & Next Action").font(.largeTitle.bold())
                        Text("Installed policy • saved evidence • background service status").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {Task{await store.refreshReadiness()}} label:{Label(store.isRefreshingReadiness ? "Reading…":"Refresh",systemImage:"arrow.clockwise")}.disabled(store.isRefreshingReadiness)
                }
                if let snapshot=store.readiness {
                    VStack(alignment:.leading,spacing:10) {
                        Label(snapshot.headline,systemImage:"info.circle").font(.title3.bold())
                        Text(snapshot.explanation).foregroundStyle(.secondary)
                        HStack {
                            Text("Read locally " + ReadinessSnapshot.stamp(snapshot.capturedAt) + " • Engine " + snapshot.engineVersion).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy summary"){copy(snapshot.summaryText)}
                            Button("Review monitoring"){navigate(.deployment)}
                        }
                    }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.blue.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:14))
                    HStack(alignment:.top,spacing:16) {
                        monitor("macOS & apps",snapshot.mainMonitor)
                        monitor("Entra registration",snapshot.entraMonitor)
                    }
                    ForEach(snapshot.modules) { item in
                        VStack(alignment:.leading,spacing:16) {
                            HStack {
                                Text(item.title).font(.title2.bold());Spacer()
                                Text(item.status).font(.callout.weight(.semibold)).foregroundStyle(color(item.tone)).padding(.horizontal,12).padding(.vertical,7).background(color(item.tone).opacity(0.1)).clipShape(Capsule())
                            }
                            Text(item.reason).fixedSize(horizontal:false,vertical:true)
                            LazyVGrid(columns:[GridItem(.flexible(),alignment:.leading),GridItem(.flexible(),alignment:.leading)],alignment:.leading,spacing:14) {
                                ForEach(item.facts) {fact in
                                    VStack(alignment:.leading,spacing:4){Text(fact.label.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary);Text(fact.value).font(.callout).textSelection(.enabled)}.frame(maxWidth:.infinity,alignment:.leading)
                                }
                            }
                            if let observed=item.observation {Text(observed).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
                            Divider()
                            Text("Next step: " + item.nextStep).font(.callout)
                            HStack {
                                Button("Review setup"){navigate(route(item.route))}
                                Button("Copy check command"){copy(item.checkCommand);store.notice="Check command copied. Run it in Terminal when you are ready; no check was started."}
                                Spacer()
                                Text("Refresh never runs this command").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(22).background(Color(NSColor.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:16))
                    }
                    Text("Eligibility is the earliest allowed time, not a guaranteed delivery time. Meetings, other prompts, user availability and installation activity can delay reminders. Saved results may change after the next check.").font(.caption).foregroundStyle(.secondary)
                } else {ProgressView("Reading installed readiness…").frame(maxWidth:.infinity,minHeight:240)}
            }.padding(26).frame(maxWidth:1200,alignment:.leading)
        }.task{await store.refreshReadiness()}
    }
    private func monitor(_ title:String,_ monitor:MonitorReadiness)->some View {
        VStack(alignment:.leading,spacing:8){Text(title).font(.headline);Label(monitor.title,systemImage:"circle.fill").foregroundStyle(color(monitor.tone));Text(monitor.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}.padding(18).frame(maxWidth:.infinity,alignment:.topLeading).background(Color(NSColor.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:12))
    }
}
