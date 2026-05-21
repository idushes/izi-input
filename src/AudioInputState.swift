import Foundation
import Combine

class AudioInputState: ObservableObject {
    @Published var isRecording = false
    @Published var isAudioReady = false
    @Published var amplitude: CGFloat = 0.0
    
    // Last recording info
    @Published var lastRussianText: String = ""
    @Published var lastEnglishText: String = ""
    @Published var hasLastAudio: Bool = false
    @Published var isPlayingAudio: Bool = false
}
