import AppKit
import Foundation

struct NativeOverrideAutoInstallResult {
    let success: Bool
    let message: String
    let targetPath: String
    let output: String
}

final class NativeOverrideAutoInstaller {
    static func install(
        display: BasicDisplayInfo,
        plan: CustomResolutionPlan
    ) -> NativeOverrideAutoInstallResult {
        let preview = NativeOverridePlistPreviewExporter.makePreview(
            display: display,
            plan: plan
        )

        return installPreviews([preview], label: display.name)
    }

    static func install(
        display: BasicDisplayInfo,
        pack: HiDPIModePack
    ) -> NativeOverrideAutoInstallResult {
        guard !display.isBuiltIn else {
            return NativeOverrideAutoInstallResult(
                success: false,
                message: "Refusing to install native override for built-in display.",
                targetPath: "",
                output: ""
            )
        }

        let preview = NativeOverridePlistPreviewExporter.makePreview(
            display: display,
            pack: pack
        )

        return installPreviews([preview], label: display.name)
    }

    static func install(
        displayPacks: [(display: BasicDisplayInfo, pack: HiDPIModePack)]
    ) -> NativeOverrideAutoInstallResult {
        let previews = displayPacks.compactMap { pair -> NativeOverridePlistPreview? in
            guard !pair.display.isBuiltIn else {
                return nil
            }

            return NativeOverridePlistPreviewExporter.makePreview(
                display: pair.display,
                pack: pair.pack
            )
        }

        guard !previews.isEmpty else {
            return NativeOverrideAutoInstallResult(
                success: false,
                message: "No external display packs to install.",
                targetPath: "",
                output: ""
            )
        }

        return installPreviews(previews, label: "\(previews.count) display pack(s)")
    }

    static func uninstall(
        display: BasicDisplayInfo,
        plan: CustomResolutionPlan
    ) -> NativeOverrideAutoInstallResult {
        let preview = NativeOverridePlistPreviewExporter.makePreview(
            display: display,
            plan: plan
        )

        return uninstallPreview(preview)
    }

    static func uninstall(
        display: BasicDisplayInfo,
        pack: HiDPIModePack
    ) -> NativeOverrideAutoInstallResult {
        let preview = NativeOverridePlistPreviewExporter.makePreview(
            display: display,
            pack: pack
        )

        return uninstallPreview(preview)
    }

    private static func installPreviews(
        _ previews: [NativeOverridePlistPreview],
        label: String
    ) -> NativeOverrideAutoInstallResult {
        for preview in previews {
            guard NativeOverridePlistPreviewExporter.validatePreview(preview) else {
                return NativeOverrideAutoInstallResult(
                    success: false,
                    message: "Generated plist failed local validation. Nothing was installed.",
                    targetPath: preview.targetInstallPath,
                    output: ""
                )
            }

            guard !preview.plistXML.contains("DisplayProductName") else {
                return NativeOverrideAutoInstallResult(
                    success: false,
                    message: "Generated plist contains DisplayProductName. Refusing to install.",
                    targetPath: preview.targetInstallPath,
                    output: ""
                )
            }
        }

        let shellCommand = makeInstallShellCommand(previews: previews)
        let result = runAppleScriptWithAdministratorPrivileges(shellCommand)

        let targetPaths = previews.map(\.targetInstallPath).joined(separator: "\n")

        if result.success {
            return NativeOverrideAutoInstallResult(
                success: true,
                message: "Installed \(label). Restart once, then the HiDPI modes should appear.",
                targetPath: targetPaths,
                output: result.output
            )
        } else {
            return NativeOverrideAutoInstallResult(
                success: false,
                message: result.message,
                targetPath: targetPaths,
                output: result.output
            )
        }
    }

