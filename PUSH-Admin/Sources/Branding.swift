// PUSH Admin — Developer: Sebastian Santos
// Copyright (c) 2026 Sebastian Santos. All rights reserved.
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

let deployedPopupLogoPath = "/Library/Management/PUSH/assets/popup-logo.png"

enum LogoChoice: String, CaseIterable, Identifiable {
    case standard = "Default PUSH icon", custom = "Custom image", symbol = "System symbol"
    var id: String { rawValue }
}
struct LogoSymbol: Identifiable {
    let id: String, title: String
}
let popupSymbols = [
    LogoSymbol(id:"arrow.down.circle.fill",title:"Update"),
    LogoSymbol(id:"apple.logo",title:"Apple"),
    LogoSymbol(id:"building.2.fill",title:"Organization"),
    LogoSymbol(id:"shield.lefthalf.filled",title:"Security"),
    LogoSymbol(id:"gearshape.fill",title:"Settings"),
    LogoSymbol(id:"desktopcomputer",title:"Computer"),
    LogoSymbol(id:"checkmark.seal.fill",title:"Verified"),
    LogoSymbol(id:"bolt.circle.fill",title:"Power")
]

enum BrandingImage {
    /// Convert an admin-selected image to a bounded, metadata-free PNG asset.
    static func normalizedPNG(_ input: Data) throws -> Data {
        guard !input.isEmpty, input.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(input as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              (1...16384).contains(width.intValue), (1...16384).contains(height.intValue) else {
            throw AdminError.message("Choose a PNG, JPEG, or TIFF image under 20 MB and no larger than 16,384 pixels per side.")
        }
        let options: [CFString:Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AdminError.message("That image could not be decoded. Try a PNG or JPEG export.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw AdminError.message("Could not prepare the logo image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), data.length <= 1_048_576 else {
            throw AdminError.message("The normalized logo is too large. Try a simpler image.")
        }
        return data as Data
    }
}

extension AdminStore {
    var selectedLogoChoice: LogoChoice {
        if !(document.value("ui.logoPath") ?? "").isEmpty { return .custom }
        if !(document.value("ui.sfSymbolName") ?? "").isEmpty { return .symbol }
        return .standard
    }
    var previewLogoURL: URL {
        draftURL.deletingLastPathComponent().appendingPathComponent("preview-popup-logo.png")
    }
    var previewLogoImageData: Data? {
        guard document.value("ui.logoPath") == deployedPopupLogoPath else { return nil }
        return document.logoImageData
    }
    var previewYAML: String {
        var preview = document
        if document.logoImageData != nil, document.value("ui.logoPath") == deployedPopupLogoPath {
            preview.edits["ui.logoPath"] = previewLogoURL.path
        }
        return preview.yaml
    }
    func persistPreviewLogo() throws {
        guard let data = document.logoImageData else { return }
        if (try? Data(contentsOf: previewLogoURL)) != data {
            try data.write(to: previewLogoURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath:previewLogoURL.path)
        }
    }
    func changeLogoChoice(_ choice: LogoChoice) {
        switch choice {
        case .standard:
            document.edits["ui.logoPath"] = ""
            document.edits["ui.sfSymbolName"] = ""
            document.logoImageData = nil; document.logoImageName = nil
            notice = "The default PUSH icon is selected for this draft."
        case .custom: choosePopupLogo()
        case .symbol:
            document.edits["ui.logoPath"] = ""
            if (document.value("ui.sfSymbolName") ?? "").isEmpty { document.edits["ui.sfSymbolName"] = popupSymbols[0].id }
            document.logoImageData = nil; document.logoImageName = nil
        }
    }
    func choosePopupLogo() {
        let panel = NSOpenPanel()
        panel.title = "Choose a popup logo"
        panel.message = "PNG, JPEG, or TIFF. A square image with a transparent background works best. The original image will not be modified."
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 20 * 1024 * 1024 else { throw AdminError.message("Choose an image smaller than 20 MB.") }
            let image = try BrandingImage.normalizedPNG(Data(contentsOf:url))
            document.logoImageData = image; document.logoImageName = url.lastPathComponent
            document.edits["ui.logoPath"] = deployedPopupLogoPath
            document.edits["ui.sfSymbolName"] = ""
            notice = "Logo added to the popup preview. No Save or Apply is needed to see it. Export or Apply only when you are ready to deploy."
        } catch { notice = error.localizedDescription }
    }
    func selectPopupSymbol(_ symbol: LogoSymbol) {
        document.edits["ui.logoPath"] = ""; document.edits["ui.sfSymbolName"] = symbol.id
        document.logoImageData = nil; document.logoImageName = nil
    }
}

struct PopupLogoControls: View {
    @EnvironmentObject var store: AdminStore
    var body: some View {
        VStack(alignment:.leading, spacing:12) {
            HStack(alignment:.center, spacing:14) {
                AppIconView(config:UIConfig.fromAdminYAML(store.previewYAML),size:54)
                    .environment(\.popupPreviewLogoData, store.previewLogoImageData)
                    .environment(\.popupPreviewLogoAction, {store.choosePopupLogo()})
                VStack(alignment:.leading, spacing:5) {
                    Text("Popup icon").font(.headline)
                    Picker("Icon",selection:Binding(get:{store.selectedLogoChoice},set:{store.changeLogoChoice($0)})) {
                        ForEach(LogoChoice.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().pickerStyle(.menu)
                }
                Spacer()
                if store.selectedLogoChoice == .custom { Button("Choose image…") {store.choosePopupLogo()} }
            }
            if store.selectedLogoChoice == .custom {
                Text(store.document.logoImageName ?? "Logo referenced by the imported YAML").font(.caption).foregroundStyle(.secondary)
                if store.document.logoImageData != nil && store.document.value("ui.logoPath") == deployedPopupLogoPath {
                    Text("Deployment path: " + deployedPopupLogoPath).font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
                } else {
                    Text("The image must exist at the configured path on each Mac. Choose an image here to include a managed PNG with the export.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.selectedLogoChoice == .symbol {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:80))],spacing:8) {
                    ForEach(popupSymbols) { symbol in
                        Button {store.selectPopupSymbol(symbol)} label:{
                            VStack(spacing:5) {Image(systemName:symbol.id).font(.title3);Text(symbol.title).font(.caption2)}
                                .frame(maxWidth:.infinity).padding(9)
                                .background(store.document.value("ui.sfSymbolName") == symbol.id ? Color.blue.opacity(0.14):Color.primary.opacity(0.035))
                                .clipShape(RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if store.pushInstalled, let version = versionParts(store.pushVersion), version.lexicographicallyPrecedes([1,2,2]) {
                Text("For custom icons in live popups, update the PUSH engine to 1.2.2 or later. Studio can preview them now.").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

struct PopupPreviewIdentity: Hashable {
    let revision: UUID
    let yaml: String
    let imageData: Data?
}
