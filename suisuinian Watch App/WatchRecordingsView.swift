import SwiftUI
import AVFoundation
import Combine

// MARK: - Playback VM for watchOS

@MainActor
class WatchPlayerViewModel: ObservableObject {
    @Published var playingURL: URL?
    @Published var isPlaying = false
    private var audioPlayer: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playingURL == url, isPlaying {
            audioPlayer?.pause()
            isPlaying = false
        } else {
            playingURL = url
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                isPlaying = true
            } catch {
                print("Watch player error: \(error)")
            }
        }
    }

    func stop() {
        audioPlayer?.stop()
        isPlaying = false
    }
}

// MARK: - Recordings list on Watch

struct WatchRecordingsView: View {
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var player = WatchPlayerViewModel()

    var body: some View {
        Group {
            if recordingManager.recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mic.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No recordings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(recordingManager.recordings, id: \.url) { recording in
                        Button {
                            player.toggle(recording.url)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: player.playingURL == recording.url && player.isPlaying
                                      ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(player.playingURL == recording.url && player.isPlaying
                                                     ? Color.orange : Color.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recording.date, style: .time)
                                        .font(.caption).fontWeight(.semibold)
                                    Text("\(recording.date, style: .date)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text(recording.size)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                player.stop()
                                recordingManager.delete(recording: recording)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recordings")
        .onAppear {
            recordingManager.fetchRecordings()
        }
        .onDisappear {
            player.stop()
        }
    }
}
