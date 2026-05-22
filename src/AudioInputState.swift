import Foundation
import Combine

enum OutputLanguage: String, CaseIterable, Identifiable, Hashable {
    case russian = "rus"
    case english = "eng"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .russian: return "RUS"
        case .english: return "ENG"
        }
    }
}

class AudioInputState: ObservableObject {
    private static let outputLanguageDefaultsKey = "OutputLanguage"

    @Published var isRecording = false
    @Published var isAudioReady = false
    @Published var amplitude: CGFloat = 0.0
    @Published var outputLanguage: OutputLanguage {
        didSet {
            UserDefaults.standard.set(outputLanguage.rawValue, forKey: Self.outputLanguageDefaultsKey)
        }
    }
    
    // Last recording info
    @Published var lastRussianText: String = ""
    @Published var lastEnglishText: String = ""
    @Published var hasLastAudio: Bool = false
    @Published var isPlayingAudio: Bool = false

    init() {
        if let savedLanguage = UserDefaults.standard.string(forKey: Self.outputLanguageDefaultsKey),
           let outputLanguage = OutputLanguage(rawValue: savedLanguage) {
            self.outputLanguage = outputLanguage
        } else {
            self.outputLanguage = .english
        }
    }
}
