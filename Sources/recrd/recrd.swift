import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ServiceManagement
import Sparkle
import SwiftUI

private enum CaptureKind {
    case recording
    case screenshot
}

private enum RecrdTuning {
    enum Keys {
        static let selectionDimOpacity = "recrd.tuning.selectionDimOpacity"
        static let releaseGlowDuration = "recrd.tuning.releaseGlowDuration"
        static let releaseGlowLineWidth = "recrd.tuning.releaseGlowLineWidth"
        static let releaseGlowOpacity = "recrd.tuning.releaseGlowOpacity"
        static let releaseGlowShadowRadius = "recrd.tuning.releaseGlowShadowRadius"
        static let startAtLogin = "recrd.app.startAtLogin"
        static let showMenuBarIcon = "recrd.app.showMenuBarIcon"
    }

    static let defaultSelectionDimOpacity = 0.10
    static let defaultReleaseGlowDuration = 1.0
    static let defaultReleaseGlowLineWidth = 4.0
    static let defaultReleaseGlowOpacity = 0.95
    static let defaultReleaseGlowShadowRadius = 10.0

    static let selectionDimOpacityRange = 0.0 ... 0.4
    static let releaseGlowDurationRange = 0.2 ... 2.0
    static let releaseGlowLineWidthRange = 1.0 ... 10.0
    static let releaseGlowOpacityRange = 0.2 ... 1.0
    static let releaseGlowShadowRadiusRange = 0.0 ... 20.0

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.selectionDimOpacity: defaultSelectionDimOpacity,
            Keys.releaseGlowDuration: defaultReleaseGlowDuration,
            Keys.releaseGlowLineWidth: defaultReleaseGlowLineWidth,
            Keys.releaseGlowOpacity: defaultReleaseGlowOpacity,
            Keys.releaseGlowShadowRadius: defaultReleaseGlowShadowRadius,
            Keys.startAtLogin: false,
            Keys.showMenuBarIcon: false,
        ])
    }

    static var selectionDimOpacity: Double {
        clamped(UserDefaults.standard.double(forKey: Keys.selectionDimOpacity), in: selectionDimOpacityRange)
    }

    static var releaseGlowDuration: Double {
        clamped(UserDefaults.standard.double(forKey: Keys.releaseGlowDuration), in: releaseGlowDurationRange)
    }

    private static func clamped(_ value: Double, in range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private weak var recorder: ScreenRecorder?

    func setEnabled(_ enabled: Bool, recorder: ScreenRecorder) {
        self.recorder = recorder
        if enabled {
            installIfNeeded()
        } else {
            remove()
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "recrd") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "recrd"
            }
            button.toolTip = "recrd"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open recrd", action: #selector(openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Start / Stop Recording", action: #selector(toggleRecording), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Screenshot (Select Area)", action: #selector(screenshotSelection), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Screenshot (Full Screen)", action: #selector(screenshotFullscreen), keyEquivalent: "f"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Folder", action: #selector(openFolder), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Quit recrd", action: #selector(quitApp), keyEquivalent: "q"))
        for item in menu.items where item.action != nil {
            item.target = self
        }

        item.menu = menu
        statusItem = item
    }

    private func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func toggleRecording() {
        guard let recorder else {
            return
        }
        if recorder.isRecording {
            recorder.stopRecordingFromUI()
        } else if !recorder.isSelectingArea {
            recorder.startRecordingWithSelection()
        }
        openMainWindow()
    }

    @objc private func screenshotSelection() {
        guard let recorder else {
            return
        }
        recorder.captureScreenshotWithSelection()
        openMainWindow()
    }

    @objc private func screenshotFullscreen() {
        guard let recorder else {
            return
        }
        recorder.captureScreenshotFullScreen()
        recorder.flashGreenGlow()
        openMainWindow()
    }

    @objc private func openFolder() {
        recorder?.openRecordingsFolder()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class AppRuntimeController: ObservableObject {
    private let recorder: ScreenRecorder
    private let menuBarController = MenuBarController()

    init(recorder: ScreenRecorder) {
        self.recorder = recorder
        applyStartAtLogin(UserDefaults.standard.bool(forKey: RecrdTuning.Keys.startAtLogin))
        applyMenuBarIcon(UserDefaults.standard.bool(forKey: RecrdTuning.Keys.showMenuBarIcon))
    }

    var supportsStartAtLogin: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    func applyStartAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch-at-login update failed: \(error.localizedDescription)")
        }
    }

    func applyMenuBarIcon(_ enabled: Bool) {
        menuBarController.setEnabled(enabled, recorder: recorder)
    }
}

@MainActor
final class AppUpdateController: NSObject, ObservableObject {
    private let updaterController: SPUStandardUpdaterController?

    override init() {
        if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           !feed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
        super.init()
    }

