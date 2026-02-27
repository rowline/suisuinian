import AppIntents

struct WatchCaptureIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Start Watch Suisuinian"
    
    @Parameter(title: "Show visually")
    var showUI: Bool
    
    init() {
        self.showUI = true
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await MainActor.run {
            // Setup local audio recording for the Watch
            let audioRecorder = AudioRecorder()
            audioRecorder.startRecording()
        }
        
        return .result(value: "Watch recording started.")
    }
}
