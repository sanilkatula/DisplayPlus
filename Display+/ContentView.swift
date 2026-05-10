import SwiftUI
import CoreGraphics
import Foundation

private enum DisplaySubsection: String {
    case resolution
    case hidpi
    case refreshRate
    case controls
    case advanced
}

private enum InstallStateKind {
    case notInstalled
    case needsRestart
    case installed
    case partiallyLoaded
    case alreadyAvailable
}

private struct InstallState {
    let kind: InstallStateKind
    let title: String
    let detail: String

    var isPositive: Bool {
        kind == .installed || kind == .alreadyAvailable
    }

    var isWarning: Bool {
        kind == .needsRestart || kind == .partiallyLoaded
    }
}

private struct InstalledHiDPIResolution: Identifiable, Hashable {
    let framebufferWidth: Int
    let framebufferHeight: Int
    let logicalWidth: Int
    let logicalHeight: Int
    let isAvailableNow: Bool

    var id: String {
        "\(framebufferWidth)x\(framebufferHeight)"
    }

    var title: String {
        "\(logicalWidth) × \(logicalHeight) HiDPI"
    }

    var subtitle: String {
        "Framebuffer \(framebufferWidth) × \(framebufferHeight)"
    }

    var key: String {
        "\(framebufferWidth)x\(framebufferHeight)"
    }
}

struct DisplayPanelView: View {
    @StateObject private var displayManager = DisplayManager()