    var isEnabled: Bool {
        updaterController != nil
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

@MainActor
final class ScreenRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isSelectingArea = false
    @Published var statusMessage = "Ready"
    @Published var lastCaptureURL: URL?
    @Published var showCopiedToast = false
    @Published var copiedToastOpacity: Double = 0
    @Published var showSelectionReleaseGlow = false

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var screenInput: AVCaptureScreenInput?
    private let recordingsFolder: URL
    private let regionSelector = RegionSelectionCoordinator()
    private let retentionDays = 14
    private let cleanupInterval: TimeInterval = 6 * 60 * 60
    private var toastTask: Task<Void, Never>?
    private var releaseGlowTask: Task<Void, Never>?
    private var cleanupTimer: Timer?
    private let permissionHelpMessage = "Enable 'recrd' in Screen Recording settings, then quit and reopen recrd."
    private var suppressNextSelectionCancelledMessage = false

    private enum SelectionIntent {
        case recording
        case screenshot
    }

    override init() {
        RecrdTuning.registerDefaults()
        recordingsFolder = ScreenRecorder.desktopRecrdFolderURL()
        super.init()
        if !ensureOutputFolderExists() {
            statusMessage = "Could not create output folder at Desktop/recrd."
        }
        cleanupExpiredFiles()
        startRetentionCleanupTimer()
    }

    func stopRecordingFromUI() {
        stopRecording()
    }

    func startRecordingWithSelection() {
        guard !isRecording, !isSelectingArea else {
            return
        }
        beginRegionSelection(for: .recording)
    }

    func startRecordingFullScreen() {
        guard !isRecording, !isSelectingArea else {
            return
        }
        guard ensureScreenCapturePermission() else {
            return
        }
        guard ensureOutputFolderExists() else {
            return
        }
        guard let screen = preferredCaptureScreen() else {
            statusMessage = "Could not access an active display."
            return
        }
        startRecording(selectedRect: screen.frame, on: screen)
    }

    func openRecordingsFolder() {
        NSWorkspace.shared.open(recordingsFolder)
    }

    func openScreenRecordingSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    func openAppSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func revealLastCapture() {
        guard let url = lastCaptureURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func canDeleteLastCapture() -> Bool {
        guard let url = lastCaptureURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func deleteLastCapture() {
        guard let url = lastCaptureURL else {
            statusMessage = "No recent capture to delete."
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            lastCaptureURL = nil
            statusMessage = "Last capture was already removed."
            return
        }

        do {
            try FileManager.default.removeItem(at: url)
            lastCaptureURL = nil
            statusMessage = "Deleted: \(url.lastPathComponent)"
        } catch {
            statusMessage = "Could not delete file: \(error.localizedDescription)"
        }
    }

    func flashGreenGlow() {
        showReleaseGlow()
    }

    func cancelSelectionMode() {
        guard isSelectingArea else {
            statusMessage = "Ready"
            return
        }
        suppressNextSelectionCancelledMessage = true
        regionSelector.cancel()
    }

    func captureScreenshotWithSelection() {
        guard !isRecording, !isSelectingArea else {
            return
        }
        beginRegionSelection(for: .screenshot)
    }

    func captureScreenshotFullScreen() {
        guard !isRecording else {
            statusMessage = "Stop recording before taking a screenshot."
            return
        }
        guard !isSelectingArea else {
            return
        }

        guard ensureScreenCapturePermission() else {
            return
        }

        guard ensureOutputFolderExists() else {
            return
        }

        guard let screen = preferredCaptureScreen() else {
            statusMessage = "Could not access an active display."
            return
        }

        captureScreenshot(selectedRect: screen.frame, on: screen)
    }

    private func captureScreenshot(selectedRect: CGRect, on screen: NSScreen) {
        guard let displayID = displayID(for: screen) else {
            statusMessage = "Could not determine display ID."
            return
        }

        let clampedSelection = selectedRect.intersection(screen.frame)
        guard !clampedSelection.isNull, clampedSelection.width >= 2, clampedSelection.height >= 2 else {
            statusMessage = "Selected area is too small."
            return
        }

        let cropRect = screenshotCropRectInDisplayPixels(from: clampedSelection, on: screen, displayID: displayID)
        guard !cropRect.isNull, !cropRect.isEmpty else {
            statusMessage = "Could not map selected area to display coordinates."
            return
        }

        guard let image = CGDisplayCreateImage(displayID, rect: cropRect) else {
            statusMessage = "Could not capture the selected area."
            return
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            statusMessage = "Could not encode screenshot."
            return
        }

        let destinationURL = nextCaptureURL(for: .screenshot)
        do {
            try pngData.write(to: destinationURL, options: .atomic)
            finalizeSavedCapture(at: destinationURL, kind: .screenshot)
        } catch {
            statusMessage = "Could not save screenshot: \(error.localizedDescription)"
        }
    }

    func recordingsPathDisplay() -> String {
        recordingsFolder.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func beginRegionSelection(for intent: SelectionIntent) {
        guard ensureScreenCapturePermission() else {
            return
        }

        guard ensureOutputFolderExists() else {
            return
        }

        guard let screen = preferredCaptureScreen() else {
            statusMessage = "Could not access an active display."
            return
        }

        isSelectingArea = true
        statusMessage = intent == .recording
            ? "Click, hold, and drag to select recording area."
            : "Click, hold, and drag to select screenshot area."

        regionSelector.present(
            on: screen,
            dimOpacity: RecrdTuning.selectionDimOpacity,
            onMouseReleased: { [weak self] in
                self?.showReleaseGlow()
            },
            completion: { [weak self] selectedRect in
                guard let self else {
                    return
                }

                self.isSelectingArea = false
                guard let selectedRect else {
                    if self.suppressNextSelectionCancelledMessage {
                        self.suppressNextSelectionCancelledMessage = false
                        self.statusMessage = "Ready"
                        return
                    }
                    self.statusMessage = "Selection cancelled."
                    return
                }
                self.suppressNextSelectionCancelledMessage = false
                switch intent {
                case .recording:
                    self.startRecording(selectedRect: selectedRect, on: screen)
                case .screenshot:
                    self.captureScreenshot(selectedRect: selectedRect, on: screen)
                }
            }
        )
    }

    private func startRecording(selectedRect: CGRect, on screen: NSScreen) {
        guard !isRecording else {
            return
        }

        let clampedSelection = selectedRect.intersection(screen.frame)
        guard !clampedSelection.isNull, clampedSelection.width >= 4, clampedSelection.height >= 4 else {
            statusMessage = "Selected area is too small."
            return
        }

        guard let displayID = displayID(for: screen) else {
            statusMessage = "Could not determine display ID."
            return
        }

        guard let input = AVCaptureScreenInput(displayID: displayID) else {
            statusMessage = "Could not access selected display."
            return
        }

        input.capturesCursor = true
        input.capturesMouseClicks = true
        input.minFrameDuration = CMTime(value: 1, timescale: 30)
        input.scaleFactor = max(1.0, screen.backingScaleFactor)

        let cropRect = recordingCropRectInScreenPoints(from: clampedSelection, on: screen)
        guard !cropRect.isNull, !cropRect.isEmpty else {
            statusMessage = "Could not map selected area to screen coordinates."
            return
        }
        input.cropRect = cropRect

        session.beginConfiguration()
        for existingInput in session.inputs {
            session.removeInput(existingInput)
        }
        for existingOutput in session.outputs {
            session.removeOutput(existingOutput)
        }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            statusMessage = "Could not configure display input."
            return
        }
        session.addInput(input)

        guard session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            statusMessage = "Could not configure movie output."
            return
        }
        session.addOutput(movieOutput)
        session.commitConfiguration()

        screenInput = input
        let destinationURL = nextCaptureURL(for: .recording)
        session.startRunning()
        movieOutput.startRecording(to: destinationURL, recordingDelegate: self)

        isRecording = true
        statusMessage = "Recording..."
    }

    private func stopRecording() {
        guard isRecording else {
            return
        }
        statusMessage = "Stopping..."
        movieOutput.stopRecording()
    }

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        _ = CGRequestScreenCaptureAccess()
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        statusMessage = permissionHelpMessage
        return false
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(displayNumber.uint32Value)
    }

    private func recordingCropRectInScreenPoints(from selectedRect: CGRect, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        guard screenFrame.width > 0, screenFrame.height > 0 else {
            return .null
        }

        let clampedRect = selectedRect.intersection(screenFrame)
        guard !clampedRect.isNull, !clampedRect.isEmpty else {
            return .null
        }

        // AVCaptureScreenInput.cropRect expects display points in top-left-origin space.
        let localX = clampedRect.minX - screenFrame.minX
        let localMaxY = clampedRect.maxY - screenFrame.minY
        let localYFromTop = screenFrame.height - localMaxY
        var rect = CGRect(
            x: floor(localX),
            y: floor(localYFromTop),
            width: ceil(clampedRect.width),
            height: ceil(clampedRect.height)
        )
        if rect.width < 1 { rect.size.width = 1 }
        if rect.height < 1 { rect.size.height = 1 }
        return rect.intersection(CGRect(origin: .zero, size: screenFrame.size))
    }

    private func screenshotCropRectInDisplayPixels(from selectedRect: CGRect,
                                                   on screen: NSScreen,
                                                   displayID: CGDirectDisplayID) -> CGRect {
        let screenFrame = screen.frame
        let displayWidth = CGFloat(CGDisplayPixelsWide(displayID))
        let displayHeight = CGFloat(CGDisplayPixelsHigh(displayID))
        guard screenFrame.width > 0, screenFrame.height > 0, displayWidth > 0, displayHeight > 0 else {
            return .null
        }

        let clampedRect = selectedRect.intersection(screenFrame)
        guard !clampedRect.isNull, !clampedRect.isEmpty else {
            return .null
        }

        // Convert points in NSScreen space to display pixels using actual display dimensions.
        let scaleX = displayWidth / screenFrame.width
        let scaleY = displayHeight / screenFrame.height

        let localMinX = clampedRect.minX - screenFrame.minX
        let localMaxY = clampedRect.maxY - screenFrame.minY

        let x = localMinX * scaleX
        let yFromTop = (screenFrame.height - localMaxY) * scaleY
        let width = clampedRect.width * scaleX
        let height = clampedRect.height * scaleY

        var rect = CGRect(
            x: floor(x),
            y: floor(yFromTop),
            width: ceil(width),
            height: ceil(height)
        )

        if rect.width < 1 { rect.size.width = 1 }
        if rect.height < 1 { rect.size.height = 1 }

        return rect.intersection(CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight))
    }

