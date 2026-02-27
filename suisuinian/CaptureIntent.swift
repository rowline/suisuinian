import AppIntents
import AVFoundation

/// The core AppIntent designed to be bound to the iPhone Action Button
struct CaptureIntent: AudioRecordingIntent {
    static var title: LocalizedStringResource = "Start Suisuinian"
    static var description = IntentDescription("Immediately starts recording a voice memo for your AI brain.")
    
    // Shows in Dynamic Island/Live Activities
    @Parameter(title: "Show visually")
    var showUI: Bool
    
    init() {
        self.showUI = true
    }
    
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await MainActor.run {
            let audioRecorder = AudioRecorder()
            
            // Simulating the intent lifecycle
            // In a real AppIntent for recording, you would manage AVAudioSession locally
            // or trigger a background task.
            audioRecorder.startRecording()
        }
        
        // For an Intent, we might just return a confirmation that recording started.
        // True "background execution while app is killed" requires special entitlements 
        // or utilizing iOS's built-in Live Activities / Voice Memos integrations.
        
        return .result(value: "Recording started. Tap Action Button again to stop.")
    }
}
