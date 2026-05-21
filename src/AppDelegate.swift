import Cocoa
import SwiftUI
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate {
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?

    let downloader = ModelDownloader()
    var audioRecorder: AVAudioRecorder?
    var audioPlayer: AVAudioPlayer?
    var wasFnPressed = false
    var isRecording = false
    var isProcessing = false

    // Transparent overlay window for voice indicator
    var overlayWindow: OverlayWindow?
    let audioInputState = AudioInputState()
    var meteringTimer: Timer?

    private let minimumRecordingDuration: TimeInterval = 0.35
    private let silencePeakThresholdDBFS = -50.0
    private let silenceRMSThresholdDBFS = -55.0

    // Temporary audio file path
    var tempAudioURL: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("izi_input_temp.wav")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestMicrophonePermission()
        checkAccessibilityPermission() // Prompts macOS to request Accessibility if missing or invalid
        setupGlobalKeyListener()

        // Initialize voice overlay window
        let overlayView = OverlayView(audioInputState: self.audioInputState)
        let hostingView = NSHostingView(rootView: overlayView)
        overlayWindow = OverlayWindow(contentView: hostingView)

        // Open settings automatically on first launch if model is not downloaded
        if !downloader.isModelDownloaded {
            showSettings()
        }
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Izi Input")
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func statusItemClicked(_ sender: Any?) {
        // Show menu on click
        statusItem?.button?.performClick(nil)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                downloader: self.downloader,
                audioInputState: self.audioInputState,
                onPlayPause: { [weak self] in
                    self?.playLastAudio()
                }
            )
            let hostingController = NSHostingController(rootView: view)

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Izi Input Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 480, height: 680))
            window.center()
            window.isReleasedWhenClosed = false

            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Microphone & Key Listening

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                print("[Izi Input] Microphone access denied.")
            }
        }
    }

    func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        print("[Izi Input] Accessibility permission trusted status: \(accessEnabled)")
    }

    func setupGlobalKeyListener() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }

            let isFnPressed = event.modifierFlags.contains(.function)
            if isFnPressed != self.wasFnPressed {
                self.wasFnPressed = isFnPressed
                if isFnPressed {
                    self.startRecording()
                } else {
                    self.stopRecording()
                }
            }
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording && !isProcessing else { return }

        // Verify model is downloaded
        guard downloader.isModelDownloaded else {
            showNotification(title: "Model Required", text: "Please download the Whisper model in Settings first.")
            return
        }

        guard hasMicrophonePermission() else { return }

        let recordingRequestedAt = Date()

        print("[Izi Input] Initializing audio recording...")
        let inputDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown"
        print("[Izi Input] Default audio input device: \(inputDeviceName)")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            let recorder = try AVAudioRecorder(url: tempAudioURL, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw NSError(
                    domain: "IziInput",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder refused to start recording."]
                )
            }

            audioRecorder = recorder
            isRecording = true
            audioInputState.isRecording = true
            audioInputState.isAudioReady = true
            updateStatusIcon()

            overlayWindow?.alphaValue = 0
            overlayWindow?.updatePosition()
            overlayWindow?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                overlayWindow?.animator().alphaValue = 1.0
            }

            meteringTimer?.invalidate()
            meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, let recorder = self.audioRecorder else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let normalized = CGFloat(max(0.0, (power + 50.0) / 50.0))
                self.audioInputState.amplitude = normalized
            }

            let startupMilliseconds = Int(Date().timeIntervalSince(recordingRequestedAt) * 1000)
            print("[Izi Input] Recording started successfully. Startup latency: \(startupMilliseconds) ms.")
        } catch {
            print("[Izi Input] Failed to start recording: \(error.localizedDescription)")
            isRecording = false
            audioRecorder = nil
            audioInputState.isRecording = false
            audioInputState.isAudioReady = false
            audioInputState.amplitude = 0.0
            updateStatusIcon()
            overlayWindow?.orderOut(nil)
            showNotification(title: "Recording Failed", text: error.localizedDescription)
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        // Stop metering timer
        meteringTimer?.invalidate()
        meteringTimer = nil
        audioInputState.isRecording = false
        audioInputState.isAudioReady = false // Reset to false
        audioInputState.amplitude = 0.0

        let hasRecorder = audioRecorder != nil
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        // Fade-out the visual overlay
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.overlayWindow?.animator().alphaValue = 0
        }) {
            self.overlayWindow?.orderOut(nil)
        }

        // Only run transcription if we actually recorded something (audioRecorder was initialized)
        if hasRecorder {
            guard validateLastRecordingForTranscription() else { return }

            isProcessing = true
            updateStatusIcon()
            print("[Izi Input] Recording stopped. Starting transcription...")

            // Process on background thread to keep UI interactive
            DispatchQueue.global(qos: .userInitiated).async {
                self.runWhisperTranslation()
            }
        } else {
            print("[Izi Input] Recording cancelled or too short; skipping transcription.")
            updateStatusIcon()
        }
    }

    func hasMicrophonePermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self = self else { return }
                if !granted {
                    DispatchQueue.main.async {
                        self.showNotification(title: "Microphone Required", text: "Allow microphone access in macOS Settings and try again.")
                    }
                }
            }
            showNotification(title: "Microphone Permission", text: "Allow microphone access, then hold Fn again.")
            return false
        case .denied, .restricted:
            showNotification(title: "Microphone Blocked", text: "Enable microphone access for IziInput in macOS Settings.")
            print("[Izi Input] Microphone access is denied or restricted.")
            return false
        @unknown default:
            showNotification(title: "Microphone Error", text: "Could not verify microphone permission.")
            print("[Izi Input] Unknown microphone authorization status.")
            return false
        }
    }

    func validateLastRecordingForTranscription() -> Bool {
        guard FileManager.default.fileExists(atPath: tempAudioURL.path) else {
            print("[Izi Input] Recording file was not created.")
            finishRecordingWithoutTranscription(
                title: "No Recording",
                text: "No audio file was created. Check microphone permission and try again."
            )
            return false
        }

        guard let analysis = analyzeRecording(at: tempAudioURL) else {
            print("[Izi Input] Could not analyze recording; continuing with transcription.")
            return true
        }

        print(
            "[Izi Input] Recording analysis: duration=\(String(format: "%.2f", analysis.duration))s, " +
            "peak=\(String(format: "%.1f", analysis.peakDBFS)) dBFS, " +
            "rms=\(String(format: "%.1f", analysis.rmsDBFS)) dBFS"
        )

        if analysis.duration < minimumRecordingDuration {
            finishRecordingWithoutTranscription(
                title: "Recording Too Short",
                text: "Hold Fn a little longer before speaking."
            )
            return false
        }

        if analysis.peakDBFS < silencePeakThresholdDBFS && analysis.rmsDBFS < silenceRMSThresholdDBFS {
            finishRecordingWithoutTranscription(
                title: "No Microphone Signal",
                text: "The recording was silent. Check macOS Sound Input, input volume, or muted headset mic."
            )
            return false
        }

        return true
    }

    func finishRecordingWithoutTranscription(title: String, text: String) {
        isProcessing = false
        audioInputState.lastRussianText = ""
        audioInputState.lastEnglishText = ""
        audioInputState.hasLastAudio = FileManager.default.fileExists(atPath: tempAudioURL.path)
        updateStatusIcon()
        showNotification(title: title, text: text)
        print("[Izi Input] Skipping transcription: \(title) - \(text)")
    }

    struct RecordingAnalysis {
        let duration: TimeInterval
        let peakDBFS: Double
        let rmsDBFS: Double
    }

    func analyzeRecording(at url: URL) -> RecordingAnalysis? {
        do {
            let file = try AVAudioFile(forReading: url)
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0 else { return nil }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return nil }
            try file.read(into: buffer)

            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            guard frameLength > 0, channelCount > 0 else { return nil }

            var peak = 0.0
            var sumSquares = 0.0
            var sampleCount = 0

            if let channelData = buffer.floatChannelData {
                for channel in 0..<channelCount {
                    let samples = channelData[channel]
                    for frame in 0..<frameLength {
                        let sample = Double(samples[frame])
                        let absoluteSample = abs(sample)
                        peak = max(peak, absoluteSample)
                        sumSquares += sample * sample
                        sampleCount += 1
                    }
                }
            } else if let channelData = buffer.int16ChannelData {
                for channel in 0..<channelCount {
                    let samples = channelData[channel]
                    for frame in 0..<frameLength {
                        let sample = Double(samples[frame]) / Double(Int16.max)
                        let absoluteSample = abs(sample)
                        peak = max(peak, absoluteSample)
                        sumSquares += sample * sample
                        sampleCount += 1
                    }
                }
            } else {
                return nil
            }

            guard sampleCount > 0 else { return nil }

            let rms = sqrt(sumSquares / Double(sampleCount))
            let sampleRate = file.fileFormat.sampleRate
            let duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0

            return RecordingAnalysis(
                duration: duration,
                peakDBFS: dbFS(peak),
                rmsDBFS: dbFS(rms)
            )
        } catch {
            print("[Izi Input] Failed to analyze recording: \(error.localizedDescription)")
            return nil
        }
    }

    func dbFS(_ value: Double) -> Double {
        guard value > 0 else { return -160.0 }
        return 20.0 * log10(value)
    }

    // MARK: - Whisper Integration

    func runWhisperTranslation() {
        let modelPath = downloader.destinationURL.path
        let audioPath = tempAudioURL.path

        // Look for whisper-cli in app bundle first, fallback to developer path
        var whisperExecutablePath = ""
        if let bundledPath = Bundle.main.path(forResource: "whisper-cli", ofType: nil) {
            whisperExecutablePath = bundledPath
        } else {
            whisperExecutablePath = "/Users/dushes/projects/izi-input/whisper.cpp/build/bin/whisper-cli"
        }

        guard FileManager.default.fileExists(atPath: whisperExecutablePath) else {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.updateStatusIcon()
                self.showNotification(title: "Whisper CLI Not Found", text: "Could not find whisper-cli. Please compile the project using build.sh.")
            }
            return
        }

        var russianText = ""
        var englishText = ""

        // 1. Run Russian transcription
        do {
            let ruProcess = Process()
            ruProcess.executableURL = URL(fileURLWithPath: whisperExecutablePath)
            ruProcess.arguments = [
                "-m", modelPath,
                "-f", audioPath,
                "-l", "ru",
                "--no-timestamps",
                "-sns"
            ]
            let ruPipe = Pipe()
            ruProcess.standardOutput = ruPipe
            ruProcess.standardError = Pipe()

            try ruProcess.run()
            ruProcess.waitUntilExit()

            let data = ruPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                russianText = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            print("[Izi Input] Russian transcription output: \(russianText)")
        } catch {
            print("[Izi Input] Error running Whisper Russian transcription: \(error.localizedDescription)")
        }

        // 2. Run English translation
        do {
            let enProcess = Process()
            enProcess.executableURL = URL(fileURLWithPath: whisperExecutablePath)
            enProcess.arguments = [
                "-m", modelPath,
                "-f", audioPath,
                "-tr",
                "--no-timestamps",
                "-sns"
            ]
            let enPipe = Pipe()
            enProcess.standardOutput = enPipe
            enProcess.standardError = Pipe()

            try enProcess.run()
            enProcess.waitUntilExit()

            let data = enPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                englishText = output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            print("[Izi Input] English translation output: \(englishText)")
        } catch {
            print("[Izi Input] Error running Whisper English translation: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            self.isProcessing = false
            self.updateStatusIcon()

            self.audioInputState.lastRussianText = russianText
            self.audioInputState.lastEnglishText = englishText
            self.audioInputState.hasLastAudio = FileManager.default.fileExists(atPath: self.tempAudioURL.path)

            if !englishText.isEmpty {
                self.pasteText(englishText)
            }
        }
    }

    // MARK: - Keystroke Simulation (Paste)

    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[Izi Input] Clipboard set to: \"\(text)\"")

        guard hasAccessibilityPermissionForPaste() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.postPasteShortcut()
        }
    }

    func hasAccessibilityPermissionForPaste() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        guard accessEnabled else {
            showNotification(
                title: "Accessibility Required",
                text: "Text is in the clipboard. Enable Accessibility for IziInput to paste automatically."
            )
            print("[Izi Input] Automatic paste skipped: Accessibility permission is not trusted.")
            return false
        }

        return true
    }

    func postPasteShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        let loc = CGEventTapLocation.cgSessionEventTap
        cmdDown?.post(tap: loc)
        vDown?.post(tap: loc)
        vUp?.post(tap: loc)
        cmdUp?.post(tap: loc)
        print("[Izi Input] Simulated Cmd+V keystroke sent.")
    }

    // MARK: - UI Helpers

    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        if isRecording {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording...")
            button.contentTintColor = NSColor.systemRed
        } else if isProcessing {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Processing...")
            button.contentTintColor = NSColor.systemPurple
        } else {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Izi Input")
            button.contentTintColor = nil
        }
    }

    func showNotification(title: String, text: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - Audio Playback

    func playLastAudio() {
        guard FileManager.default.fileExists(atPath: tempAudioURL.path) else {
            print("[Izi Input] Last audio file not found at \(tempAudioURL.path)")
            return
        }

        if audioInputState.isPlayingAudio {
            audioPlayer?.stop()
            audioInputState.isPlayingAudio = false
            print("[Izi Input] Playback stopped.")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: tempAudioURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            audioInputState.isPlayingAudio = true
            print("[Izi Input] Playing last audio file...")
        } catch {
            print("[Izi Input] Failed to play last audio: \(error.localizedDescription)")
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.audioInputState.isPlayingAudio = false
            print("[Izi Input] Playback finished.")
        }
    }
}

// Custom print function to redirect logs to a debug file for runtime diagnostics
func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let output = items.map { "\($0)" }.joined(separator: separator)
    Swift.print(output, terminator: terminator) // Call standard library print

    let fileURL = URL(fileURLWithPath: "/Users/dushes/projects/izi-input/debug.log")
    let logMessage = "[\(Date())] \(output)\(terminator)"
    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: fileURL)
        }
    }
}