    private func preferredCaptureScreen() -> NSScreen? {
        let mousePoint = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mousePoint) }) {
            return mouseScreen
        }
        if let keyWindowScreen = NSApp.keyWindow?.screen {
            return keyWindowScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func nextCaptureURL(for kind: CaptureKind) -> URL {
        let (prefix, ext) = filenameScheme(for: kind)
        let nextIndex = nextIndexForFiles(prefix: prefix, ext: ext)
        return recordingsFolder.appendingPathComponent("\(prefix)_\(nextIndex).\(ext)")
    }

    private func filenameScheme(for kind: CaptureKind) -> (prefix: String, ext: String) {
        switch kind {
        case .recording:
            return ("vid", "mov")
        case .screenshot:
            return ("scr", "png")
        }
    }

    private func nextIndexForFiles(prefix: String, ext: String) -> Int {
        let pattern = #"^\#(prefix)_(\d+)\.\#(ext)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return 0
        }

        let urls = (try? FileManager.default.contentsOfDirectory(at: recordingsFolder, includingPropertiesForKeys: nil)) ?? []
        var maxIndex = -1

        for url in urls {
            let name = url.lastPathComponent
            let range = NSRange(location: 0, length: name.utf16.count)
            guard let match = regex.firstMatch(in: name, options: [], range: range),
                  match.numberOfRanges == 2,
                  let idxRange = Range(match.range(at: 1), in: name),
                  let idx = Int(name[idxRange]) else {
                continue
            }
            if idx > maxIndex {
                maxIndex = idx
            }
        }

        return maxIndex + 1
    }

    private func ensureOutputFolderExists() -> Bool {
        do {
            try FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
            return true
        } catch {
            statusMessage = "Could not create output folder: \(error.localizedDescription)"
            return false
        }
    }

    private static func desktopRecrdFolderURL() -> URL {
        if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            return desktopURL.appendingPathComponent("recrd", isDirectory: true)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("recrd", isDirectory: true)
    }

    private func copyCaptureToPasteboard(_ url: URL, kind: CaptureKind) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.fileURL, .string], owner: nil)

        var didCopy = pasteboard.writeObjects([url as NSURL])
        if !didCopy {
            didCopy = pasteboard.setString(url.absoluteString, forType: .fileURL)
        }
        _ = pasteboard.setString(url.path, forType: .string)

        if kind == .screenshot, let image = NSImage(contentsOf: url) {
            _ = pasteboard.writeObjects([image])
        }

        if didCopy {
            showCopiedIndicator()
        }
        return didCopy
    }

    private func finalizeSavedCapture(at url: URL, kind: CaptureKind) {
        lastCaptureURL = url
        let copied = copyCaptureToPasteboard(url, kind: kind)
        cleanupExpiredFiles()
        statusMessage = copied
            ? "Saved: \(url.lastPathComponent)"
            : "Saved (copy failed): \(url.lastPathComponent)"
        flashGreenGlow()
    }

    private func waitForCaptureFileToStabilize(at url: URL) async -> Bool {
        let timeout = Date().addingTimeInterval(3.0)
        var lastSize: UInt64 = 0
        var stableCount = 0

        while Date() < timeout {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let sizeValue = attributes[.size] as? NSNumber {
                let size = sizeValue.uint64Value
                if size > 0 {
                    if size == lastSize {
                        stableCount += 1
                    } else {
                        stableCount = 0
                        lastSize = size
                    }
                    if stableCount >= 2 {
                        return true
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    private func showCopiedIndicator() {
        toastTask?.cancel()
        showCopiedToast = true
        copiedToastOpacity = 0

        withAnimation(.easeInOut(duration: 3.0)) {
            copiedToastOpacity = 1
        }

        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.easeInOut(duration: 3.0)) {
                copiedToastOpacity = 0
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            showCopiedToast = false
        }
    }

    private func showReleaseGlow() {
        releaseGlowTask?.cancel()
        withAnimation(.easeInOut(duration: 0.08)) {
            showSelectionReleaseGlow = true
        }

        releaseGlowTask = Task { @MainActor in
            let nanos = UInt64(RecrdTuning.releaseGlowDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) {
                showSelectionReleaseGlow = false
            }
        }
    }

    private func startRetentionCleanupTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            self?.cleanupExpiredFiles()
        }
    }

    private func cleanupExpiredFiles() {
        let cutoffDate = Date().addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey, .contentModificationDateKey]

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: recordingsFolder,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            for fileURL in fileURLs {
                let values = try fileURL.resourceValues(forKeys: resourceKeys)
                guard values.isRegularFile == true else {
                    continue
                }

                let fileDate = values.creationDate ?? values.contentModificationDate
                guard let fileDate, fileDate < cutoffDate else {
                    continue
                }

                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("Retention cleanup failed: \(error.localizedDescription)")
        }
    }

    private func cleanupSession() {
        if session.isRunning {
            session.stopRunning()
        }

        if let input = screenInput {
            session.removeInput(input)
            screenInput = nil
        }
    }
}