    private static func makeInstallShellCommand(
        previews: [NativeOverridePlistPreview]
    ) -> String {
        var commands: [String] = [
            "set -euo pipefail",
            "echo 'Display+ HiDPI Pack Installer'"
        ]

        for preview in previews {
            guard let plistData = preview.plistXML.data(using: .utf8) else {
                continue
            }

            let targetDir = "/Library/Displays/Contents/Resources/Overrides/\(preview.folderName)"
            let targetFile = "\(targetDir)/\(preview.fileName)"
            let backupRoot = "/Library/Displays/Contents/Resources/Overrides/DisplayPlusBackups"
            let backupName = "\(preview.folderName)-\(preview.fileName)"
            let plistBase64 = plistData.base64EncodedString()

            commands.append(contentsOf: [
                "echo 'Installing Display+ override: \(targetFile)'",
                "TARGET_DIR=\(shellQuote(targetDir))",
                "TARGET_FILE=\(shellQuote(targetFile))",
                "BACKUP_ROOT=\(shellQuote(backupRoot))",
                "BACKUP_NAME=\(shellQuote(backupName))",
                "PLIST_BASE64=\(shellQuote(plistBase64))",
                "TMP_FILE=$(/usr/bin/mktemp /tmp/displayplus-override.XXXXXX)",
                "trap 'rm -f \"$TMP_FILE\"' EXIT",
                "printf %s \"$PLIST_BASE64\" | /usr/bin/base64 -D > \"$TMP_FILE\"",
                "/usr/bin/plutil -lint \"$TMP_FILE\"",
                "if /usr/bin/grep -q DisplayProductName \"$TMP_FILE\"; then echo 'ERROR: Refusing to install plist containing DisplayProductName'; exit 20; fi",
                "/bin/mkdir -p \"$TARGET_DIR\"",
                "/bin/mkdir -p \"$BACKUP_ROOT\"",
                "if [ -e \"$TARGET_FILE\" ]; then BACKUP_DIR=\"$BACKUP_ROOT/$BACKUP_NAME-$(date +%Y%m%d-%H%M%S)\"; /bin/mkdir -p \"$BACKUP_DIR\"; /bin/cp \"$TARGET_FILE\" \"$BACKUP_DIR/\(preview.fileName).backup\"; echo \"Backup created at: $BACKUP_DIR\"; fi",
                "/bin/cp \"$TMP_FILE\" \"$TARGET_FILE\"",
                "/usr/sbin/chown root:wheel \"$TARGET_FILE\"",
                "/bin/chmod 644 \"$TARGET_FILE\"",
                "/usr/bin/plutil -lint \"$TARGET_FILE\"",
                "if /usr/bin/grep -q DisplayProductName \"$TARGET_FILE\"; then echo 'ERROR: Installed plist contains DisplayProductName'; /bin/rm \"$TARGET_FILE\"; exit 21; fi",
                "rm -f \"$TMP_FILE\""
            ])
        }

        commands.append("echo 'Done. Restart is required.'")

        return commands.joined(separator: "\n")
    }

    private static func uninstallPreview(
        _ preview: NativeOverridePlistPreview
    ) -> NativeOverrideAutoInstallResult {
        let targetFile = preview.targetInstallPath

        let shellCommand = [
            "set -euo pipefail",
            "TARGET_FILE=\(shellQuote(targetFile))",
            "if [ -e \"$TARGET_FILE\" ]; then /bin/rm \"$TARGET_FILE\"; echo Removed Display+ override at: \"$TARGET_FILE\"; else echo No override found at: \"$TARGET_FILE\"; fi",
            "echo Restart is required."
        ].joined(separator: "\n")

        let result = runAppleScriptWithAdministratorPrivileges(shellCommand)

        if result.success {
            return NativeOverrideAutoInstallResult(
                success: true,
                message: "Native override removed. Restart for the change to apply.",
                targetPath: targetFile,
                output: result.output
            )
        } else {
            return NativeOverrideAutoInstallResult(
                success: false,
                message: result.message,
                targetPath: targetFile,
                output: result.output
            )
        }
    }

    private static func runAppleScriptWithAdministratorPrivileges(
        _ shellCommand: String
    ) -> (success: Bool, message: String, output: String) {
        let appleScriptSource = """
        do shell script \(appleScriptQuotedString(shellCommand)) with administrator privileges
        """

        guard let script = NSAppleScript(source: appleScriptSource) else {
            return (
                false,
                "Could not create AppleScript installer.",
                ""
            )
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
            let errorMessage = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error."

            if errorNumber == -128 {
                return (
                    false,
                    "Administrator prompt was cancelled.",
                    errorMessage
                )
            }

            return (
                false,
                "AppleScript admin install failed: \(errorMessage)",
                "\(errorInfo)"
            )
        }

        let output = result.stringValue ?? ""

        return (
            true,
            "Command completed successfully.",
            output
        )
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptQuotedString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escaped)\""
    }
}
