import AppKit
import Foundation

struct NativeOverridePlistPreview {
    let folderName: String
    let fileName: String
    let targetInstallPath: String
    let plistXML: String
    let encodedScaleResolution: String
    let encodedScaleResolutions: [String]
    let modeCount: Int
}

final class NativeOverridePlistPreviewExporter {
    static func makePreview(
        display: BasicDisplayInfo,
        plan: CustomResolutionPlan
    ) -> NativeOverridePlistPreview {
        let item = HiDPIModePackItem(
            id: "\(plan.requestedLogicalWidth)x\(plan.requestedLogicalHeight)-\(plan.requestedFramebufferWidth)x\(plan.requestedFramebufferHeight)",
            logicalWidth: plan.requestedLogicalWidth,
            logicalHeight: plan.requestedLogicalHeight,
            framebufferWidth: plan.requestedFramebufferWidth,
            framebufferHeight: plan.requestedFramebufferHeight,
            framebufferMegapixels: Double(plan.requestedFramebufferWidth * plan.requestedFramebufferHeight) / 1_000_000.0,
            alreadyAvailable: false,
            recommended: true
        )

        let pack = HiDPIModePack(
            id: "\(display.vendorID)-\(display.productID)-single",
            displayID: display.id,
            displayName: display.name,
            vendorID: display.vendorID,
            productID: display.productID,
            serialNumber: display.serialNumber,
            items: [item]
        )

        return makePreview(display: display, pack: pack)
    }

    static func makePreview(
        display: BasicDisplayInfo,
        pack: HiDPIModePack
    ) -> NativeOverridePlistPreview {
        let vendorHex = hexPathComponent(display.vendorID)
        let productHex = hexPathComponent(display.productID)

        let folderName = "DisplayVendorID-\(vendorHex)"
        let fileName = "DisplayProductID-\(productHex)"
        let targetInstallPath = "/Library/Displays/Contents/Resources/Overrides/\(folderName)/\(fileName)"

        let encoded = pack.items.map { item in
            encodeResolutionData(
                width: item.framebufferWidth,
                height: item.framebufferHeight
            )
        }

        let scaleResolutionXML = encoded.map { value in
            """
                <data>
                \(value)
                </data>
            """
        }.joined(separator: "\n")

        let plistXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DisplayProductID</key>
            <integer>\(display.productID)</integer>

            <key>DisplayVendorID</key>
            <integer>\(display.vendorID)</integer>

            <key>scale-resolutions</key>
            <array>
        \(scaleResolutionXML)
            </array>
        </dict>
        </plist>
        """

        return NativeOverridePlistPreview(
            folderName: folderName,
            fileName: fileName,
            targetInstallPath: targetInstallPath,
            plistXML: plistXML,
            encodedScaleResolution: encoded.first ?? "",
            encodedScaleResolutions: encoded,
            modeCount: encoded.count
        )
    }

    static func export(
        display: BasicDisplayInfo,
        plan: CustomResolutionPlan
    ) -> URL? {
        let preview = makePreview(display: display, plan: plan)
        return exportPreview(preview, displayName: display.name, suffix: "\(plan.requestedFramebufferWidth)x\(plan.requestedFramebufferHeight)")
    }

    static func export(
        display: BasicDisplayInfo,
        pack: HiDPIModePack
    ) -> URL? {
        let preview = makePreview(display: display, pack: pack)
        return exportPreview(preview, displayName: display.name, suffix: "Pack-\(preview.modeCount)-modes")
    }

    static func validatePreview(_ preview: NativeOverridePlistPreview) -> Bool {
        guard let data = preview.plistXML.data(using: .utf8) else {
            return false
        }

        do {
            _ = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )

            guard !preview.plistXML.contains("DisplayProductName") else {
                return false
            }

            return preview.modeCount > 0
        } catch {
            print("Invalid preview plist: \(error)")
            return false
        }
    }

    private static func exportPreview(
        _ preview: NativeOverridePlistPreview,
        displayName: String,
        suffix: String
    ) -> URL? {
        do {
            let exportFolder = FileManager.default.temporaryDirectory
                .appendingPathComponent("DisplayPlusOverridePlistPreviews", isDirectory: true)

            try FileManager.default.createDirectory(
                at: exportFolder,
                withIntermediateDirectories: true
            )

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"

            let safeDisplayName = sanitizeFileName(displayName)
            let fileName = "OverridePreview-\(safeDisplayName)-\(suffix)-\(formatter.string(from: Date())).plist"
            let fileURL = exportFolder.appendingPathComponent(fileName)

            try preview.plistXML.write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )

            NSWorkspace.shared.activateFileViewerSelecting([fileURL])

            return fileURL
        } catch {
            print("Failed to export override plist preview: \(error)")
            return nil
        }
    }

    private static func encodeResolutionData(width: Int, height: Int) -> String {
        var widthBE = UInt32(width).bigEndian
        var heightBE = UInt32(height).bigEndian

        var data = Data()
        data.append(Data(bytes: &widthBE, count: MemoryLayout<UInt32>.size))
        data.append(Data(bytes: &heightBE, count: MemoryLayout<UInt32>.size))

        return data.base64EncodedString()
    }

    private static func hexPathComponent(_ value: UInt32) -> String {
        String(value, radix: 16, uppercase: false)
    }

    private static func sanitizeFileName(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }
}