extension ScreenRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didStartRecordingTo fileURL: URL,
                                from connections: [AVCaptureConnection]) {}

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: (any Error)?) {
        Task { @MainActor in
            isRecording = false
            cleanupSession()

            if let error {
                statusMessage = "Recording failed: \(error.localizedDescription)"
                return
            }

            guard await waitForCaptureFileToStabilize(at: outputFileURL) else {
                statusMessage = "Saved file is not fully available yet."
                return
            }

            finalizeSavedCapture(at: outputFileURL, kind: .recording)
        }
    }
}

@MainActor
private final class RegionSelectionCoordinator: NSObject {
    private var window: NSWindow?
    private var completion: ((CGRect?) -> Void)?

    func present(on screen: NSScreen,
                 dimOpacity: Double,
                 onMouseReleased: @escaping () -> Void,
                 completion: @escaping (CGRect?) -> Void) {
        dismiss()
        self.completion = completion

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false

        let selectionView = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        selectionView.minimumAcceptedEventTimestamp = ProcessInfo.processInfo.systemUptime + 0.02
        selectionView.dimOpacity = CGFloat(min(1.0, max(0.0, dimOpacity)))
        selectionView.onMouseReleased = onMouseReleased
        selectionView.onComplete = { [weak self] localRect in
            guard let self else {
                return
            }
            let screenRect = localRect.map { rect in
                rect.offsetBy(dx: screen.frame.origin.x, dy: screen.frame.origin.y)
            }
            self.finish(with: screenRect)
        }
        selectionView.onCancel = { [weak self] in
            self?.finish(with: nil)
        }

        window.contentView = selectionView
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(selectionView)
    }

    private func finish(with rect: CGRect?) {
        let callback = completion
        dismiss()
        callback?(rect)
    }

    func cancel() {
        finish(with: nil)
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
        completion = nil
    }
}

@MainActor
private final class RegionSelectionView: NSView {
    var onComplete: ((CGRect?) -> Void)?
    var onCancel: (() -> Void)?
    var onMouseReleased: (() -> Void)?
    var minimumAcceptedEventTimestamp: TimeInterval = 0
    var dimOpacity: CGFloat = 0.10

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.timestamp >= minimumAcceptedEventTimestamp else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else {
            return
        }
        let current = convert(event.locationInWindow, from: nil)
        dragCurrent = current
        if !didDrag {
            let dx = current.x - start.x
            let dy = current.y - start.y
            didDrag = hypot(dx, dy) >= 3
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard event.timestamp >= minimumAcceptedEventTimestamp else {
            return
        }

        guard let start = dragStart else {
            return
        }
        onMouseReleased?()

        let end = convert(event.locationInWindow, from: nil)
        let rect = normalizedRect(from: start, to: end)
        if !didDrag || rect.width < 8 || rect.height < 8 {
            resetSelectionState()
            return
        }
        resetSelectionState()
        onComplete?(rect)
    }

    override func rightMouseDown(with event: NSEvent) {
        resetSelectionState()
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            resetSelectionState()
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let start = dragStart else {
            return
        }

        NSColor.black.withAlphaComponent(dimOpacity).setFill()
        bounds.fill()

        guard let current = dragCurrent else {
            return
        }

        let rect = normalizedRect(from: start, to: current)
        NSColor.clear.setFill()
        rect.fill(using: .clear)

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 2
        border.stroke()
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }

    private func resetSelectionState() {
        dragStart = nil
        dragCurrent = nil
        didDrag = false
        needsDisplay = true
    }
}

private enum FloatingToolbarItem: Int, CaseIterable, Hashable {
    case still
    case vid
    case open
    case delete

