import SwiftUI
import AppKit

class OverlayWindow: NSWindow {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
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
            let windowWidth: CGFloat = 320
            let windowHeight: CGFloat = 80
            
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
        let baseHeight = CGFloat(8.0)
        let multiplier = CGFloat(1.0 - Double(abs(3 - index)) * 0.15)
        
        // Beautiful breathing sine wave for idle state
        let idleHeight = baseHeight + CGFloat(sin(phase + Double(index) * 0.8) * 3.0)
        
        // Voice reactive wave
        let activeHeight = baseHeight + 40 * amplitude * multiplier
        
        // Smoothly blend from idle wave to active voice wave
        let blendFactor = min(1.0, Double(amplitude) * 8.0)
        let height = activeHeight * CGFloat(blendFactor) + idleHeight * CGFloat(1.0 - blendFactor)
        
        RoundedRectangle(cornerRadius: 2)
            .fill(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3.5, height: height)
            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.6), value: amplitude)
    }
}

struct OverlayView: View {
    @ObservedObject var audioInputState: AudioInputState
    @State private var isPulsing = false
    @State private var phase = 0.0
    
    var body: some View {
        HStack(spacing: 16) {
            // Pulsing Red Recording Indicator
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .opacity(isPulsing ? 1.0 : 0.5)
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: isPulsing
                )
            
            Text("Слушаю вас...")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            // Voice reactive wave bar visualization
            HStack(spacing: 3) {
                ForEach(0..<7) { i in
                    WaveBar(amplitude: audioInputState.amplitude, index: i, phase: phase)
                }
            }
            .frame(width: 50, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .shadow(color: Color.purple.opacity(0.25), radius: 12, x: 0, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.blue.opacity(0.4), .purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .frame(width: 300, height: 60)
        .padding(10) // Padding to prevent clipping the shadow
        .onAppear {
            isPulsing = true
            // Continuous breathing animation for the wave
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = Double.pi * 2
            }
        }
    }
}
