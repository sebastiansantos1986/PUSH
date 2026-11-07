// PUSH — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit
import Combine

struct UpdateRecoveryView:View {
    @EnvironmentObject var ctx:UIContext
    @State private var now=Date()
    @State private var returned=false
    private let tick=Timer.publish(every:1,on:.main,in:.common).autoconnect()
    private var notice:RecoveryNotice {ctx.recoveryNotice}
    private var remaining:Int {notice.remaining(at:now)}
    private var clock:String {String(format:"%02d:%02d",remaining/60,remaining%60)}
    var body:some View {
        PopupCard(width:CGFloat(ctx.config.ui.popupWidth)) {
            PopupHeader(config:ctx.config,subtitle:"Update attempt needs attention",urgent:true)
            PushDivider()
            VStack(alignment:.leading,spacing:18) {
                Label("The update could not be completed",systemImage:"exclamationmark.triangle.fill").font(.title3.bold()).foregroundStyle(.orange)
                Text(notice.reason).fixedSize(horizontal:false,vertical:true)
                LabeledContent("Required macOS",value:notice.target)
                Text(notice.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                if notice.automatic,notice.retryAt != nil {
                    VStack(spacing:6) {
                        Text("Next guarded attempt in").font(.caption).foregroundStyle(.secondary)
                        Text(clock).font(.system(size:38,weight:.semibold,design:.monospaced)).foregroundStyle(ctx.config.accentColor)
                        Text("Closing this notice does not restart the clock.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity).padding(16).background(ctx.config.accentColor.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius:12))
                } else {Label("IT action or an explicit retry may be needed. No automatic countdown bypasses this condition.",systemImage:"person.crop.circle.badge.exclamationmark").font(.caption).foregroundStyle(.secondary)}
                ITContactStrip(config:ctx.config)
            }.padding(22)
            PushDivider()
            HStack {
                Button("Close") {ctx.exit(.dismiss)}.buttonStyle(PushSecondaryButtonStyle())
                Spacer()
                Button("Update now") {ctx.exit(.install)}.buttonStyle(PushPrimaryButtonStyle(color:ctx.config.accentColor)).keyboardShortcut(.return)
            }.padding(20)
        }
        .onReceive(tick){date in
            now=date
            guard !returned,notice.automatic,notice.countdownDue(at:now) else{return}
            returned=true;ctx.exit(.automaticRetry,automatic:true)
        }
    }
}
