import Foundation
import Combine

class AudioInputState: ObservableObject {
    @Published var isRecording = false
    @Published var amplitude: CGFloat = 0.0
}