    var title: String {
        switch self {
        case .vid:
            return "vid"
        case .still:
            return "still"
        case .open:
            return "open"
        case .delete:
            return "delete"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var recorder: ScreenRecorder
    @State private var hasAppliedDefaultWindowSize = false
    @State private var pendingRecordingSingleClickTask: Task<Void, Never>?
    @State private var pendingScreenshotSingleClickTask: Task<Void, Never>?
    @State private var activeToolbarItem: FloatingToolbarItem = .vid
    @State private var buttonScales: [FloatingToolbarItem: CGFloat] = [.vid: 1.0, .still: 1.0, .open: 1.0, .delete: 1.0]
    @State private var buttonResetTasks: [FloatingToolbarItem: Task<Void, Never>] = [:]
    @State private var localKeyEventMonitor: Any?
    @State private var globalKeyEventMonitor: Any?
    @State private var recentSpacePressTimes: [TimeInterval] = []
    @State private var pendingSpaceShortcutTask: Task<Void, Never>?
    private let defaultWindowSize = NSSize(width: 448, height: 288)
    private let tripleSpaceWindow: TimeInterval = 0.9
    private let delayedSpaceShortcutFireDelay: TimeInterval = 0.33
    @AppStorage(RecrdTuning.Keys.releaseGlowLineWidth) private var releaseGlowLineWidth = RecrdTuning.defaultReleaseGlowLineWidth
    @AppStorage(RecrdTuning.Keys.releaseGlowOpacity) private var releaseGlowOpacity = RecrdTuning.defaultReleaseGlowOpacity
    @AppStorage(RecrdTuning.Keys.releaseGlowShadowRadius) private var releaseGlowShadowRadius = RecrdTuning.defaultReleaseGlowShadowRadius

    var body: some View {
        ZStack(alignment: .top) {
            AppBackdropView()
                .opacity(0.8)

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Group {
                        if recorder.showCopiedToast {
                            Text("saved and copied")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .italic()
                                .foregroundStyle(.white.opacity(0.9))
                                .opacity(recorder.copiedToastOpacity)
                        } else {
                            Text(recorder.statusMessage)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .lineLimit(3)
                }
                .padding(.top, 10)

                Spacer()
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Spacer(minLength: 0)
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(hex: 0xE8AF48, opacity: 0.08),
                            Color(hex: 0xE8AF48, opacity: 0.025),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 180
                    )
                    .blendMode(.screen)
                    .frame(width: 420, height: 180)

                    FloatingCaptureToolbar(
                        activeItem: activeToolbarItem,
                        buttonScales: buttonScales,
                        isRecording: recorder.isRecording,
                        isSelectingArea: recorder.isSelectingArea,
                        canDeleteLastCapture: recorder.canDeleteLastCapture(),
                        onTap: triggerToolbarAction
                    )
                }

                VStack(spacing: 4) {
                    Text("Space Bar Shortcuts")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("2x - Screenshot Area")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                    Text("3x - Video Record Area")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                    Text("4x - Screenshot Screen")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)

            if shouldShowSelectionPendingGlow {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        Color.orange.opacity(0.95),
                        lineWidth: max(releaseGlowLineWidth, 4)
                    )
                    .shadow(
                        color: Color.orange.opacity(0.85),
                        radius: max(releaseGlowShadowRadius, 12)
                    )
                    .padding(4)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if recorder.isRecording || recorder.showSelectionReleaseGlow {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        Color.green.opacity(recorder.isRecording ? 1.0 : releaseGlowOpacity),
                        lineWidth: recorder.isRecording ? max(releaseGlowLineWidth, 6) : releaseGlowLineWidth
                    )
                    .shadow(
                        color: Color.green.opacity(recorder.isRecording ? 1.0 : releaseGlowOpacity),
                        radius: recorder.isRecording ? max(releaseGlowShadowRadius, 14) : releaseGlowShadowRadius
                    )
                    .padding(4)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: defaultWindowSize.width, minHeight: defaultWindowSize.height)
        .background(
            WindowAccessor { window in
                window.isOpaque = false
                window.backgroundColor = .clear
                guard !hasAppliedDefaultWindowSize else {
                    return
                }
                window.setContentSize(defaultWindowSize)
                hasAppliedDefaultWindowSize = true
            }
        )
        .animation(.easeInOut(duration: 0.2), value: recorder.showCopiedToast)
        .animation(.easeInOut(duration: 0.2), value: recorder.showSelectionReleaseGlow)
        .overlay(alignment: .bottomLeading) {
            HuskyReferenceView()
                .padding(.leading, 10)
                .padding(.bottom, 10)
        }
        .onAppear {
            installKeyMonitorsIfNeeded()
        }
        .onDisappear {
            pendingRecordingSingleClickTask?.cancel()
            pendingRecordingSingleClickTask = nil
            pendingScreenshotSingleClickTask?.cancel()
            pendingScreenshotSingleClickTask = nil
            for task in buttonResetTasks.values {
                task.cancel()
            }
            buttonResetTasks.removeAll()
            removeKeyMonitors()
            recentSpacePressTimes.removeAll()
            pendingSpaceShortcutTask?.cancel()
            pendingSpaceShortcutTask = nil
        }
    }

    private func triggerToolbarAction(_ item: FloatingToolbarItem) {
        activeToolbarItem = item
        bounceButton(item)

        switch item {
        case .vid:
            handleRecordingButtonClick()
        case .still:
            handleScreenshotButtonClick()
        case .open:
            recorder.openRecordingsFolder()
        case .delete:
            recorder.deleteLastCapture()
        }
    }

    private func bounceButton(_ item: FloatingToolbarItem) {
        buttonResetTasks[item]?.cancel()
        withAnimation(.interpolatingSpring(stiffness: 430, damping: 17)) {
            buttonScales[item] = 1.25
        }

        let resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 95_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.interpolatingSpring(stiffness: 330, damping: 19)) {
                buttonScales[item] = 1.0
            }
        }
        buttonResetTasks[item] = resetTask
    }

    private func handleRecordingButtonClick() {
        if recorder.isRecording {
            pendingRecordingSingleClickTask?.cancel()
            pendingRecordingSingleClickTask = nil
            recorder.stopRecordingFromUI()
            return
        }

        guard !recorder.isSelectingArea else {
            return
        }

        if let pendingTask = pendingRecordingSingleClickTask {
            pendingTask.cancel()
            pendingRecordingSingleClickTask = nil
            recorder.startRecordingFullScreen()
            return
        }

        pendingRecordingSingleClickTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: doubleClickWindowNs)
            guard !Task.isCancelled else {
                return
            }
            pendingRecordingSingleClickTask = nil
            recorder.startRecordingWithSelection()
        }
    }

    private func handleScreenshotButtonClick() {
        guard !recorder.isRecording, !recorder.isSelectingArea else {
            return
        }

        if let pendingTask = pendingScreenshotSingleClickTask {
            pendingTask.cancel()
            pendingScreenshotSingleClickTask = nil
            recorder.captureScreenshotFullScreen()
            return
        }

        pendingScreenshotSingleClickTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: doubleClickWindowNs)
            guard !Task.isCancelled else {
                return
            }
            pendingScreenshotSingleClickTask = nil
            recorder.captureScreenshotWithSelection()
        }
    }

    private var shouldShowSelectionPendingGlow: Bool {
        if recorder.isRecording {
            return false
        }
        return pendingRecordingSingleClickTask != nil || pendingScreenshotSingleClickTask != nil || recorder.isSelectingArea
    }

    private var doubleClickWindowNs: UInt64 {
        let seconds = max(0.2, NSEvent.doubleClickInterval)
        return UInt64(seconds * 1_000_000_000)
    }

    private func installKeyMonitorsIfNeeded() {
        if localKeyEventMonitor == nil {
            localKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53, cancelPendingCaptureFlowIfNeeded() {
                    return nil
                }

                guard event.keyCode == 49, !event.isARepeat else {
                    return event
                }
                let handledImmediately = registerSpacePress()
                return handledImmediately ? nil : event
            }
        }

        if globalKeyEventMonitor == nil {
            globalKeyEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 49, !event.isARepeat else {
                    return
                }
                Task { @MainActor in
                    _ = registerSpacePress()
                }
            }
        }
    }

    @discardableResult
    private func registerSpacePress() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        recentSpacePressTimes.append(now)
        recentSpacePressTimes = recentSpacePressTimes.filter { now - $0 <= tripleSpaceWindow }

        pendingSpaceShortcutTask?.cancel()
        pendingSpaceShortcutTask = nil

        if recentSpacePressTimes.count >= 4 {
            recentSpacePressTimes.removeAll()
            handleQuadrupleSpaceShortcut()
            return true
        }

        if recentSpacePressTimes.count == 2 || recentSpacePressTimes.count == 3 {
            pendingSpaceShortcutTask = Task { @MainActor in
                let nanos = UInt64(delayedSpaceShortcutFireDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else {
                    return
                }

                let now = ProcessInfo.processInfo.systemUptime
                recentSpacePressTimes = recentSpacePressTimes.filter { now - $0 <= tripleSpaceWindow }
                let count = recentSpacePressTimes.count
                recentSpacePressTimes.removeAll()

                if count >= 4 {
                    handleQuadrupleSpaceShortcut()
                } else if count == 3 {
                    handleTripleSpaceShortcut()
                } else if count == 2 {
                    handleDoubleSpaceShortcut()
                }
            }
        }

        return false
    }

    private func removeKeyMonitors() {
        if let monitor = localKeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyEventMonitor = nil
        }
        if let monitor = globalKeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyEventMonitor = nil
        }
        pendingSpaceShortcutTask?.cancel()
        pendingSpaceShortcutTask = nil
    }

    private func handleDoubleSpaceShortcut() {
        activeToolbarItem = .still
        bounceButton(.still)

        guard !recorder.isRecording, !recorder.isSelectingArea else {
            return
        }

        pendingScreenshotSingleClickTask?.cancel()
        pendingScreenshotSingleClickTask = nil
        recorder.captureScreenshotWithSelection()
    }

    private func handleTripleSpaceShortcut() {
        activeToolbarItem = .vid
        bounceButton(.vid)

        if recorder.isRecording {
            pendingRecordingSingleClickTask?.cancel()
            pendingRecordingSingleClickTask = nil
            recorder.stopRecordingFromUI()
            return
        }

        guard !recorder.isSelectingArea else {
            return
        }

        pendingRecordingSingleClickTask?.cancel()
        pendingRecordingSingleClickTask = nil
        recorder.startRecordingWithSelection()
    }

    private func handleQuadrupleSpaceShortcut() {
        activeToolbarItem = .still
        bounceButton(.still)

        guard !recorder.isRecording, !recorder.isSelectingArea else {
            return
        }

        pendingScreenshotSingleClickTask?.cancel()
        pendingScreenshotSingleClickTask = nil
        recorder.captureScreenshotFullScreen()
        recorder.flashGreenGlow()
    }

    @discardableResult
    private func cancelPendingCaptureFlowIfNeeded() -> Bool {
        let hadPending = pendingRecordingSingleClickTask != nil || pendingScreenshotSingleClickTask != nil

        pendingRecordingSingleClickTask?.cancel()
        pendingRecordingSingleClickTask = nil
        pendingScreenshotSingleClickTask?.cancel()
        pendingScreenshotSingleClickTask = nil
        pendingSpaceShortcutTask?.cancel()
        pendingSpaceShortcutTask = nil
        recentSpacePressTimes.removeAll()

        if recorder.isSelectingArea {
            recorder.cancelSelectionMode()
            return true
        }

        if hadPending {
            recorder.statusMessage = "Ready"
            return true
        }

        return false
    }
}

