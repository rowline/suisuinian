import Foundation
import AVFoundation
import Combine

/// Handles recording audio for both iOS and watchOS
class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?

    @Published var isRecording = false
    @Published var latestRecordingURL: URL?
    @Published var lastError: String?

    let docsURL: URL = AppGroupContainer.recordingsURL

    // MARK: - Start

    func startRecording() {
        #if os(watchOS)
        // On watchOS, permission is managed by the system — go straight to recording
        performStartRecording()
        #else
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    if allowed { self.performStartRecording() }
                    else { self.lastError = "Microphone permission denied." }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    if allowed { self.performStartRecording() }
                    else { self.lastError = "Microphone permission denied." }
                }
            }
        }
        #endif
    }

    private func performStartRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            #if os(watchOS)
            try session.setCategory(.record, mode: .default)
            #else
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            #endif
            try session.setActive(true)

            let filename = "suisuinian-\(Date().timeIntervalSince1970).m4a"
            let audioFilename = docsURL.appendingPathComponent(filename)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            print("🎙️ Recording started → \(audioFilename.lastPathComponent)")

            DispatchQueue.main.async {
                self.isRecording = true
                self.latestRecordingURL = audioFilename
                self.lastError = nil
            }
        } catch {
            print("❌ Recording setup failed: \(error)")
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
        }
    }

    // MARK: - Stop

    func stopRecording() {
        // Calling stop() will flush & finalize the file, then fire audioRecorderDidFinishRecording
        audioRecorder?.stop()
        DispatchQueue.main.async { self.isRecording = false }
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        print(flag ? "✅ File saved: \(url.lastPathComponent)" : "⚠️ Recording failed to save: \(url.lastPathComponent)")

        guard flag else {
            DispatchQueue.main.async { self.lastError = "Recording was not saved properly." }
            return
        }

        #if os(watchOS)
        // Only transfer AFTER the file is fully written to disk (this delegate fires post-flush)
        print("📡 Initiating WatchConnectivity transfer...")
        WatchConnectivityManager.shared.transferAudioFile(
            file: url,
            metadata: ["timestamp": Date().timeIntervalSince1970]
        )
        #endif

        DispatchQueue.main.async { self.latestRecordingURL = url }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ Encode error: \(String(describing: error))")
        DispatchQueue.main.async { self.lastError = error?.localizedDescription }
    }
}