    @State private var expandedDisplayID: CGDirectDisplayID? = nil
    @State private var globalMessage: String? = nil
    @State private var globalMessageIsError: Bool = false
    @State private var isInstallingAllPacks: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if let globalMessage {
                globalStatusMessage(globalMessage, isError: globalMessageIsError)
            }

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(displayManager.displays) { display in
                        DisplayCardView(
                            display: display,
                            isExpanded: Binding(
                                get: {
                                    expandedDisplayID == display.id
                                },
                                set: { shouldExpand in
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedDisplayID = shouldExpand ? display.id : nil
                                    }
                                }
                            )
                        )
                        .environmentObject(displayManager)
                    }
                }
                .padding()
            }
        }
        .frame(width: 540, height: 780)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 34, height: 34)

                Image(systemName: "display")
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Display+")
                    .font(.headline)

                Text("\(displayManager.displays.count) display\(displayManager.displays.count == 1 ? "" : "s") connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                installAllConnectedPacks()
            } label: {
                if isInstallingAllPacks {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Set Up Displays", systemImage: "sparkles")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isInstallingAllPacks || installableExternalPacks().isEmpty)
            .help("Install HiDPI mode packs for all connected external displays")

            Button {
                displayManager.refreshDisplays()

                if let expandedDisplayID,
                   !displayManager.displays.contains(where: { $0.id == expandedDisplayID }) {
                    self.expandedDisplayID = nil
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh displays")
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func globalStatusMessage(_ message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(isError ? .orange : .secondary)

            Text(message)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                self.globalMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(10)
        .background(isError ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.10))
    }

    private func installableExternalPacks() -> [(display: BasicDisplayInfo, pack: HiDPIModePack)] {
        displayManager.displays.compactMap { display in
            guard let pack = displayManager.generateRecommendedHiDPIModePack(for: display) else {
                return nil
            }

            return (display: display, pack: pack)
        }
    }

    private func installAllConnectedPacks() {
        let packs = installableExternalPacks()

        guard !packs.isEmpty else {
            globalMessage = "No external display packs to install."
            globalMessageIsError = true
            return
        }

        isInstallingAllPacks = true
        globalMessage = "macOS will ask for your admin password. Display+ will set up Retina packs for all connected external displays."
        globalMessageIsError = false

        DispatchQueue.global(qos: .userInitiated).async {
            let result = NativeOverrideAutoInstaller.install(displayPacks: packs)

            DispatchQueue.main.async {
                isInstallingAllPacks = false

                if result.success {
                    globalMessage = "\(result.message) If the indicators say “Needs restart”, macOS has not loaded the new modes yet."
                    globalMessageIsError = false
                } else {
                    globalMessage = "Install failed: \(result.message)"
                    globalMessageIsError = true
                }
            }
        }
    }
}

struct DisplayCardView: View {
    @EnvironmentObject private var displayManager: DisplayManager

    let display: BasicDisplayInfo
    @Binding var isExpanded: Bool

    @State private var activeSubsection: DisplaySubsection? = nil

    @State private var brightness: Double = 0.7
    @State private var volume: Double = 0.5
    @State private var selectedRefreshModeID: String = ""

    @State private var lastActionMessage: String? = nil
    @State private var lastActionIsError: Bool = false

    @State private var isApplyingMode: Bool = false
    @State private var isInstallingPack: Bool = false

    @State private var showAllResolutionModes: Bool = false
    @State private var showAllPackModes: Bool = false
    @State private var showAllInstalledModes: Bool = false
    @State private var showAllTechnicalModes: Bool = false

    @State private var customLogicalWidth: String = ""
    @State private var customLogicalHeight: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerButton

            if isExpanded {
                Divider()

                if let lastActionMessage {
                    statusMessage(lastActionMessage, isError: lastActionIsError)
                }

                currentSummarySection

                singleOpenSection(
                    id: .resolution,
                    title: "Resolution",
                    subtitle: "HiDPI modes already available",
                    systemImage: "rectangle.on.rectangle"
                ) {
                    resolutionSection
                }

                singleOpenSection(
                    id: .hidpi,
                    title: "HiDPI Toggle",
                    subtitle: "Quick HiDPI on / off",
                    systemImage: "sparkles"
                ) {
                    hidpiToggleSection
                }

                singleOpenSection(
                    id: .refreshRate,
                    title: "Refresh Rate",
                    subtitle: refreshRateSectionSubtitle(),
                    systemImage: "speedometer"
                ) {
                    refreshRateSection
                }

                singleOpenSection(
                    id: .controls,
                    title: "Controls",
                    subtitle: display.isBuiltIn ? "Brightness and volume" : "Volume and external controls",
                    systemImage: "slider.horizontal.3"
                ) {
                    controlsSection
                }

                singleOpenSection(
                    id: .advanced,
                    title: "Advanced",
                    subtitle: "Custom HiDPI, Retina Pack, installed modes",
                    systemImage: "gearshape"
                ) {
                    advancedSection
                }
            } else {
                collapsedSummary
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear {
            initializeStateIfNeeded()
        }
        .onChange(of: isExpanded) { newValue in
            if !newValue {
                activeSubsection = nil
                lastActionMessage = nil
            }
        }
    }

    private var headerButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(display.isHiDPI ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                        .frame(width: 34, height: 34)

                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name)
                        .font(.headline)

                    Text(display.typeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                modePill(display.modeLabel, isImportant: display.isHiDPI)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var collapsedSummary: some View {
        HStack {
            Text("\(display.logicalWidth) × \(display.logicalHeight)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Framebuffer \(display.framebufferWidth) × \(display.framebufferHeight)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var currentSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(display.logicalWidth) × \(display.logicalHeight)")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Framebuffer \(display.framebufferWidth) × \(display.framebufferHeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    modePill(display.modeLabel, isImportant: display.isHiDPI)

                    Text(refreshRateText(display.refreshRate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if display.isBuiltIn {
                infoText("Built-in display is managed by macOS.")
            } else if display.isHiDPI {
                infoText("HiDPI rendering is active for this display.")
            } else if retinaTargetMode() != nil {
                infoText("A HiDPI mode is already available. Use HiDPI Toggle to switch.")
            } else if isCurrentPackInstalledButNotLoaded() {
                infoText("Retina Pack is installed, but macOS has not loaded the new modes yet.")
            } else {
                infoText("Install a Retina Pack from Advanced to add crisp HiDPI modes for this monitor.")
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let modes = resolutionModes()
            let visibleModes = showAllResolutionModes ? modes : Array(modes.prefix(7))

            if modes.isEmpty {
                infoText("No available modes found.")
            } else {
                ForEach(visibleModes) { mode in
                    modeRow(mode, compact: true)
                }

                if modes.count > 7 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showAllResolutionModes.toggle()
                        }
                    } label: {
                        HStack {
                            Text(showAllResolutionModes ? "Show fewer resolutions" : "+ \(modes.count - 7) more resolutions")
                            Spacer()
                            Image(systemName: showAllResolutionModes ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var hidpiToggleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.isHiDPI ? "HiDPI is on" : "HiDPI is off")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text(quickHiDPISubtitle())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    quickHiDPIAction()
                } label: {
                    Label(quickHiDPIButtonTitle(), systemImage: quickHiDPIButtonIcon())
                }
                .buttonStyle(.borderedProminent)
                .disabled(quickHiDPIButtonDisabled())
            }

            if !display.isBuiltIn && retinaTargetMode() == nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        activeSubsection = .advanced
                    }
                } label: {
                    Label("Open Advanced Setup", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var refreshRateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let modes = refreshRateModesForCurrentResolution()

            if modes.count <= 1 {
                infoText("No refresh-rate alternatives for the current mode.")
            } else {
                HStack {
                    Picker("Refresh Rate", selection: $selectedRefreshModeID) {
                        ForEach(modes) { mode in
                            Text(mode.refreshRateLabel)
                                .tag(mode.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Apply") {
                        applySelectedRefreshMode()
                    }
                    .disabled(selectedRefreshModeID.isEmpty || isApplyingMode)
                }

                infoText("Refresh rate is part of the selected macOS display mode.")
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if display.isBuiltIn {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Brightness", systemImage: "sun.max")
                        Spacer()
                        Text("\(Int(brightness * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)

                    Slider(value: $brightness, in: 0...1)
                        .onChange(of: brightness) { newValue in
                            BuiltInBrightnessManager.shared.setBrightness(Float(newValue))
                        }
                }
            } else {
                infoText("External brightness via DDC/CI comes later.")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Volume", systemImage: "speaker.wave.2")
                    Spacer()
                    Text("\(Int(volume * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Slider(value: $volume, in: 0...1)
                    .onChange(of: volume) { newValue in
                        SystemVolumeManager.shared.setVolume(Float(newValue))
                    }

                Text("Controls the current default macOS output device.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if display.isBuiltIn {
                infoText("Advanced HiDPI packs are only needed for external displays.")
            } else {
                customHiDPIInstallSection
                retinaPackInstallSection
                installedHiDPIResolutionsSection
            }

            Divider()

            technicalInfoSection
            technicalModesSection
        }
    }

    private var customHiDPIInstallSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Custom HiDPI", systemImage: "rectangle.expand.vertical")

            Text("Add one specific “Looks Like” size. This is separate from the recommended Retina Pack.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Width", text: $customLogicalWidth)
                    .textFieldStyle(.roundedBorder)

                Text("×")
                    .foregroundStyle(.secondary)

                TextField("Height", text: $customLogicalHeight)
                    .textFieldStyle(.roundedBorder)
            }

            if let custom = customModePreview() {
                let state = customInstallState(custom)

                statusCard(
                    title: state.title,
                    detail: state.detail,
                    state: state
                )

                VStack(alignment: .leading, spacing: 5) {
                    row("Looks Like", "\(custom.logicalWidth) × \(custom.logicalHeight)")
                    row("Framebuffer", "\(custom.framebufferWidth) × \(custom.framebufferHeight)")
                    row("Render Cost", custom.megapixelLabel)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    installCustomOnly(custom)
                } label: {
                    Label("Install Custom HiDPI", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstallingPack)
            } else {
                statusCard(
                    title: "Custom mode not ready",
                    detail: "Enter a valid size with roughly the same aspect ratio as this display.",
                    state: InstallState(
                        kind: .notInstalled,
                        title: "Custom mode not ready",
                        detail: "Enter a valid size with roughly the same aspect ratio as this display."
                    )
                )
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var retinaPackInstallSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Retina Pack", systemImage: "sparkles")

            if let pack = displayManager.generateRecommendedHiDPIModePack(for: display) {
                let state = retinaPackInstallState(pack)

                statusCard(
                    title: state.title,
                    detail: state.detail,
                    state: state
                )

                packPreview(pack)

                HStack {
                    Button {
                        installPack(pack)
                    } label: {
                        Label(
                            isInstallingPack ? "Installing..." : "Install Retina Pack",
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstallingPack)

                    Button {
                        uninstallPack(pack)
                    } label: {
                        Label("Remove Pack", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isInstallingPack || !isPackFilePresent())
                }

                Text("Applies to this monitor model on this Mac. Native modes load after macOS reloads display metadata.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                infoText("No Retina Pack could be generated for this display.")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func packPreview(_ pack: HiDPIModePack) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let visibleItems = showAllPackModes ? pack.items : Array(pack.items.prefix(5))
            let installedKeys = Set(installedOverrideResolutions().map(\.key))

            ForEach(visibleItems) { item in
                let key = "\(item.framebufferWidth)x\(item.framebufferHeight)"
                let available = isPackItemAvailable(item)
                let installedInOverride = installedKeys.contains(key)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.caption2)
                            .fontWeight(item.recommended ? .semibold : .regular)

                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if item.recommended {
                        smallTag("recommended")
                    }

                    if available {
                        smallTag("already installed")
                    } else if installedInOverride {
                        smallTag("needs restart")
                    } else {
                        smallTag("new")
                    }
                }
            }

            if pack.items.count > 5 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAllPackModes.toggle()
                    }
                } label: {
                    HStack {
                        Text(showAllPackModes ? "Show less" : "+ \(pack.items.count - 5) more")
                        Spacer()
                        Image(systemName: showAllPackModes ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var installedHiDPIResolutionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Installed HiDPI Resolutions", systemImage: "checklist")

            let installed = installedOverrideResolutions()
            let available = installed.filter { $0.isAvailableNow }
            let pending = installed.filter { !$0.isAvailableNow }
            let visibleAvailable = showAllInstalledModes ? available : Array(available.prefix(6))

            if installed.isEmpty {
                infoText("No Display+ override file found for this monitor.")
            } else {
                if !available.isEmpty {
                    Text("Available now")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(visibleAvailable) { item in
                        installedModeRow(item)
                    }

                    if available.count > 6 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showAllInstalledModes.toggle()
                            }
                        } label: {
                            HStack {
                                Text(showAllInstalledModes ? "Show fewer installed modes" : "+ \(available.count - 6) more available")
                                Spacer()
                                Image(systemName: showAllInstalledModes ? "chevron.up" : "chevron.down")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !pending.isEmpty {
                    Text("Pending display reload")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.top, available.isEmpty ? 0 : 6)

                    ForEach(pending) { item in
                        installedModeRow(item)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func installedModeRow(_ item: InstalledHiDPIResolution) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption2)
                    .fontWeight(.semibold)

                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            smallTag(item.isAvailableNow ? "available" : "needs restart")
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var technicalInfoSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Display Identity", systemImage: "number")

            row("Vendor ID", display.vendorIDHex)
            row("Product ID", display.productIDHex)
            row("Serial", display.serialNumberHex)
            row("Active Output", "\(display.activeOutputWidth) × \(display.activeOutputHeight)")
            row("Rotation", "\(Int(display.rotation))°")
        }
    }

    private var technicalModesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("All macOS Modes", systemImage: "list.bullet.rectangle")

            let modes = showAllTechnicalModes ? display.modes : Array(display.modes.prefix(10))

            ForEach(modes) { mode in
                modeRow(mode, compact: false)
            }

            if display.modes.count > 10 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showAllTechnicalModes.toggle()
                    }
                } label: {
                    HStack {
                        Text(showAllTechnicalModes ? "Show fewer modes" : "+ \(display.modes.count - 10) more modes")
                        Spacer()
                        Image(systemName: showAllTechnicalModes ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private func singleOpenSection<Content: View>(
        id: DisplaySubsection,
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isOpen = activeSubsection == id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    activeSubsection = isOpen ? nil : id
                }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isOpen ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                            .frame(width: 28, height: 28)

                        Image(systemName: systemImage)
                            .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(.top, 10)
            }
        }
        .padding(10)
        .background(isOpen ? Color.secondary.opacity(0.09) : Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func modeRow(_ mode: DisplayModeInfo, compact: Bool) -> some View {
        let current = isCurrentMode(mode)

        return Button {
            if current {
                showStatus("This mode is already active.", isError: false)
            } else {
                applyModeAndShowStatus(mode)
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compact ? mode.compactTitle : mode.title)
                        .font(.caption)
                        .fontWeight(current ? .bold : .regular)

                    Text(mode.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if current {
                    modePill("Current", isImportant: true)
                }

                modePill(mode.modeLabel, isImportant: mode.isHiDPI)
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(current ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func initializeStateIfNeeded() {
        if display.isBuiltIn,
           let currentBrightness = BuiltInBrightnessManager.shared.readBrightness() {
            brightness = Double(currentBrightness)
        }

        if let currentVolume = SystemVolumeManager.shared.readVolume() {
            volume = Double(currentVolume)
        }

        if customLogicalWidth.isEmpty {
            customLogicalWidth = "\(display.logicalWidth)"
        }

        if customLogicalHeight.isEmpty {
            customLogicalHeight = "\(display.logicalHeight)"
        }

        let refreshModes = refreshRateModesForCurrentResolution()

        if selectedRefreshModeID.isEmpty {
            let currentRounded = Int(display.refreshRate.rounded())

            if let current = refreshModes.first(where: {
                Int($0.refreshRate.rounded()) == currentRounded
            }) {
                selectedRefreshModeID = current.id
            } else {
                selectedRefreshModeID = refreshModes.first?.id ?? ""
            }
        }
    }

    private func resolutionModes() -> [DisplayModeInfo] {
        let currentArea = display.logicalWidth * display.logicalHeight

        return friendlyAvailableModes().sorted { a, b in
            let aCurrent = isCurrentMode(a)
            let bCurrent = isCurrentMode(b)

            if aCurrent != bCurrent {
                return aCurrent && !bCurrent
            }

            if a.isHiDPI != b.isHiDPI {
                return a.isHiDPI && !b.isHiDPI
            }

            let aDiff = abs((a.logicalWidth * a.logicalHeight) - currentArea)
            let bDiff = abs((b.logicalWidth * b.logicalHeight) - currentArea)

            if aDiff != bDiff {
                return aDiff < bDiff
            }

            return a.logicalWidth < b.logicalWidth
        }
    }

    private func friendlyAvailableModes() -> [DisplayModeInfo] {
        var seen = Set<String>()

        return display.modes.filter { mode in
            let key = [
                "\(mode.logicalWidth)",
                "\(mode.logicalHeight)",
                "\(mode.framebufferWidth)",
                "\(mode.framebufferHeight)"
            ].joined(separator: "-")

            if seen.contains(key) {
                return false
            }

            seen.insert(key)
            return true
        }
    }

    private func refreshRateModesForCurrentResolution() -> [DisplayModeInfo] {
        var seen = Set<Int>()

        return display.modes
            .filter { mode in
                mode.logicalWidth == display.logicalWidth &&
                mode.logicalHeight == display.logicalHeight &&
                mode.framebufferWidth == display.framebufferWidth &&
                mode.framebufferHeight == display.framebufferHeight &&
                mode.refreshRate > 0
            }
            .filter { mode in
                let rounded = Int(mode.refreshRate.rounded())

                if seen.contains(rounded) {
                    return false
                }

                seen.insert(rounded)
                return true
            }
            .sorted {
                $0.refreshRate > $1.refreshRate
            }
    }

    private func refreshRateSectionSubtitle() -> String {
        let modes = refreshRateModesForCurrentResolution()

        if modes.count <= 1 {
            return "No alternatives"
        }

        return "\(modes.count) available"
    }

    private func quickHiDPIButtonTitle() -> String {
        if display.isHiDPI {
            return "Turn Off"
        }

        if retinaTargetMode() != nil {
            return "Turn On"
        }

        return "Set Up"
    }

    private func quickHiDPIButtonIcon() -> String {
        if display.isHiDPI {
            return "minus.magnifyingglass"
        }

        if retinaTargetMode() != nil {
            return "sparkles"
        }

        return "gearshape"
    }

    private func quickHiDPISubtitle() -> String {
        if display.isBuiltIn {
            return "Built-in display scaling is managed by macOS."
        }

        if display.isHiDPI {
            return "Switch back to the closest standard LoDPI mode."
        }

        if let mode = retinaTargetMode() {
            return "Switch to \(mode.logicalWidth) × \(mode.logicalHeight) HiDPI."
        }

        if isCurrentPackInstalledButNotLoaded() {
            return "Retina Pack is installed, but the new modes are not loaded yet."
        }

        return "No HiDPI mode is available yet. Install a Retina Pack in Advanced."
    }

    private func quickHiDPIButtonDisabled() -> Bool {
        if display.isBuiltIn {
            return true
        }

        if display.isHiDPI {
            return standardTargetMode() == nil || isApplyingMode
        }

        if retinaTargetMode() != nil {
            return isApplyingMode
        }

        return false
    }

    private func quickHiDPIAction() {
        if display.isHiDPI {
            guard let mode = standardTargetMode() else {
                showStatus("No standard LoDPI mode was found.", isError: true)
                return
            }

            applyModeAndShowStatus(mode)
            return
        }

        if let mode = retinaTargetMode() {
            applyModeAndShowStatus(mode)
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            activeSubsection = .advanced
        }

        showStatus("Install a Retina Pack from Advanced first, then HiDPI Toggle can switch instantly.", isError: false)
    }

    private func retinaTargetMode() -> DisplayModeInfo? {
        let retinaModes = friendlyAvailableModes().filter { $0.isHiDPI }

        if retinaModes.isEmpty {
            return nil
        }

        if let sameWorkspace = retinaModes.first(where: {
            $0.logicalWidth == display.logicalWidth &&
            $0.logicalHeight == display.logicalHeight
        }) {
            return sameWorkspace
        }

        let currentArea = display.logicalWidth * display.logicalHeight

        return retinaModes.sorted { a, b in
            let aDiff = abs((a.logicalWidth * a.logicalHeight) - currentArea)
            let bDiff = abs((b.logicalWidth * b.logicalHeight) - currentArea)

            if aDiff != bDiff {
                return aDiff < bDiff
            }

            return a.logicalWidth < b.logicalWidth
        }.first
    }

    private func standardTargetMode() -> DisplayModeInfo? {
        let standardModes = friendlyAvailableModes().filter { !$0.isHiDPI }

        if standardModes.isEmpty {
            return nil
        }

        if let sameWorkspace = standardModes.first(where: {
            $0.logicalWidth == display.logicalWidth &&
            $0.logicalHeight == display.logicalHeight
        }) {
            return sameWorkspace
        }

        if let nativeOutput = standardModes.first(where: {
            $0.logicalWidth == display.activeOutputWidth &&
            $0.logicalHeight == display.activeOutputHeight
        }) {
            return nativeOutput
        }

        let currentArea = display.logicalWidth * display.logicalHeight

        return standardModes.sorted { a, b in
            let aDiff = abs((a.logicalWidth * a.logicalHeight) - currentArea)
            let bDiff = abs((b.logicalWidth * b.logicalHeight) - currentArea)

            if aDiff != bDiff {
                return aDiff < bDiff
            }

            return a.logicalWidth < b.logicalWidth
        }.first
    }

    private func isCurrentPackInstalledButNotLoaded() -> Bool {
        guard let pack = displayManager.generateRecommendedHiDPIModePack(for: display) else {
            return false
        }

        let state = retinaPackInstallState(pack)
        return state.kind == .needsRestart || state.kind == .partiallyLoaded
    }

    private func customModePreview() -> HiDPIModePackItem? {
        guard let logicalWidth = Int(customLogicalWidth.trimmingCharacters(in: .whitespacesAndNewlines)),
              let logicalHeight = Int(customLogicalHeight.trimmingCharacters(in: .whitespacesAndNewlines)),
              logicalWidth >= 1000,
              logicalHeight >= 600 else {
            return nil
        }

        let displayAspect = Double(display.activeOutputWidth) / Double(max(display.activeOutputHeight, 1))
        let requestedAspect = Double(logicalWidth) / Double(max(logicalHeight, 1))
        let aspectDifference = abs(displayAspect - requestedAspect)

        guard aspectDifference <= 0.10 else {
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

        return HiDPIModePackItem(
            id: "custom-\(logicalWidth)x\(logicalHeight)-\(framebufferWidth)x\(framebufferHeight)",
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,
            framebufferWidth: framebufferWidth,
            framebufferHeight: framebufferHeight,
            framebufferMegapixels: megapixels,
            alreadyAvailable: alreadyAvailable,
            recommended: true
        )
    }

    private func retinaPackInstallState(_ pack: HiDPIModePack) -> InstallState {
        guard isPackFilePresent() else {
            return InstallState(
                kind: .notInstalled,
                title: "Retina Pack not installed",
                detail: "Install the recommended HiDPI pack for this monitor."
            )
        }

        let installedKeys = Set(installedOverrideResolutions().map(\.key))
        let packKeys = Set(pack.items.map { "\($0.framebufferWidth)x\($0.framebufferHeight)" })

        let containedCount = packKeys.filter { installedKeys.contains($0) }.count
        let availableCount = pack.items.filter { isPackItemAvailable($0) }.count

        if containedCount == 0 {
            return InstallState(
                kind: .notInstalled,
                title: "Retina Pack not installed",
                detail: "An override exists, but it does not contain this recommended pack."
            )
        }

        if availableCount == pack.items.count {
            return InstallState(
                kind: .installed,
                title: "Retina Pack installed",
                detail: "All recommended HiDPI modes are available now."
            )
        }

        if availableCount > 0 {
            return InstallState(
                kind: .partiallyLoaded,
                title: "Retina Pack partially loaded",
                detail: "\(availableCount) of \(pack.items.count) modes are available. The rest may need a display reload or restart."
            )
        }

        return InstallState(
            kind: .needsRestart,
            title: "Retina Pack installed — needs restart",
            detail: "The override file is installed, but macOS has not loaded the new HiDPI modes yet."
        )
    }

    private func customInstallState(_ custom: HiDPIModePackItem) -> InstallState {
        if isPackItemAvailable(custom) {
            return InstallState(
                kind: .alreadyAvailable,
                title: "Custom HiDPI available",
                detail: "This custom mode is already visible to macOS."
            )
        }

        let key = "\(custom.framebufferWidth)x\(custom.framebufferHeight)"
        let installedKeys = Set(installedOverrideResolutions().map(\.key))

        if installedKeys.contains(key) {
            return InstallState(
                kind: .needsRestart,
                title: "Custom HiDPI installed — needs restart",
                detail: "The custom mode is in the override file, but macOS has not loaded it yet."
            )
        }

        return InstallState(
            kind: .notInstalled,
            title: "Custom HiDPI not installed",
            detail: "Install this custom mode separately from the recommended Retina Pack."
        )
    }

    private func installCustomOnly(_ customItem: HiDPIModePackItem) {
        let existingInstalledItems = installedOverrideResolutions().map { installed in
            HiDPIModePackItem(
                id: "installed-\(installed.framebufferWidth)x\(installed.framebufferHeight)",
                logicalWidth: installed.logicalWidth,
                logicalHeight: installed.logicalHeight,
                framebufferWidth: installed.framebufferWidth,
                framebufferHeight: installed.framebufferHeight,
                framebufferMegapixels: Double(installed.framebufferWidth * installed.framebufferHeight) / 1_000_000.0,
                alreadyAvailable: installed.isAvailableNow,
                recommended: false
            )
        }

        var items = existingInstalledItems

        let customExists = items.contains { item in
            item.framebufferWidth == customItem.framebufferWidth &&
            item.framebufferHeight == customItem.framebufferHeight
        }

        if !customExists {
            items.append(customItem)
        }

        if items.isEmpty {
            items = [customItem]
        }

        let pack = HiDPIModePack(
            id: "\(display.vendorID)-\(display.productID)-custom-only",
            displayID: display.id,
            displayName: display.name,
            vendorID: display.vendorID,
            productID: display.productID,
            serialNumber: display.serialNumber,
            items: items.sorted { $0.logicalWidth < $1.logicalWidth }
        )

        installPack(pack)
    }

    private func applySelectedRefreshMode() {
        guard let mode = refreshRateModesForCurrentResolution()
            .first(where: { $0.id == selectedRefreshModeID }) else {
            showStatus("No matching refresh-rate mode found.", isError: true)
            return
        }

        applyModeAndShowStatus(mode)
    }

    private func applyModeAndShowStatus(_ mode: DisplayModeInfo) {
        isApplyingMode = true

        let error = displayManager.applyMode(mode)

        if error == .success {
            showStatus("Applied \(mode.compactTitle) · \(mode.modeLabel).", isError: false)
        } else {
            showStatus("macOS rejected this mode: \(error).", isError: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isApplyingMode = false
        }
    }

    private func installPack(_ pack: HiDPIModePack) {
        isInstallingPack = true
        showStatus("macOS will ask for your admin password.", isError: false)

        DispatchQueue.global(qos: .userInitiated).async {
            let result = NativeOverrideAutoInstaller.install(display: display, pack: pack)

            DispatchQueue.main.async {
                isInstallingPack = false
                showStatus(
                    result.success ? result.message : "Install failed: \(result.message)",
                    isError: !result.success
                )
            }
        }
    }

    private func uninstallPack(_ pack: HiDPIModePack) {
        isInstallingPack = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = NativeOverrideAutoInstaller.uninstall(display: display, pack: pack)

            DispatchQueue.main.async {
                isInstallingPack = false
                showStatus(
                    result.success ? result.message : "Uninstall failed: \(result.message)",
                    isError: !result.success
                )
            }
        }
    }

    private func isPackItemAvailable(_ item: HiDPIModePackItem) -> Bool {
        display.modes.contains { mode in
            mode.isHiDPI &&
            mode.logicalWidth == item.logicalWidth &&
            mode.logicalHeight == item.logicalHeight &&
            mode.framebufferWidth == item.framebufferWidth &&
            mode.framebufferHeight == item.framebufferHeight
        }
    }

    private func isPackFilePresent() -> Bool {
        guard let path = displayOverridePath() else {
            return false
        }

        return FileManager.default.fileExists(atPath: path)
    }

    private func displayOverridePath() -> String? {
        guard let pack = displayManager.generateRecommendedHiDPIModePack(for: display) else {
            return nil
        }

        let preview = NativeOverridePlistPreviewExporter.makePreview(
            display: display,
            pack: pack
        )

        return preview.targetInstallPath
    }

    private func installedOverrideResolutions() -> [InstalledHiDPIResolution] {
        guard let path = displayOverridePath(),
              FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any],
              let values = plist["scale-resolutions"] as? [Data] else {
            return []
        }

        var seen = Set<String>()

        let resolutions: [InstalledHiDPIResolution] = values.compactMap { value in
            guard let decoded = decodeScaleResolution(value) else {
                return nil
            }

            let key = "\(decoded.width)x\(decoded.height)"

            guard !seen.contains(key) else {
                return nil
            }

            seen.insert(key)

            let logicalWidth = decoded.width / 2
            let logicalHeight = decoded.height / 2

            let available = display.modes.contains { mode in
                mode.isHiDPI &&
                mode.logicalWidth == logicalWidth &&
                mode.logicalHeight == logicalHeight &&
                mode.framebufferWidth == decoded.width &&
                mode.framebufferHeight == decoded.height
            }

            return InstalledHiDPIResolution(
                framebufferWidth: decoded.width,
                framebufferHeight: decoded.height,
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight,
                isAvailableNow: available
            )
        }

        return resolutions.sorted { a, b in
            if a.isAvailableNow != b.isAvailableNow {
                return a.isAvailableNow && !b.isAvailableNow
            }

            return a.logicalWidth < b.logicalWidth
        }
    }

    private func decodeScaleResolution(_ data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)

        guard bytes.count >= 8 else {
            return nil
        }

        let width =
            (UInt32(bytes[0]) << 24) |
            (UInt32(bytes[1]) << 16) |
            (UInt32(bytes[2]) << 8) |
            UInt32(bytes[3])

        let height =
            (UInt32(bytes[4]) << 24) |
            (UInt32(bytes[5]) << 16) |
            (UInt32(bytes[6]) << 8) |
            UInt32(bytes[7])

        guard width > 0, height > 0 else {
            return nil
        }

        return (Int(width), Int(height))
    }

    private func showStatus(_ message: String, isError: Bool) {
        lastActionMessage = message
        lastActionIsError = isError
    }

    private func statusMessage(_ message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .foregroundStyle(isError ? .orange : .secondary)

            Text(message)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                lastActionMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .padding(8)
        .background(isError ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusCard(title: String, detail: String, state: InstallState) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: stateIcon(state))
                .foregroundStyle(stateColor(state))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            statePill(state)
        }
        .padding(8)
        .background(stateBackground(state))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stateIcon(_ state: InstallState) -> String {
        switch state.kind {
        case .installed, .alreadyAvailable:
            return "checkmark.circle.fill"
        case .needsRestart, .partiallyLoaded:
            return "arrow.clockwise.circle.fill"
        case .notInstalled:
            return "circle"
        }
    }

    private func stateColor(_ state: InstallState) -> Color {
        if state.isPositive {
            return .green
        }

        if state.isWarning {
            return .orange
        }

        return .secondary
    }

    private func stateBackground(_ state: InstallState) -> Color {
        if state.isPositive {
            return Color.green.opacity(0.12)
        }

        if state.isWarning {
            return Color.orange.opacity(0.14)
        }

        return Color.secondary.opacity(0.08)
    }

    private func statePill(_ state: InstallState) -> some View {
        let text: String

        switch state.kind {
        case .installed:
            text = "Installed"
        case .alreadyAvailable:
            text = "Available"
        case .needsRestart:
            text = "Needs restart"
        case .partiallyLoaded:
            text = "Partial"
        case .notInstalled:
            text = "Not installed"
        }

        return Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(stateColor(state).opacity(0.16))
            .clipShape(Capsule())
    }

    private func isCurrentMode(_ mode: DisplayModeInfo) -> Bool {
        let sameLogical = mode.logicalWidth == display.logicalWidth &&
                          mode.logicalHeight == display.logicalHeight

        let sameFramebuffer = mode.framebufferWidth == display.framebufferWidth &&
                              mode.framebufferHeight == display.framebufferHeight

        let sameRefresh = Int(mode.refreshRate.rounded()) == Int(display.refreshRate.rounded())

        return sameLogical && sameFramebuffer && sameRefresh
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func refreshRateText(_ refreshRate: Double) -> String {
        if refreshRate <= 0 {
            return "Default"
        }

        return "\(Int(refreshRate.rounded())) Hz"
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .fontWeight(.semibold)
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func modePill(_ text: String, isImportant: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(isImportant ? .semibold : .regular)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(isImportant ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func smallTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.10))
            .clipShape(Capsule())
    }
}
