import AppKit
import Foundation

struct NativeOverrideInstallPackage {
    let folderURL: URL
    let plistURL: URL
    let installScriptURL: URL
    let uninstallScriptURL: URL
    let readmeURL: URL
    let targetInstallPath: String
}

final class NativeOverrideInstallPackageExporter {
    static func export(
        display: BasicDisplayInfo,
        plan: CustomResolutionPlan
    ) -> NativeOverrideInstallPackage? {
        guard !display.isBuiltIn else {
            print("Refusing to export installer package for built-in display.")
            return nil
        }

        guard plan.backend == .nativeUnlock else {
            print("Refusing to export installer package because this is not a native unlock plan.")
            return nil
        }

        guard plan.wantsHiDPI else {
            print("Refusing to export installer package because this is not a HiDPI plan.")
            return nil
        }

        let preview = NativeOverridePlistPreviewExporter.makePreview(
            display: display,
            plan: plan
        )

        guard NativeOverridePlistPreviewExporter.validatePreview(preview) else {
            print("Refusing to export installer package because plist preview failed validation.")
            return nil
        }

        guard !preview.plistXML.contains("DisplayProductName") else {
            print("Refusing to export installer package because plist contains DisplayProductName.")
            return nil
        }

        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"

            let timestamp = formatter.string(from: Date())
            let safeDisplayName = sanitizeFileName(display.name)

            let packageFolder = FileManager.default.temporaryDirectory
                .appendingPathComponent("DisplayPlusNativeOverrideInstallers", isDirectory: true)
                .appendingPathComponent(
                    "Installer-\(safeDisplayName)-\(plan.requestedFramebufferWidth)x\(plan.requestedFramebufferHeight)-\(timestamp)",
                    isDirectory: true
                )

            try FileManager.default.createDirectory(
                at: packageFolder,
                withIntermediateDirectories: true
            )

            let plistURL = packageFolder.appendingPathComponent(preview.fileName)
            let installScriptURL = packageFolder.appendingPathComponent("install.sh")
            let uninstallScriptURL = packageFolder.appendingPathComponent("uninstall.sh")
            let readmeURL = packageFolder.appendingPathComponent("README.txt")

            try preview.plistXML.write(
                to: plistURL,
                atomically: true,
                encoding: .utf8
            )

            let installScript = makeInstallScript(
                preview: preview,
                display: display,
                plan: plan
            )

            let uninstallScript = makeUninstallScript(preview: preview)

            let readme = makeReadme(
                preview: preview,
                display: display,
                plan: plan
            )

            try installScript.write(
                to: installScriptURL,
                atomically: true,
                encoding: .utf8
            )

            try uninstallScript.write(
                to: uninstallScriptURL,
                atomically: true,
                encoding: .utf8
            )

            try readme.write(
                to: readmeURL,
                atomically: true,
                encoding: .utf8
            )

            try makeExecutable(installScriptURL)
            try makeExecutable(uninstallScriptURL)

            NSWorkspace.shared.activateFileViewerSelecting([packageFolder])

            return NativeOverrideInstallPackage(
                folderURL: packageFolder,
                plistURL: plistURL,
                installScriptURL: installScriptURL,
                uninstallScriptURL: uninstallScriptURL,
                readmeURL: readmeURL,
                targetInstallPath: preview.targetInstallPath
            )
        } catch {
            print("Failed to export native override installer package: \(error)")
            return nil
        }
    }

    private static func makeInstallScript(
        preview: NativeOverridePlistPreview,
        display: BasicDisplayInfo,
        plan: CustomResolutionPlan
    ) -> String {
        let targetDir = "/Library/Displays/Contents/Resources/Overrides/\(preview.folderName)"
        let targetFile = "\(targetDir)/\(preview.fileName)"
        let backupName = "\(preview.folderName)-\(preview.fileName)"

        return """
        #!/bin/zsh
        set -euo pipefail

        SOURCE_DIR="${0:A:h}"
        PLIST_SOURCE="$SOURCE_DIR/\(preview.fileName)"

        TARGET_DIR="\(targetDir)"
        TARGET_FILE="\(targetFile)"

        BACKUP_ROOT="/Library/Displays/Contents/Resources/Overrides/DisplayPlusBackups"
        BACKUP_DIR="$BACKUP_ROOT/\(backupName)-$(date +%Y%m%d-%H%M%S)"

        echo "Display+ Native Override Installer"
        echo "Display: \(display.name)"
        echo "Target: $TARGET_FILE"
        echo "Requested mode: looks like \(plan.requestedLogicalWidth)x\(plan.requestedLogicalHeight), framebuffer \(plan.requestedFramebufferWidth)x\(plan.requestedFramebufferHeight)"
        echo ""

        if [ ! -f "$PLIST_SOURCE" ]; then
            echo "ERROR: Source plist not found: $PLIST_SOURCE"
            exit 1
        fi

        echo "Validating source plist..."
        plutil -lint "$PLIST_SOURCE"

        if grep -q "DisplayProductName" "$PLIST_SOURCE"; then
            echo "ERROR: Refusing to install plist containing DisplayProductName."
            echo "This key previously caused WindowServer instability."
            exit 20
        fi

        echo "Creating target directory..."
        sudo mkdir -p "$TARGET_DIR"

        if [ -e "$TARGET_FILE" ]; then
            echo "Existing override found. Creating backup..."
            sudo mkdir -p "$BACKUP_DIR"
            sudo cp "$TARGET_FILE" "$BACKUP_DIR/\(preview.fileName).backup"
            echo "Backup created at: $BACKUP_DIR"
        fi

        echo "Installing override..."
        sudo cp "$PLIST_SOURCE" "$TARGET_FILE"
        sudo chown root:wheel "$TARGET_FILE"
        sudo chmod 644 "$TARGET_FILE"

        echo "Validating installed plist..."
        plutil -lint "$TARGET_FILE"

        if grep -q "DisplayProductName" "$TARGET_FILE"; then
            echo "ERROR: Installed plist unexpectedly contains DisplayProductName."
            echo "Removing installed override."
            sudo rm "$TARGET_FILE"
            exit 21
        fi

        echo ""
        echo "Done."
        echo "Restart your Mac, then open Display+ and check Available Now / Technical modes."
        echo "If anything looks wrong, disconnect the monitor, run uninstall.sh from this folder, and restart again."
        """
    }

    private static func makeUninstallScript(
        preview: NativeOverridePlistPreview
    ) -> String {
        let targetFile = "/Library/Displays/Contents/Resources/Overrides/\(preview.folderName)/\(preview.fileName)"

        return """
        #!/bin/zsh
        set -euo pipefail

        TARGET_FILE="\(targetFile)"

        echo "Display+ Native Override Uninstaller"
        echo "Target: $TARGET_FILE"
        echo ""

        if [ -e "$TARGET_FILE" ]; then
            echo "Removing override..."
            sudo rm "$TARGET_FILE"
            echo "Removed: $TARGET_FILE"
        else
            echo "No installed override found at: $TARGET_FILE"
        fi

        echo ""
        echo "Done."
        echo "Restart your Mac, then open Display+ and refresh displays."
        """
    }

    private static func makeReadme(
        preview: NativeOverridePlistPreview,
        display: BasicDisplayInfo,
        plan: CustomResolutionPlan
    ) -> String {
        return """
        Display+ Native HiDPI Override Installer Package

        DISPLAY
        Name: \(display.name)
        Vendor ID: \(display.vendorIDHex)
        Product ID: \(display.productIDHex)
        Serial: \(display.serialNumberHex)

        CURRENT MODE
        Logical / Looks Like: \(display.logicalWidth)x\(display.logicalHeight)
        Framebuffer: \(display.framebufferWidth)x\(display.framebufferHeight)
        Active Output: \(display.activeOutputWidth)x\(display.activeOutputHeight)
        Refresh Rate: \(display.refreshRate)
        HiDPI: \(display.isHiDPI)

        REQUESTED MODE
        Looks Like: \(plan.requestedLogicalWidth)x\(plan.requestedLogicalHeight)
        Framebuffer: \(plan.requestedFramebufferWidth)x\(plan.requestedFramebufferHeight)
        HiDPI: \(plan.wantsHiDPI)

        TARGET INSTALL PATH
        \(preview.targetInstallPath)

        FILES
        \(preview.fileName)
        install.sh
        uninstall.sh
        README.txt

        HOW TO INSTALL
        1. Open Terminal.
        2. Drag install.sh into Terminal and press Return.
        3. Enter your admin password when macOS asks.
        4. Restart your Mac.
        5. Open Display+.
        6. Check whether the new HiDPI mode appears in Available Now or Technical modes.

        HOW TO REMOVE
        1. Disconnect the external monitor if it causes crashes.
        2. Boot using the built-in display.
        3. Open Terminal.
        4. Drag uninstall.sh into Terminal and press Return.
        5. Restart your Mac.

        EMERGENCY CLEANUP
        If the monitor still causes WindowServer crashes, run:

        sudo rm -rf /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-*
        sudo rm -f /Library/Preferences/com.apple.windowserver.displays.plist
        rm -f ~/Library/Preferences/ByHost/com.apple.windowserver*.plist
        sudo reboot

        IMPORTANT
        This package modifies macOS display override configuration only when you run install.sh.
        Exporting this package does not install anything.
        The generated override intentionally does not include DisplayProductName.
        """
    }

    private static func makeExecutable(_ url: URL) throws {
        var attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        attributes[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private static func sanitizeFileName(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }
}
