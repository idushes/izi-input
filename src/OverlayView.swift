import SwiftUI
import AppKit

class OverlayWindow: NSWindow {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 110, height: 70),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .statusBar // Sits above all other windows
        self.ignoresMouseEvents = true // Clicks pass right through to windows behind
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        self.contentView = contentView
        
        updatePosition()
    }
    
    func updatePosition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let screen = screen {
            let screenFrame = screen.visibleFrame
            let windowWidth: CGFloat = 110
            let windowHeight: CGFloat = 70
            
            // Center horizontally and place 40px above the bottom edge (just above the dock)
            let x = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
            let y = screenFrame.origin.y + 40
            
            self.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }
    }
}

struct WaveBar: View {
    let amplitude: CGFloat
    let index: Int
    let phase: Double
    let isAudioReady: Bool

    var body: some View {
        let baseHeight = CGFloat(6.0) // slightly reduced baseline for compactness
        let multiplier = CGFloat(1.0 - Double(abs(3 - index)) * 0.15)
        let colors: [Color] = isAudioReady ? [.blue, .purple] : [.orange, .yellow]

        // Beautiful breathing sine wave for idle state
        let idleHeight = baseHeight + CGFloat(sin(phase + Double(index) * 0.8) * 2.5)
        
        // Voice reactive wave
        let activeHeight = baseHeight + 25 * amplitude * multiplier // slightly scaled down height
        
        // Smoothly blend from idle wave to active voice wave
        let blendFactor = min(1.0, Double(amplitude) * 8.0)
        let height = activeHeight * CGFloat(blendFactor) + idleHeight * CGFloat(1.0 - blendFactor)
        
        RoundedRectangle(cornerRadius: 1.5)
            .fill(
                LinearGradient(
                    colors: colors,
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3.0, height: height) // slightly narrower bars
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.6), value: amplitude)
            .animation(.easeInOut(duration: 0.25), value: isAudioReady)
    }
}

struct OverlayView: View {
    @ObservedObject var audioInputState: AudioInputState
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 8) { // compact spacing
            // Pulsing Red Recording Indicator
            Circle()
                .fill(audioInputState.isAudioReady ? Color.red : Color.orange)
                .frame(width: 6, height: 6)
                .scaleEffect(isPulsing ? (audioInputState.isAudioReady ? 1.25 : 1.08) : 0.75)
                .opacity(isPulsing ? (audioInputState.isAudioReady ? 1.0 : 0.75) : 0.5)
                .animation(
                    .easeInOut(duration: audioInputState.isAudioReady ? 0.6 : 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .animation(.easeInOut(duration: 0.25), value: audioInputState.isAudioReady)

            // Voice reactive wave bar visualization using TimelineView for continuous, 60fps animations
            TimelineView(.animation) { timelineContext in
                let time = timelineContext.date.timeIntervalSinceReferenceDate
                HStack(spacing: 2.5) {
                    ForEach(0..<7) { i in
                        WaveBar(
                            amplitude: audioInputState.isAudioReady ? audioInputState.amplitude : 0.0, 
                            index: i, 
                            phase: time * 4.0, // 4.0 speed multiplier for perfect breathing wave rate
                            isAudioReady: audioInputState.isAudioReady
                        )
                    }
                }
            }
            .frame(width: 40, height: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .shadow(
                    color: (audioInputState.isAudioReady ? Color.purple : Color.orange).opacity(0.25),
                    radius: 8,
                    x: 0,
                    y: 3
                )
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: audioInputState.isAudioReady
                            ? [.blue.opacity(0.4), .purple.opacity(0.4)]
                            : [.orange.opacity(0.45), .yellow.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.25), value: audioInputState.isAudioReady)
        .frame(width: 90, height: 50)
        .padding(10) // Padding to prevent clipping the shadow
        .onAppear {
            isPulsing = true
        }
    }
}
