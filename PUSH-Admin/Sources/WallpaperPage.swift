// PUSH Admin — Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import SwiftUI
import AppKit

struct WallpaperPage:View {
    @EnvironmentObject var store:AdminStore
    var navigate:(AdminPage)->Void
    private func flag(_ key:String)->Binding<Bool> {Binding(get:{store.document.setupFlag(key)},set:{store.document.edits[key]=$0 ? "true":"false"})}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PageHeading(eyebrow:"Compliance wallpaper",title:"A visible reminder that stays in place.",subtitle:"Use a custom background while the Mac is below its configured macOS target. This page previews and stages images only.")
                AdminCard {
                    Toggle("Enable compliance wallpaper",isOn:flag("compliance.wallpaperEnabled"))
                    Text("Every eligible macOS check compares the active desktop image with the managed non-compliant background. If the user changed it, PUSH reapplies the managed image. There is no one-time transition shortcut.").foregroundStyle(.secondary)
                    Text("Automatic macOS checks must be enabled. Wallpaper compliance follows the configured macOS version; it does not claim all apps or cloud registration are compliant. Dry-run prevents wallpaper changes.").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Managed working directory",value:WallpaperPolicy.managedDirectory).font(.caption).textSelection(.enabled)
                }
                AdminCard {
                    Label("While the Mac is non-compliant",systemImage:"photo").font(.headline)
                    preview(role:"noncompliant")
                    HStack{Button("Choose custom background…"){store.chooseWallpaper(role:"noncompliant")}.buttonStyle(.borderedProminent);Button("Use PUSH default"){store.useDefaultWallpaper()}}
                    Text(store.document.wallpaperAssets?["noncompliant"]?.originalName ?? "Image referenced by this draft").font(.caption).foregroundStyle(.secondary)
                    Text(store.document.setupValue("compliance.nonCompliantWallpaper")).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                }
                AdminCard {
                    Label("After the macOS target is met",systemImage:"checkmark.circle").font(.headline)
                    Text("By default, restore the background captured before enforcement, and only when PUSH's image is still active. If the user has already changed their background, preserve that choice. You can select a compliant background instead.").foregroundStyle(.secondary)
                    if !store.document.setupValue("compliance.compliantWallpaper").isEmpty {preview(role:"compliant")}
                    HStack{Button("Restore previous personal background"){store.restorePersonalWallpaperChoice()};Button("Choose compliant background…"){store.chooseWallpaper(role:"compliant")}}
                    Text("Enforcement applies to the active user's connected displays. Backgrounds on other Spaces, dynamic/video desktops, disconnected displays and management-profile restrictions need pilot testing; restoration depends on a readable saved baseline.").font(.caption).foregroundStyle(.secondary)
                }
                AdminCard {
                    Label("Stage, export, then deploy",systemImage:"shippingbox").font(.headline)
                    Text("Custom images are normalized into static PNG files and saved in the Admin working folder. Export writes them next to your YAML; deploy those files to the managed directory shown above. Apply installs attached images into that directory before writing configuration. Selecting an image does not change this Mac's desktop.").foregroundStyle(.secondary)
                    HStack{Button("Export YAML & attached images…"){store.exportDocument()}.disabled(!store.document.problems.isEmpty);Button("Review deployment"){navigate(.deployment)};Button("Delivery history"){navigate(.history)}}
                    Text("The included PUSH default ships with the engine. Custom images referenced by imported YAML must already be deployed, or selected here again to attach them. Disabling this policy stops reapplication; it does not force a replacement personal image.").font(.caption).foregroundStyle(.secondary)
                }
                ValidationSummary()
            }.padding(28).frame(maxWidth:1200,alignment:.leading)
        }
    }
    @ViewBuilder private func preview(role:String)->some View {
        if let image=store.wallpaperPreview(role:role) {
            Image(nsImage:image).resizable().aspectRatio(contentMode:.fit).frame(maxWidth:.infinity,maxHeight:310).background(Color.black.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius:12))
            Text("PREVIEW ONLY · your desktop is unchanged").font(.caption2.bold()).foregroundStyle(.secondary)
        } else {ContentUnavailableView("Choose or deploy a background",systemImage:"photo",description:Text("This draft references an image that is not available for preview on this Mac."))}
    }
}
