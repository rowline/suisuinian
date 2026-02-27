@preconcurrency import Foundation

/// Represents a single "Suisuinian" or "碎碎念" entry sent to the Cloud Brain.
public struct MemoryEntity: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let transcription: String?
    public let emotion: String?
    public let location: String?
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), transcription: String? = nil, emotion: String? = nil, location: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.transcription = transcription
        self.emotion = emotion
        self.location = location
    }
}

/// Represents the structured daily report returned from the LLM.
public struct DailyReport: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let markdownContent: String
    public let extractedTasks: [ReportTask]
    
    public init(id: UUID = UUID(), date: Date = Date(), markdownContent: String, extractedTasks: [ReportTask] = []) {
        self.id = id
        self.date = date
        self.markdownContent = markdownContent
        self.extractedTasks = extractedTasks
    }
}

public struct ReportTask: Codable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let isCompleted: Bool
    
    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

/// API Request payload for uploading audio files
public struct AudioUploadRequest: Codable, Sendable {
    public let timestamp: Date
    public let base64Audio: String // In production, consider multipart/form-data for raw audio
    public let optionalTranscription: String?
    public let location: String?
}
