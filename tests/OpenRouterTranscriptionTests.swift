import Foundation

final class StubProtocol: URLProtocol {
    static var status = 200
    static var responseBody = ""
    static var transportError: Error?
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        if let error = Self.transportError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct OpenRouterTests {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = OpenRouterTranscription(session: URLSession(configuration: configuration))
        let audio = Data([0x52, 0x49, 0x46, 0x46])
        for model in OpenRouterModels.all {
            StubProtocol.responseBody = #"{"text":" Привет \n"}"#
            let result = try await client.transcribe(audio: audio, model: model, apiKey: "test-secret")
            precondition(result == "Привет")
            let request = StubProtocol.requests.last!
            precondition(request.url!.path == "/api/v1/audio/transcriptions")
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret")
            // URLSession may expose the body as a stream to URLProtocol.
            let body: Data
            if let data = request.httpBody { body = data } else {
                let stream = request.httpBodyStream!
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                body = data
            }
            let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            precondition(json["model"] as? String == model)
            let input = json["input_audio"] as! [String: String]
            precondition(input["format"] == "wav" && Data(base64Encoded: input["data"]!) == audio)
            precondition(json["language"] as? String == "ru")
        }
        StubProtocol.responseBody = #"{"choices":[{"message":{"content":" Hello "}}]}"#
        let translation = try await client.translate(text: "Привет", model: "openai/gpt-4o-mini", apiKey: "test-secret")
        precondition(translation == "Hello")
        precondition(StubProtocol.requests.last!.url!.path == "/api/v1/chat/completions")
        for status in [401, 402, 403, 404, 429, 500] {
            StubProtocol.status = status
            StubProtocol.responseBody = "test-secret private audio"
            do {
                _ = try await client.transcribe(audio: audio, model: OpenRouterModels.all[0], apiKey: "test-secret")
                fatalError("Expected HTTP error")
            } catch {
                precondition(error.localizedDescription.contains(String(status)))
                precondition(!error.localizedDescription.contains("test-secret"))
            }
        }
        StubProtocol.status = 200
        for body in ["{}", "invalid", #"{"text":" "}"#] {
            StubProtocol.responseBody = body
            do {
                _ = try await client.transcribe(audio: audio, model: OpenRouterModels.all[0], apiKey: "test-secret")
                fatalError("Expected invalid response error")
            } catch is TranscriptionError {}
        }
        for body in ["{}", #"{"choices":[]}"#, #"{"choices":[{"message":{"content":null}}]}"#, #"{"choices":[{"message":{"content":" "}}]}"#] {
            StubProtocol.responseBody = body
            do {
                _ = try await client.translate(text: "Привет", model: "openai/gpt-4o-mini", apiKey: "test-secret")
                fatalError("Expected invalid translation error")
            } catch is TranscriptionError {}
        }
        StubProtocol.transportError = URLError(.timedOut)
        do {
            _ = try await client.transcribe(audio: audio, model: OpenRouterModels.all[0], apiKey: "test-secret")
            fatalError("Expected timeout")
        } catch let error as URLError { precondition(error.code == .timedOut) }
        let count = StubProtocol.requests.count
        do {
            _ = try await client.transcribe(audio: audio, model: OpenRouterModels.all[0], apiKey: "")
            fatalError("Expected missing key error")
        } catch is TranscriptionError {}
        precondition(StubProtocol.requests.count == count)
        print("OpenRouter tests passed (six models, translation, HTTP errors, invalid responses, timeout, missing key).")
    }
}
