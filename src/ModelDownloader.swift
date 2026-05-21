import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case tiny = "Tiny (~75 MB)"
    case base = "Base (~148 MB)"
    case small = "Small (~466 MB)"
    
    var id: String { self.rawValue }
    
    var filename: String {
        switch self {
        case .tiny: return "ggml-tiny.bin"
        case .base: return "ggml-base.bin"
        case .small: return "ggml-small.bin"
        }
    }
    
    var url: URL {
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(self.filename)")!
    }
}

class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0.0
    @Published var isDownloading: Bool = false
    @Published var status: String = ""
    @Published var isModelDownloaded: Bool = false
    
    @Published var selectedModel: WhisperModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "SelectedWhisperModel")
            checkModelExists()
        }
    }
    
    private var downloadTask: URLSessionDownloadTask?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
    }()
    
    var modelURL: URL {
        return selectedModel.url
    }
    
    var destinationURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("izi-input", isDirectory: true)
        let modelsDir = appDir.appendingPathComponent("models", isDirectory: true)
        
        // Ensure directories exist
        if !fileManager.fileExists(atPath: modelsDir.path) {
            try? fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        return modelsDir.appendingPathComponent(selectedModel.filename)
    }
    
    override init() {
        if let savedRaw = UserDefaults.standard.string(forKey: "SelectedWhisperModel"),
           let savedModel = WhisperModel(rawValue: savedRaw) {
            self.selectedModel = savedModel
        } else {
            self.selectedModel = .base
        }
        super.init()
        checkModelExists()
    }
    
    func checkModelExists() {
        let exists = FileManager.default.fileExists(atPath: destinationURL.path)
        DispatchQueue.main.async {
            self.isModelDownloaded = exists
            if exists {
                self.status = "Модель готова к использованию."
            } else {
                self.status = "Модель не скачана."
            }
        }
    }
    
    func startDownload() {
        guard !isDownloading else { return }
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }
        
        isDownloading = true
        status = "Соединение..."
        progress = 0.0
        
        downloadTask = session.downloadTask(with: modelURL)
        downloadTask?.resume()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
        progress = 0.0
        status = "Скачивание отменено."
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let currentProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let percent = Int(currentProgress * 100)
        let sizeMB = Double(totalBytesExpectedToWrite) / 1024.0 / 1024.0
        let downloadedMB = Double(totalBytesWritten) / 1024.0 / 1024.0
        
        DispatchQueue.main.async {
            self.progress = currentProgress
            self.status = String(format: "Загрузка: %.1f MB / %.1f MB (%d%%)", downloadedMB, sizeMB, percent)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        let dest = destinationURL
        
        // Remove existing if any
        if fileManager.fileExists(atPath: dest.path) {
            try? fileManager.removeItem(at: dest)
        }
        
        do {
            try fileManager.moveItem(at: location, to: dest)
            DispatchQueue.main.async {
                self.isDownloading = false
                self.isModelDownloaded = true
                self.status = "Модель успешно загружена."
                self.progress = 1.0
            }
        } catch {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.status = "Не удалось сохранить модель: \(error.localizedDescription)"
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Check if cancelled
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            
            DispatchQueue.main.async {
                self.isDownloading = false
                self.status = "Ошибка загрузки: \(error.localizedDescription)"
            }
        }
    }
}