private struct FloatingCaptureToolbar: View {
    let activeItem: FloatingToolbarItem
    let buttonScales: [FloatingToolbarItem: CGFloat]
    let isRecording: Bool
    let isSelectingArea: Bool
    let canDeleteLastCapture: Bool
    let onTap: (FloatingToolbarItem) -> Void

    private let buttonWidth: CGFloat = 92
    private let buttonHeight: CGFloat = 52
    private let dividerWidth: CGFloat = 1
    private let horizontalPadding: CGFloat = 10
    private let verticalPadding: CGFloat = 8
    private let cornerRadius: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.5))
            FilmGrainOverlay(opacity: 0.16, density: 1.0)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
            RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                .inset(by: 1)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)

            HStack(spacing: 0) {
                toolbarButton(for: .still)
                divider
                toolbarButton(for: .vid)
                divider
                toolbarButton(for: .open)
                divider
                toolbarButton(for: .delete)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .frame(width: toolbarWidth, height: toolbarHeight)
        .overlay(alignment: .leading) {
            GoldenIndicatorRing()
                .frame(width: buttonWidth - 6, height: buttonHeight - 6)
                .offset(x: indicatorOffsetX)
                .animation(.timingCurve(0.34, 1.2, 0.64, 1, duration: 0.45), value: activeItem)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.5), radius: 24, y: 12)
    }

    private var toolbarWidth: CGFloat {
        horizontalPadding * 2 + buttonWidth * 4 + dividerWidth * 3
    }

    private var toolbarHeight: CGFloat {
        verticalPadding * 2 + buttonHeight
    }

    private var indicatorOffsetX: CGFloat {
        horizontalPadding + 3 + CGFloat(activeItem.rawValue) * (buttonWidth + dividerWidth)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: dividerWidth, height: 30)
    }

    @ViewBuilder
    private func toolbarButton(for item: FloatingToolbarItem) -> some View {
        let inactive = isInactive(item)
        Button {
            guard !inactive else {
                return
            }
            onTap(item)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: iconName(for: item))
                    .font(.system(size: 16, weight: .light))
                    .imageScale(.medium)
                    .foregroundStyle(.white.opacity(inactive ? 0.70 : 0.84))
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(inactive ? 0.68 : 0.76))
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(buttonScales[item] ?? 1.0)
        }
        .buttonStyle(ToolbarNoDimButtonStyle())
    }

    private func isInactive(_ item: FloatingToolbarItem) -> Bool {
        switch item {
        case .vid:
            return isSelectingArea
        case .still:
            return isRecording || isSelectingArea
        case .open:
            return false
        case .delete:
            return !canDeleteLastCapture
        }
    }

    private func iconName(for item: FloatingToolbarItem) -> String {
        switch item {
        case .vid:
            return isRecording ? "stop.fill" : "video"
        case .still:
            return "camera"
        case .open:
            return "folder"
        case .delete:
            return "trash"
        }
    }
}

