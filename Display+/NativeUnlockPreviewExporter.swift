import AppKit
import Foundation

struct NativeUnlockPreviewDocument: Codable {
    let createdAt: String
    let app: String
    let warning: String
    let display: NativeUnlockDisplayIdentity
    let requestedMode: NativeUnlockRequestedMode
    let strategy: NativeUnlockStrategy
    let nextSteps: [String]
}

struct NativeUnlockDisplayIdentity: Codable {
    let name: String
    let isBuiltIn: Bool
    let displayID: UInt32
    let vendorID: UInt32
    let vendorIDHex: String
    let productID: UInt32
    let productIDHex: String
    let serialNumber: UInt32
    let serialNumberHex: String
    let currentLogicalWidth: Int
    let currentLogicalHeight: Int
    let currentFramebufferWidth: Int
    let currentFramebufferHeight: Int
    let activeOutputWidth: Int
    let activeOutputHeight: Int
    let refreshRate: Double
    let rotation: Double
    let currentModeIsHiDPI: Bool
}

struct NativeUnlockRequestedMode: Codable {
    let looksLikeWidth: Int
    let looksLikeHeight: Int
    let framebufferWidth: Int
    let framebufferHeight: Int
    let wantsHiDPI: Bool
    let estimatedMegapixels: Double
    let aspectRatio: Double
}

struct NativeUnlockStrategy: Codable {
    let backend: String
    let status: String
    let reason: String
    let installState: String
    let requiresAdmin: Bool
    let likelyRequiresReboot: Bool
}

final class NativeUnlockPreviewExporter {
    static func export(
        display: BasicDisplayInfo,
        plan: CustomResolutionPlan
    ) -> URL? {
        let megapixels = Double(
            plan.requestedFramebufferWidth * plan.requestedFramebufferHeight
        ) / 1_000_000.0

        let aspectRatio = Double(plan.requestedLogicalWidth) /
            Double(max(plan.requestedLogicalHeight, 1))

        let document = NativeUnlockPreviewDocument(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            app: "Display+",
            warning: "Preview only. This file does not install or modify macOS display configuration.",
            display: NativeUnlockDisplayIdentity(
                name: display.name,
                isBuiltIn: display.isBuiltIn,
                displayID: display.id,
                vendorID: display.vendorID,
                vendorIDHex: display.vendorIDHex,
                productID: display.productID,
                productIDHex: display.productIDHex,
                serialNumber: display.serialNumber,
                serialNumberHex: display.serialNumberHex,
                currentLogicalWidth: display.logicalWidth,
                currentLogicalHeight: display.logicalHeight,
                currentFramebufferWidth: display.framebufferWidth,
                currentFramebufferHeight: display.framebufferHeight,
                activeOutputWidth: display.activeOutputWidth,
                activeOutputHeight: display.activeOutputHeight,
                refreshRate: display.refreshRate,
                rotation: display.rotation,
                currentModeIsHiDPI: display.isHiDPI
            ),
            requestedMode: NativeUnlockRequestedMode(
                looksLikeWidth: plan.requestedLogicalWidth,
                looksLikeHeight: plan.requestedLogicalHeight,
                framebufferWidth: plan.requestedFramebufferWidth,
                framebufferHeight: plan.requestedFramebufferHeight,
                wantsHiDPI: plan.wantsHiDPI,
                estimatedMegapixels: megapixels,
                aspectRatio: aspectRatio
            ),
            strategy: NativeUnlockStrategy(
                backend: plan.backendTitle,
                status: "Planned only",
                reason: plan.message,
                installState: "Not installed",
                requiresAdmin: true,
                likelyRequiresReboot: true
            ),
            nextSteps: [
                "Generate a real display override payload for this display identity.",
                "Install the override using a privileged helper.",
                "Reboot or reload display configuration.",
                "Verify that macOS exposes the requested HiDPI mode.",
                "Apply the new mode through CGDisplaySetDisplayMode."
            ]
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(document)

            let exportFolder = FileManager.default.temporaryDirectory
                .appendingPathComponent("DisplayPlusNativeUnlockPreviews", isDirectory: true)

            try FileManager.default.createDirectory(
                at: exportFolder,
                withIntermediateDirectories: true
            )

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"

            let safeDisplayName = display.name
                .replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")

            let fileName = "NativeUnlock-\(safeDisplayName)-\(plan.requestedLogicalWidth)x\(plan.requestedLogicalHeight)-\(formatter.string(from: Date())).json"

            let fileURL = exportFolder.appendingPathComponent(fileName)

            try data.write(to: fileURL, options: [.atomic])

            NSWorkspace.shared.activateFileViewerSelecting([fileURL])

            return fileURL
        } catch {
            print("Failed to export native unlock preview: \(error)")
            return nil
        }
    }
}
