import Foundation

/// Calls the local suisuinian-brain-proxy at localhost:19001.
enum OpenClawSummarizer {

    private static let baseURL = URL(string: "http://127.0.0.1:19001")!

    // MARK: - Summarize (cached by audioPath on Mac side)
    static func summarize(transcript: String, audioPath: String) async throws -> String {
        struct Body: Encodable { let transcript: String; let audioPath: String }
        struct Resp: Decodable { let summary: String }
        let resp: Resp = try await post(path: "/summarize",
                                        body: Body(transcript: transcript, audioPath: audioPath))
        return resp.summary
    }

    // MARK: - Daily Summarize
    static func dailySummarize(transcripts: [String], dateString: String) async throws -> String {
        struct Body: Encodable { let transcripts: [String]; let dateString: String }
        struct Resp: Decodable { let summary: String }
        let resp: Resp = try await post(path: "/daily_summarize",
                                        body: Body(transcripts: transcripts, dateString: dateString))
        return resp.summary
    }

    // MARK: - Chat (stateful session)
    static func chat(message: String, useGlobalScope: Bool?, sessionId: String?) async throws -> ChatReply {
        struct Body: Encodable { let message: String; let useGlobalScope: Bool?; let sessionId: String? }
        let body = Body(message: message, useGlobalScope: useGlobalScope, sessionId: sessionId)
        return try await post(path: "/chat", body: body)
    }

    struct ChatReply: Decodable {
        let text: String
        let sessionId: String
    }

    // MARK: - Generic POST helper
    private static func post<B: Encodable, R: Decodable>(path: String, body: B) async throws -> R {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Err.invalidResponse }
        guard http.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "HTTP \(http.statusCode)"
            throw Err.serverError(msg)
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    enum Err: LocalizedError {
        case invalidResponse, serverError(String)
        var errorDescription: String? {
            switch self {
            case .invalidResponse:     return "Invalid proxy response"
            case .serverError(let m):  return "OpenClaw: \(m)"
            }
        }
    }
}
