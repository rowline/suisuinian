import SwiftUI

struct WatchContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()

    var body: some View {
        NavigationStack {
            TabView {
                // ── Tab 1: Record ────────────────────────────────────────
                recordTab
                    .tag(0)

                // ── Tab 2: Recordings List ───────────────────────────────
                NavigationLink(destination: WatchRecordingsView()) {
                    VStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text("Recordings")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .tag(1)
            }
            .tabViewStyle(.page)
        }
    }

    private var recordTab: some View {
        VStack(spacing: 8) {
            Spacer()

            Button {
                if audioRecorder.isRecording {
                    audioRecorder.stopRecording()
                } else {
                    audioRecorder.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(audioRecorder.isRecording ? Color.red : Color.blue)
                        .frame(width: 80, height: 80)
                    Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)

            // Status label
            if let error = audioRecorder.lastError {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
            } else if audioRecorder.isRecording {
                Text("Listening...")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if let url = audioRecorder.latestRecordingURL {
                VStack(spacing: 2) {
                    Text("Saved ✓")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(url.lastPathComponent)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text("Tap to Record")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "chevron.right.2")
                    .font(.caption2)
                Text("Swipe for list")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    WatchContentView()
}