private struct ToolbarNoDimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(1)
            .brightness(0)
    }
}

private struct GoldenIndicatorRing: View {
    @State private var ringRotation = 0.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xE8AF48, opacity: 0.95), lineWidth: 2)
                .blur(radius: 8)
                .opacity(0.15)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(stops: Self.gradientStops),
                            center: .center,
                            startAngle: .degrees(ringRotation),
                            endAngle: .degrees(ringRotation + 360)
                        ),
                        lineWidth: 2
                    )
            }
        }
        .onAppear {
            ringRotation = 0
            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    private static let gradientStops: [Gradient.Stop] = [
        .init(color: Color(hex: 0x533517), location: 0.000),
        .init(color: Color(hex: 0x6B441D), location: 0.070),
        .init(color: Color(hex: 0xC49746), location: 0.165),
        .init(color: Color(hex: 0xFEEAA5), location: 0.255),
        .init(color: Color(hex: 0xC49746), location: 0.325),
        .init(color: Color(hex: 0x5C3B18), location: 0.345),
        .init(color: Color(hex: 0x8FC4FF, opacity: 0.36), location: 0.360),
        .init(color: Color(hex: 0x5C3B18), location: 0.375),
        .init(color: .white, location: 0.385),
        .init(color: .white, location: 0.415),
        .init(color: Color(hex: 0xFFC0CB, opacity: 0.34), location: 0.430),
        .init(color: Color(hex: 0x533517), location: 0.500),
        .init(color: Color(hex: 0x533517), location: 0.500),
        .init(color: Color(hex: 0x6B441D), location: 0.570),
        .init(color: Color(hex: 0xC49746), location: 0.665),
        .init(color: Color(hex: 0xFEEAA5), location: 0.755),
        .init(color: Color(hex: 0xC49746), location: 0.825),
        .init(color: Color(hex: 0x5C3B18), location: 0.845),
        .init(color: Color(hex: 0x8FC4FF, opacity: 0.36), location: 0.860),
        .init(color: Color(hex: 0x5C3B18), location: 0.875),
        .init(color: .white, location: 0.885),
        .init(color: .white, location: 0.915),
        .init(color: Color(hex: 0xFFC0CB, opacity: 0.34), location: 0.930),
        .init(color: Color(hex: 0x533517), location: 1.000),
    ]
}

private struct AppBackdropView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x151A1B),
                    Color(hex: 0x1A2021),
                    Color(hex: 0x14191A),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            SubtleGoldStripedBackdrop()

            RadialGradient(
                colors: [
                    Color(hex: 0xC49746, opacity: 0.045),
                    Color(hex: 0x0C0D10, opacity: 0.012),
                    .clear,
                ],
                center: .center,
                startRadius: 10,
                endRadius: 460
            )

            FilmGrainOverlay(opacity: 0.06, density: 0.7)
        }
        .ignoresSafeArea()
    }
}

private struct SubtleGoldStripedBackdrop: View {
    var body: some View {
        Canvas { context, size in
            // Sampled from reference frame: dark band ~#1B1F20, light band ~#242A2A.
            let cycleHeight: CGFloat = 84
            let lightBandHeight: CGFloat = 42
            let lightBand = Color(hex: 0x242A2A, opacity: 0.92)
            let darkBand = Color(hex: 0x1B1F20, opacity: 0.94)
            let goldTintLine = Color(hex: 0xC49746, opacity: 0.038)
            let coolEdgeLine = Color(hex: 0x2A3133, opacity: 0.38)

            var y: CGFloat = 0
            while y < size.height + cycleHeight {
                let lightRect = CGRect(x: 0, y: y, width: size.width, height: lightBandHeight)
                let darkRect = CGRect(x: 0, y: y + lightBandHeight, width: size.width, height: cycleHeight - lightBandHeight)
                context.fill(Path(lightRect), with: .color(lightBand))
                context.fill(Path(darkRect), with: .color(darkBand))

                // Thin separators to keep a slight metallic tint without looking gold.
                let boundaryY = y + lightBandHeight - 1
                context.fill(Path(CGRect(x: 0, y: boundaryY, width: size.width, height: 1)), with: .color(goldTintLine))
                context.fill(Path(CGRect(x: 0, y: boundaryY + 1, width: size.width, height: 1)), with: .color(coolEdgeLine))

                y += cycleHeight
            }
        }
        .blendMode(.normal)
        .allowsHitTesting(false)
    }
}

