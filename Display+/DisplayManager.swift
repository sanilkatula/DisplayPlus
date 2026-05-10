import AppKit
import CoreGraphics
import Foundation
import Combine

struct BasicDisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool

    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32

    let logicalWidth: Int
    let logicalHeight: Int

    let framebufferWidth: Int
    let framebufferHeight: Int

    let activeOutputWidth: Int
    let activeOutputHeight: Int

    let rotation: Double
    let refreshRate: Double

    let modes: [DisplayModeInfo]

    var typeLabel: String {
        isBuiltIn ? "Built-in Display" : "External Display"
    }

    var isHiDPI: Bool {
        framebufferWidth >= logicalWidth * 2 &&
        framebufferHeight >= logicalHeight * 2
    }

    var modeLabel: String {
        isHiDPI ? "HiDPI" : "LoDPI"
    }

    var vendorIDHex: String {
        String(format: "0x%08X", vendorID)
    }

    var productIDHex: String {
        String(format: "0x%08X", productID)
    }

    var serialNumberHex: String {
        String(format: "0x%08X", serialNumber)
    }

    var hardwareID: String {
        "Vendor \(vendorIDHex), Product \(productIDHex), Serial \(serialNumberHex)"
    }
}

struct DisplayModeInfo: Identifiable {
    let id: String
    let displayID: CGDirectDisplayID
    let mode: CGDisplayMode

    let logicalWidth: Int
    let logicalHeight: Int
    let framebufferWidth: Int
    let framebufferHeight: Int
    let refreshRate: Double

    var isHiDPI: Bool {
        framebufferWidth >= logicalWidth * 2 &&
        framebufferHeight >= logicalHeight * 2
    }

    var modeLabel: String {
        isHiDPI ? "HiDPI" : "LoDPI"
    }

    var refreshRateLabel: String {
        refreshRate > 0 ? "\(Int(refreshRate.rounded())) Hz" : "Default"
    }

    var title: String {
        "\(logicalWidth) × \(logicalHeight) · \(modeLabel) · \(refreshRateLabel)"
    }

    var subtitle: String {
        "Framebuffer \(framebufferWidth) × \(framebufferHeight)"
    }

    var compactTitle: String {
        "\(logicalWidth) × \(logicalHeight)"
    }
}

struct CustomResolutionPlan {
    enum Backend {
        case exposedMode
        case nativeUnlock
        case virtualDisplay
    }

    let requestedLogicalWidth: Int
    let requestedLogicalHeight: Int
    let requestedFramebufferWidth: Int
    let requestedFramebufferHeight: Int
    let wantsHiDPI: Bool
    let backend: Backend
    let matchingMode: DisplayModeInfo?
    let message: String

    var backendTitle: String {
        switch backend {
        case .exposedMode:
            return "Available now"
        case .nativeUnlock:
            return "Needs native HiDPI unlock"
        case .virtualDisplay:
            return "Needs virtual Retina fallback"
        }
    }

    var isImmediatelyApplyable: Bool {
        matchingMode != nil
    }
}

struct MissingHiDPICandidate: Identifiable {
    let id: String

    let logicalWidth: Int
    let logicalHeight: Int

    let framebufferWidth: Int
    let framebufferHeight: Int

    let aspectRatio: Double
    let framebufferMegapixels: Double
    let score: Int
    let reason: String

    var title: String {
        "\(logicalWidth) × \(logicalHeight) HiDPI"
    }

    var subtitle: String {
        "Framebuffer \(framebufferWidth) × \(framebufferHeight)"
    }

    var megapixelLabel: String {
        String(format: "%.1f MP", framebufferMegapixels)
    }
}

struct HiDPIModePackItem: Identifiable, Hashable {
    let id: String

    let logicalWidth: Int
    let logicalHeight: Int

    let framebufferWidth: Int
    let framebufferHeight: Int

    let framebufferMegapixels: Double
    let alreadyAvailable: Bool
    let recommended: Bool

