import Foundation

/// Configuration for the Suisuinian Cloud Brain API
public struct APIConfig: Sendable {
    /// The base URL for the private cloud RESTful API
    public static let baseURL = "https://api.yourcustomcloud.com/v1"
    
    /// API Keys or OAuth tokens should ideally be stored securely in the Keychain.
    /// This is a simplified access for the prototype.
    nonisolated(unsafe) public static let apiKey = "YOUR_API_KEY_HERE"
    
    public struct Endpoints {
        public static let uploadAudio = "/capture/audio"
        public static let uploadText = "/capture/text"
        public static let getDailyReport = "/reports/daily"
        public static let queryMemories = "/memories/search"
    }
}