private struct FilmGrainOverlay: View {
    var opacity: Double = 0.10
    var density: CGFloat = 1.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 10.0)) { timeline in
            Canvas { context, size in
                let area = max(size.width * size.height, 1)
                let count = Int(max(160, area / (44.0 / max(density, 0.1))))
                let tick = timeline.date.timeIntervalSinceReferenceDate * 30

                for idx in 0..<count {
                    let x = fractionalNoise(Double(idx) * 1.71 + tick * 0.91) * size.width
                    let y = fractionalNoise(Double(idx) * 2.33 + tick * 1.13) * size.height
                    let alpha = 0.01 + fractionalNoise(Double(idx) * 3.07 + tick * 0.57) * 0.07
                    let tone = 0.82 + fractionalNoise(Double(idx) * 4.41 + tick * 0.27) * 0.18
                    let pixelRect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                    context.fill(Path(pixelRect), with: .color(Color(white: tone, opacity: alpha)))
                }
            }
        }
        .blendMode(.overlay)
        .opacity(opacity)
        .allowsHitTesting(false)
    }

    private func fractionalNoise(_ seed: Double) -> CGFloat {
        let value = sin(seed * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct HuskyReferenceView: View {
    @State private var wiggleAngle: Double = 0
    @State private var wiggleTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: "husky-reference-clean", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 62, height: 96)
                    .shadow(color: Color.black.opacity(0.35), radius: 4, y: 2)
                    .rotationEffect(.degrees(wiggleAngle), anchor: .bottom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        DogTapAudioPlayer.shared.play()
                        startWiggle()
                    }
            }
        }
    }

    private func startWiggle() {
        wiggleTask?.cancel()
        wiggleAngle = 0

        withAnimation(.easeInOut(duration: 0.09).repeatCount(5, autoreverses: true)) {
            wiggleAngle = 5
        }

        wiggleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeOut(duration: 0.12)) {
                wiggleAngle = 0
            }
        }
    }
}

@MainActor
private final class DogTapAudioPlayer {
    static let shared = DogTapAudioPlayer()

    private var player: AVAudioPlayer?

    private init() {}

    func play() {
        guard let url = Bundle.module.url(forResource: "dog-press", withExtension: "mp3") else {
            return
        }

        do {
            if player?.url != url {
                player = try AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            }
            player?.currentTime = 0
            player?.play()
        } catch {
            print("Dog tap audio failed: \(error.localizedDescription)")
        }
    }
}

struct RecrdSettingsView: View {
    @EnvironmentObject private var appRuntime: AppRuntimeController
    @AppStorage(RecrdTuning.Keys.selectionDimOpacity) private var selectionDimOpacity = RecrdTuning.defaultSelectionDimOpacity
    @AppStorage(RecrdTuning.Keys.releaseGlowDuration) private var releaseGlowDuration = RecrdTuning.defaultReleaseGlowDuration
    @AppStorage(RecrdTuning.Keys.releaseGlowLineWidth) private var releaseGlowLineWidth = RecrdTuning.defaultReleaseGlowLineWidth
    @AppStorage(RecrdTuning.Keys.releaseGlowOpacity) private var releaseGlowOpacity = RecrdTuning.defaultReleaseGlowOpacity
    @AppStorage(RecrdTuning.Keys.releaseGlowShadowRadius) private var releaseGlowShadowRadius = RecrdTuning.defaultReleaseGlowShadowRadius
    @AppStorage(RecrdTuning.Keys.startAtLogin) private var startAtLogin = false
    @AppStorage(RecrdTuning.Keys.showMenuBarIcon) private var showMenuBarIcon = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Capture Tuning")
                .font(.headline)

            Toggle("Start on computer login", isOn: $startAtLogin)
                .toggleStyle(.switch)
            if !appRuntime.supportsStartAtLogin {
                Text("Requires macOS 13+.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                .toggleStyle(.switch)

            Divider()

            settingRow("Outside dim", value: "\(Int(selectionDimOpacity * 100))%")
            Slider(value: $selectionDimOpacity, in: RecrdTuning.selectionDimOpacityRange, step: 0.01)

            settingRow("Glow duration", value: String(format: "%.1fs", releaseGlowDuration))
            Slider(value: $releaseGlowDuration, in: RecrdTuning.releaseGlowDurationRange, step: 0.1)

            settingRow("Glow thickness", value: String(format: "%.1f", releaseGlowLineWidth))
            Slider(value: $releaseGlowLineWidth, in: RecrdTuning.releaseGlowLineWidthRange, step: 0.5)

            settingRow("Glow strength", value: "\(Int(releaseGlowOpacity * 100))%")
            Slider(value: $releaseGlowOpacity, in: RecrdTuning.releaseGlowOpacityRange, step: 0.05)

            settingRow("Glow blur", value: String(format: "%.1f", releaseGlowShadowRadius))
            Slider(value: $releaseGlowShadowRadius, in: RecrdTuning.releaseGlowShadowRadiusRange, step: 0.5)

            HStack {
                Spacer()
                Button("Reset Defaults") {
                    selectionDimOpacity = RecrdTuning.defaultSelectionDimOpacity
                    releaseGlowDuration = RecrdTuning.defaultReleaseGlowDuration
                    releaseGlowLineWidth = RecrdTuning.defaultReleaseGlowLineWidth
                    releaseGlowOpacity = RecrdTuning.defaultReleaseGlowOpacity
                    releaseGlowShadowRadius = RecrdTuning.defaultReleaseGlowShadowRadius
                }
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(width: 340)
        .onAppear {
            appRuntime.applyStartAtLogin(startAtLogin)
            appRuntime.applyMenuBarIcon(showMenuBarIcon)
        }
        .onChange(of: startAtLogin) { newValue in
            appRuntime.applyStartAtLogin(newValue)
        }
        .onChange(of: showMenuBarIcon) { newValue in
            appRuntime.applyMenuBarIcon(newValue)
        }
    }

    @ViewBuilder
    private func settingRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else {
                return
            }
            onResolve(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else {
                return
            }
            onResolve(window)
        }
    }
}

@main
struct RecrdApp: App {
    @StateObject private var recorder: ScreenRecorder
    @StateObject private var appRuntime: AppRuntimeController
    @StateObject private var appUpdateController: AppUpdateController

    init() {
        RecrdTuning.registerDefaults()
        let recorder = ScreenRecorder()
        _recorder = StateObject(wrappedValue: recorder)
        _appRuntime = StateObject(wrappedValue: AppRuntimeController(recorder: recorder))
        _appUpdateController = StateObject(wrappedValue: AppUpdateController())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
                .environmentObject(appRuntime)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appUpdateController.checkForUpdates()
                }
                .disabled(!appUpdateController.isEnabled)
            }
        }
        Settings {
            RecrdSettingsView()
                .environmentObject(appRuntime)
        }
    }
}
