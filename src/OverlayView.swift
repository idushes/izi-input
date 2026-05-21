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

    var body: some View {
        let baseHeight = CGFloat(6.0)
        let multiplier = CGFloat(1.0 - Double(abs(3 - index)) * 0.15)

        let idleHeight = baseHeight + CGFloat(sin(phase + Double(index) * 0.8) * 2.5)
        let activeHeight = baseHeight + 25 * amplitude * multiplier
        let blendFactor = min(1.0, Double(amplitude) * 8.0)
        let height = activeHeight * CGFloat(blendFactor) + idleHeight * CGFloat(1.0 - blendFactor)

        RoundedRectangle(cornerRadius: 1.5)
            .fill(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3.0, height: height)
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.6), value: amplitude)
    }
}

struct LoadingRing: View {
    let rotation: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 3)

            Circle()
                .trim(from: 0.10, to: 0.78)
                .stroke(
                    LinearGradient(
                        colors: [.orange, .yellow, .orange.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: 30, height: 30)
    }
}

struct OverlayView: View {
    @ObservedObject var audioInputState: AudioInputState

    var body: some View {
        TimelineView(.animation) { timelineContext in
            let time = timelineContext.date.timeIntervalSinceReferenceDate
            let isReady = audioInputState.isAudioReady
            let loopTime = time.truncatingRemainder(dividingBy: 1.0)
            let pulseTime = time.truncatingRemainder(dividingBy: 10.0)
            let pulse = 0.5 + 0.5 * sin(pulseTime * 7.0)

            ZStack {
                Capsule()
                    .fill(Color.black.opacity(isReady ? 0.26 : 0.0))
                    .shadow(
                        color: (isReady ? Color.purple : Color.orange).opacity(0.28),
                        radius: isReady ? 10 : 8,
                        x: 0,
                        y: 3
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: isReady
                                        ? [.blue.opacity(0.52), .purple.opacity(0.52)]
                                        : [.orange.opacity(0.75), .yellow.opacity(0.55)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )

                if isReady {
                    readyContent(time: time, pulse: pulse)
                        .transition(.opacity.combined(with: .scale(scale: 0.76)))
                } else {
                    LoadingRing(rotation: loopTime * 360.0)
                        .transition(.opacity.combined(with: .scale(scale: 0.86)))
                }
            }
            .frame(width: isReady ? 86 : 42, height: isReady ? 44 : 42)
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: isReady)
        }
        .frame(width: 110, height: 70)
        .padding(0)
    }

    private func readyContent(time: Double, pulse: Double) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(0.88 + 0.34 * pulse)
                .opacity(0.68 + 0.32 * pulse)

            HStack(spacing: 2.5) {
                ForEach(0..<7) { i in
                    WaveBar(
                        amplitude: audioInputState.amplitude,
                        index: i,
                        phase: time * 4.0
                    )
                }
            }
            .frame(width: 40, height: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
