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
    
    // Temporary audio file path
    var tempAudioURL: URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent("izi_input_temp.wav")
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        requestMicrophonePermission()
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
        
        // Microphone access check
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else {
            showNotification(title: "Microphone Access Required", text: "Please enable Microphone permissions for this app.")
            requestMicrophonePermission()
            return
        }
        
        // Audio Recorder Settings: 16000Hz, 1 channel, 16-bit PCM (Required by whisper.cpp)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: tempAudioURL, settings: settings)
            audioRecorder?.prepareToRecord()
            
            // Enable voice level metering
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isRecording = true
            updateStatusIcon()
            
            // Start voice metering timer (50ms interval)
            audioInputState.isRecording = true
            meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self, let recorder = self.audioRecorder else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                
                // Map dB power (-50dB to 0dB) to normalized range 0.0 to 1.0
                let normalized = CGFloat(max(0.0, (power + 50.0) / 50.0))
                DispatchQueue.main.async {
                    self.audioInputState.amplitude = normalized
                }
            }
            
            // Fade-in the visual overlay at the bottom of the screen
            overlayWindow?.alphaValue = 0
            overlayWindow?.updatePosition()
            overlayWindow?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                overlayWindow?.animator().alphaValue = 1.0
            }
            
            print("[Izi Input] Recording started...")
        } catch {
            print("[Izi Input] Failed to start recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop metering timer
        meteringTimer?.invalidate()
        meteringTimer = nil
        audioInputState.isRecording = false
        audioInputState.amplitude = 0.0
        
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        isProcessing = true
        updateStatusIcon()
        
        // Fade-out the visual overlay
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.overlayWindow?.animator().alphaValue = 0
        }) {
            self.overlayWindow?.orderOut(nil)
        }
        
        print("[Izi Input] Recording stopped. Starting transcription...")
        
        // Process on background thread to keep UI interactive
        DispatchQueue.global(qos: .userInitiated).async {
            self.runWhisperTranslation()
        }
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
                "--no-timestamps"
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
                "--no-timestamps"
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
        let priorContent = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("[Izi Input] Clipboard set to: \"\(text)\"")
        
        // Simulate Cmd+V keystroke using session event tap
        let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true)
        let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false)
        let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        
        // Apply Command modifier flags to key press events
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        
        let loc = CGEventTapLocation.cgSessionEventTap
        cmdDown?.post(tap: loc)
        vDown?.post(tap: loc)
        vUp?.post(tap: loc)
        cmdUp?.post(tap: loc)
        print("[Izi Input] Simulated Cmd+V keystroke sent.")
        
        // Restore prior clipboard content after a safe 0.5s delay to avoid race conditions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let prior = priorContent {
                let currentCB = NSPasteboard.general.string(forType: .string)
                if currentCB == text {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prior, forType: .string)
                    print("[Izi Input] Clipboard restored successfully.")
                }
            }
        }
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