    var title: String {
        "\(logicalWidth) × \(logicalHeight)"
    }

    var subtitle: String {
        "Framebuffer \(framebufferWidth) × \(framebufferHeight)"
    }

    var megapixelLabel: String {
        String(format: "%.1f MP", framebufferMegapixels)
    }
}

struct HiDPIModePack: Identifiable {
    let id: String
    let displayID: CGDirectDisplayID
    let displayName: String
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let items: [HiDPIModePackItem]

    var installableItems: [HiDPIModePackItem] {
        items.filter { !$0.alreadyAvailable }
    }

    var title: String {
        "HiDPI Mode Pack"
    }

    var summary: String {
        "\(items.count) Retina modes"
    }

    var hasMissingModes: Bool {
        items.contains { !$0.alreadyAvailable }
    }
}

private struct DisplayModeExport: Codable {
    let logicalWidth: Int
    let logicalHeight: Int
    let framebufferWidth: Int
    let framebufferHeight: Int
    let refreshRate: Double
    let isHiDPI: Bool
}

private struct DisplayExport: Codable {
    let name: String
    let isBuiltIn: Bool
    let displayID: UInt32
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let currentLogicalWidth: Int
    let currentLogicalHeight: Int
    let currentFramebufferWidth: Int
    let currentFramebufferHeight: Int
    let currentModeIsHiDPI: Bool
    let activeOutputWidth: Int
    let activeOutputHeight: Int
    let rotation: Double
    let refreshRate: Double
    let modes: [DisplayModeExport]
}

private struct DisplayExportReport: Codable {
    let createdAt: String
    let displays: [DisplayExport]
}

final class DisplayManager: ObservableObject {
    @Published var displays: [BasicDisplayInfo] = []

    init() {
        refreshDisplays()
    }

    func refreshDisplays() {
        var count: UInt32 = 0
        let countError = CGGetActiveDisplayList(0, nil, &count)

        guard countError == .success, count > 0 else {
            displays = []
            return
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let listError = CGGetActiveDisplayList(count, &displayIDs, &count)

        guard listError == .success else {
            displays = []
            return
        }

        displays = displayIDs.map { displayID in
            makeDisplayInfo(for: displayID)
        }
    }

    @discardableResult
    func applyMode(_ mode: DisplayModeInfo) -> CGError {
        let error = CGDisplaySetDisplayMode(mode.displayID, mode.mode, nil)

        if error != .success {
            print("Failed to apply mode: \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.refreshDisplays()
        }

        return error
    }

    func planCustomResolution(
        for display: BasicDisplayInfo,
        logicalWidth: Int,
        logicalHeight: Int,
        wantsHiDPI: Bool,
        preferredRefreshRate: Double?
    ) -> CustomResolutionPlan {
        let framebufferWidth = wantsHiDPI ? logicalWidth * 2 : logicalWidth
        let framebufferHeight = wantsHiDPI ? logicalHeight * 2 : logicalHeight

        let matchingModes = display.modes.filter { mode in
            let sameLogical = mode.logicalWidth == logicalWidth &&
                              mode.logicalHeight == logicalHeight

            let sameFramebuffer = mode.framebufferWidth == framebufferWidth &&
                                  mode.framebufferHeight == framebufferHeight

            let refreshMatches: Bool

            if let preferredRefreshRate {
                refreshMatches = Int(mode.refreshRate.rounded()) == Int(preferredRefreshRate.rounded())
            } else {
                refreshMatches = true
            }

            return sameLogical && sameFramebuffer && refreshMatches
        }

        if let exact = matchingModes.first {
            return CustomResolutionPlan(
                requestedLogicalWidth: logicalWidth,
                requestedLogicalHeight: logicalHeight,
                requestedFramebufferWidth: framebufferWidth,
                requestedFramebufferHeight: framebufferHeight,
                wantsHiDPI: wantsHiDPI,
                backend: .exposedMode,
                matchingMode: exact,
                message: "This exact mode already exists."
            )
        }

        if wantsHiDPI {
            let likelyNativeCandidate = isReasonableNativeHiDPICandidate(
                display: display,
                framebufferWidth: framebufferWidth,
                framebufferHeight: framebufferHeight
            )

            if likelyNativeCandidate {
                return CustomResolutionPlan(
                    requestedLogicalWidth: logicalWidth,
                    requestedLogicalHeight: logicalHeight,
                    requestedFramebufferWidth: framebufferWidth,
                    requestedFramebufferHeight: framebufferHeight,
                    wantsHiDPI: wantsHiDPI,
                    backend: .nativeUnlock,
                    matchingMode: nil,
                    message: "This HiDPI mode can be added with a native mode pack."
                )
            } else {
                return CustomResolutionPlan(
                    requestedLogicalWidth: logicalWidth,
                    requestedLogicalHeight: logicalHeight,
                    requestedFramebufferWidth: framebufferWidth,
                    requestedFramebufferHeight: framebufferHeight,
                    wantsHiDPI: wantsHiDPI,
                    backend: .virtualDisplay,
                    matchingMode: nil,
                    message: "This framebuffer is large or unusual. Virtual Retina fallback is safer."
                )
            }
        }

        return CustomResolutionPlan(
            requestedLogicalWidth: logicalWidth,
            requestedLogicalHeight: logicalHeight,
            requestedFramebufferWidth: framebufferWidth,
            requestedFramebufferHeight: framebufferHeight,
            wantsHiDPI: wantsHiDPI,
            backend: .nativeUnlock,
            matchingMode: nil,
            message: "This custom LoDPI mode is not currently exposed."
        )
    }

    func generateRecommendedHiDPIModePack(for display: BasicDisplayInfo) -> HiDPIModePack? {
        guard !display.isBuiltIn else {
            return nil
        }

        let items = generateRecommendedHiDPIItems(for: display)

        guard !items.isEmpty else {
            return nil
        }

        return HiDPIModePack(
            id: "\(display.vendorID)-\(display.productID)-\(display.serialNumber)",
            displayID: display.id,
            displayName: display.name,
            vendorID: display.vendorID,
            productID: display.productID,
            serialNumber: display.serialNumber,
            items: items
        )
    }

    func generateMissingHiDPICandidates(for display: BasicDisplayInfo) -> [MissingHiDPICandidate] {
        generateRecommendedHiDPIItems(for: display)
            .filter { !$0.alreadyAvailable }
            .map { item in
                let reason: String

                if item.logicalWidth == display.logicalWidth &&
                    item.logicalHeight == display.logicalHeight {
                    reason = "same workspace, Retina framebuffer"
                } else if item.logicalWidth * item.logicalHeight < display.logicalWidth * display.logicalHeight {
                    reason = "larger UI, Retina framebuffer"
                } else {
                    reason = "more workspace, Retina framebuffer"
                }

                let score: Int

                if item.logicalWidth == display.logicalWidth &&
                    item.logicalHeight == display.logicalHeight {
                    score = 90
                } else if item.recommended {
                    score = 80
                } else {
                    score = 70
                }

                return MissingHiDPICandidate(
                    id: item.id,
                    logicalWidth: item.logicalWidth,
                    logicalHeight: item.logicalHeight,
                    framebufferWidth: item.framebufferWidth,
                    framebufferHeight: item.framebufferHeight,
                    aspectRatio: Double(item.logicalWidth) / Double(max(item.logicalHeight, 1)),
                    framebufferMegapixels: item.framebufferMegapixels,
                    score: score,
                    reason: reason
                )
            }
    }

    func exportModeReport() {
        let report = DisplayExportReport(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            displays: displays.map { display in
                DisplayExport(
                    name: display.name,
                    isBuiltIn: display.isBuiltIn,
                    displayID: display.id,
                    vendorID: display.vendorID,
                    productID: display.productID,
                    serialNumber: display.serialNumber,
                    currentLogicalWidth: display.logicalWidth,
                    currentLogicalHeight: display.logicalHeight,
                    currentFramebufferWidth: display.framebufferWidth,
                    currentFramebufferHeight: display.framebufferHeight,
                    currentModeIsHiDPI: display.isHiDPI,
                    activeOutputWidth: display.activeOutputWidth,
                    activeOutputHeight: display.activeOutputHeight,
                    rotation: display.rotation,
                    refreshRate: display.refreshRate,
                    modes: display.modes.map { mode in
                        DisplayModeExport(
                            logicalWidth: mode.logicalWidth,
                            logicalHeight: mode.logicalHeight,
                            framebufferWidth: mode.framebufferWidth,
                            framebufferHeight: mode.framebufferHeight,
                            refreshRate: mode.refreshRate,
                            isHiDPI: mode.isHiDPI
                        )
                    }
                )
            }
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data = try encoder.encode(report)

            let exportFolder = FileManager.default.temporaryDirectory
                .appendingPathComponent("DisplayPlusExports", isDirectory: true)

            try FileManager.default.createDirectory(
                at: exportFolder,
                withIntermediateDirectories: true
            )

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"

            let fileName = "DisplayPlus-ModeReport-\(formatter.string(from: Date())).json"
            let fileURL = exportFolder.appendingPathComponent(fileName)

            try data.write(to: fileURL, options: [.atomic])
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } catch {
            print("Failed to export mode report: \(error)")
        }
    }

    private func generateRecommendedHiDPIItems(for display: BasicDisplayInfo) -> [HiDPIModePackItem] {
        let displayAspect = Double(display.activeOutputWidth) / Double(max(display.activeOutputHeight, 1))

        var logicalSizes = Set<String>()

        func add(width: Int, height: Int) {
            guard width >= 1000, height >= 600 else { return }
            logicalSizes.insert("\(width)x\(height)")
        }

        add(width: display.logicalWidth, height: display.logicalHeight)

        let commonWidths = [
            1280,
            1366,
            1440,
            1512,
            1600,
            1680,
            1728,
            1800,
            1920,
            2048,
            2304,
            2560
        ]

        for width in commonWidths {
            let rawHeight = Double(width) / displayAspect
            let height = makeEven(Int(rawHeight.rounded()))
            add(width: width, height: height)
        }

        let items = logicalSizes.compactMap { key -> HiDPIModePackItem? in
            let parts = key.split(separator: "x")

            guard parts.count == 2,
                  let logicalWidth = Int(parts[0]),
                  let logicalHeight = Int(parts[1]) else {
                return nil
            }

            let candidateAspect = Double(logicalWidth) / Double(max(logicalHeight, 1))
            let aspectDifference = abs(candidateAspect - displayAspect)

            guard aspectDifference <= 0.03 else {
                return nil
            }

            let framebufferWidth = logicalWidth * 2
            let framebufferHeight = logicalHeight * 2
            let megapixels = Double(framebufferWidth * framebufferHeight) / 1_000_000.0

            guard megapixels <= 25 else {
                return nil
            }

            let alreadyAvailable = display.modes.contains { mode in
                mode.logicalWidth == logicalWidth &&
                mode.logicalHeight == logicalHeight &&
                mode.framebufferWidth == framebufferWidth &&
                mode.framebufferHeight == framebufferHeight
            }

            let logicalArea = logicalWidth * logicalHeight
            let currentArea = display.logicalWidth * display.logicalHeight
            let areaRatio = Double(logicalArea) / Double(max(currentArea, 1))

            let recommended = areaRatio >= 0.70 && areaRatio <= 1.35

            return HiDPIModePackItem(
                id: "\(logicalWidth)x\(logicalHeight)-\(framebufferWidth)x\(framebufferHeight)",
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                framebufferWidth: framebufferWidth,
                framebufferHeight: framebufferHeight,
                framebufferMegapixels: megapixels,
                alreadyAvailable: alreadyAvailable,
                recommended: recommended
            )
        }

        return items.sorted { a, b in
            if a.logicalWidth == display.logicalWidth &&
                a.logicalHeight == display.logicalHeight {
                return true
            }

            if b.logicalWidth == display.logicalWidth &&
                b.logicalHeight == display.logicalHeight {
                return false
            }

            if a.recommended != b.recommended {
                return a.recommended && !b.recommended
            }

            return a.logicalWidth < b.logicalWidth
        }
    }

    private func isReasonableNativeHiDPICandidate(
        display: BasicDisplayInfo,
        framebufferWidth: Int,
        framebufferHeight: Int
    ) -> Bool {
        let framebufferMegapixels = Double(framebufferWidth * framebufferHeight) / 1_000_000.0

        if framebufferMegapixels > 25 {
            return false
        }

        let aspectDisplay = Double(display.activeOutputWidth) / Double(max(display.activeOutputHeight, 1))
        let aspectRequested = Double(framebufferWidth) / Double(max(framebufferHeight, 1))
        let aspectDifference = abs(aspectDisplay - aspectRequested)

        if aspectDifference > 0.15 {
            return false
        }

        return true
    }

    private func makeDisplayInfo(for displayID: CGDirectDisplayID) -> BasicDisplayInfo {
        let currentMode = CGDisplayCopyDisplayMode(displayID)
        let modes = getModes(for: displayID)

        return BasicDisplayInfo(
            id: displayID,
            name: displayName(for: displayID),
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,

            vendorID: CGDisplayVendorNumber(displayID),
            productID: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID),

            logicalWidth: currentMode?.width ?? CGDisplayPixelsWide(displayID),
            logicalHeight: currentMode?.height ?? CGDisplayPixelsHigh(displayID),

            framebufferWidth: currentMode?.pixelWidth ?? CGDisplayPixelsWide(displayID),
            framebufferHeight: currentMode?.pixelHeight ?? CGDisplayPixelsHigh(displayID),

            activeOutputWidth: CGDisplayPixelsWide(displayID),
            activeOutputHeight: CGDisplayPixelsHigh(displayID),

            rotation: CGDisplayRotation(displayID),
            refreshRate: currentMode?.refreshRate ?? 0,

            modes: modes
        )
    }

    private func getModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        let options = [
            kCGDisplayShowDuplicateLowResolutionModes as String: true
        ] as CFDictionary

        guard let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return []
        }

        var seen = Set<String>()

        let modes: [DisplayModeInfo] = rawModes.compactMap { mode in
            let key = [
                "\(mode.width)",
                "\(mode.height)",
                "\(mode.pixelWidth)",
                "\(mode.pixelHeight)",
                "\(Int(mode.refreshRate.rounded()))"
            ].joined(separator: "-")

            guard !seen.contains(key) else {
                return nil
            }

            seen.insert(key)

            return DisplayModeInfo(
                id: "\(displayID)-\(key)",
                displayID: displayID,
                mode: mode,
                logicalWidth: mode.width,
                logicalHeight: mode.height,
                framebufferWidth: mode.pixelWidth,
                framebufferHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate
            )
        }

        return modes.sorted { a, b in
            if a.isHiDPI != b.isHiDPI {
                return a.isHiDPI && !b.isHiDPI
            }

            if a.logicalWidth != b.logicalWidth {
                return a.logicalWidth > b.logicalWidth
            }

            if a.logicalHeight != b.logicalHeight {
                return a.logicalHeight > b.logicalHeight
            }

            return a.refreshRate > b.refreshRate
        }
    }

    private func displayName(for displayID: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber

            if number?.uint32Value == displayID {
                return screen.localizedName
            }
        }

        return "Display \(displayID)"
    }

    private func makeEven(_ value: Int) -> Int {
        value % 2 == 0 ? value : value + 1
    }
}
