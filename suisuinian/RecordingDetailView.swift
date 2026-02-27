import SwiftUI
import AVFoundation
import Speech
import Combine

// Represents one transcribed segment with timing info
struct TranscriptionSegment: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval   // start time in seconds
    let duration: TimeInterval
}

@MainActor
class RecordingDetailViewModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    // MARK: - Published
    @Published var isPlaying = false
    @Published var isTranscribing = false
    @Published var segments: [TranscriptionSegment] = []
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var transcriptionStatus: String = "Transcribing..."

    // MARK: - Private
    private var audioPlayer: AVAudioPlayer?
    private var displayTimer: Timer?
    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
        setupPlayer()
    }

    private func setupPlayer() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
        } catch {
            errorMessage = "Failed to load audio: \(error.localizedDescription)"
        }
    }

    // MARK: - Playback
    func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            displayTimer?.invalidate()
            isPlaying = false
        } else {
            audioPlayer?.play()
            startDisplayTimer()
            isPlaying = true
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        displayTimer?.invalidate()
        currentTime = 0
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    func seekRelative(_ delta: TimeInterval) {
        let newTime = max(0, min(duration, (audioPlayer?.currentTime ?? 0) + delta))
        seek(to: newTime)
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = self?.audioPlayer?.currentTime ?? 0
            }
        }
    }

    // MARK: - AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.displayTimer?.invalidate()
            self.isPlaying = false
            self.currentTime = 0
        }
    }

    // MARK: - ASR
    func startTranscription() {
        isTranscribing = true
        transcriptionStatus = "Requesting permission..."
        errorMessage = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                if authStatus == .authorized {
                    self.performTranscription()
                } else {
                    self.errorMessage = "Speech recognition was not authorized."
                    self.isTranscribing = false
                }
            }
        }
    }

    private func performTranscription() {
        // Try Chinese first, fall back to device locale
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
                      ?? SFSpeechRecognizer()

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech Recognizer unavailable on this device/simulator."
            isTranscribing = false
            return
        }

        transcriptionStatus = "Recognizing speech ..."
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        // Ask for word-level timestamps
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let result {
                    // Build segments from low-level SFTranscriptionSegment which includes timing
                    self.segments = result.bestTranscription.segments.map { seg in
                        TranscriptionSegment(
                            text: seg.substring,
                            timestamp: seg.timestamp,
                            duration: seg.duration
                        )
                    }
                    if result.isFinal {
                        self.isTranscribing = false
                        self.transcriptionStatus = "Transcription complete"
                    }
                }

                if let error {
                    if self.segments.isEmpty {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isTranscribing = false
                }
            }
        }
    }

    // MARK: - Helpers
    var activeSegmentIndex: Int? {
        // Find the last segment whose start time is <= currentTime
        let idx = segments.lastIndex(where: { $0.timestamp <= currentTime })
        return idx
    }
}

// MARK: - View
struct RecordingDetailView: View {
    let recording: LocalRecording
    @StateObject private var vm: RecordingDetailViewModel

    init(recording: LocalRecording) {
        self.recording = recording
        _vm = StateObject(wrappedValue: RecordingDetailViewModel(url: recording.url))
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header info ──────────────────────────────────────────────
            VStack(spacing: 2) {
                Text(recording.date.formatted(date: .abbreviated, time: .standard))
                    .font(.subheadline).fontWeight(.semibold)
                Text(recording.size)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            // ── Karaoke Transcript ───────────────────────────────────────
            Group {
                if vm.isTranscribing && vm.segments.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(vm.transcriptionStatus)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.segments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .font(.largeTitle).foregroundStyle(.secondary)
                        Text("No transcription yet")
                            .foregroundStyle(.secondary)
                        if let err = vm.errorMessage {
                            Text(err).font(.caption).foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    KaraokeTextView(segments: vm.segments,
                                   activeIndex: vm.activeSegmentIndex) { tappedIndex in
                        vm.seek(to: vm.segments[tappedIndex].timestamp)
                        if !vm.isPlaying { vm.togglePlayback() }
                    }
                }
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity)

            Divider()

            // ── Progress Slider ──────────────────────────────────────────
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { vm.currentTime },
                    set: { vm.seek(to: $0) }
                ), in: 0...max(vm.duration, 1))
                .padding(.horizontal)

                HStack {
                    Text(formatTime(vm.currentTime))
                    Spacer()
                    Text(formatTime(vm.duration))
                }
                .font(.caption2).monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }
            .padding(.top, 8)

            // ── Playback Controls ────────────────────────────────────────
            HStack(spacing: 32) {
                Button { vm.seekRelative(-10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }

                Button { vm.togglePlayback() } label: {
                    Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                }

                Button { vm.seekRelative(10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Voice Note")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Auto-start ASR when the view opens
            vm.startTranscription()
        }
        .onDisappear {
            vm.stop()
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Karaoke word-flow view
struct KaraokeTextView: View {
    let segments: [TranscriptionSegment]
    let activeIndex: Int?
    let onTap: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Use a flow layout via wrapping HStack in a lazy grid workaround
                FlowLayout(spacing: 6) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                        Text(seg.text)
                            .font(.title3)
                            .fontWeight(idx == activeIndex ? .bold : .regular)
                            .foregroundStyle(
                                idx == activeIndex ? Color.blue :
                                (activeIndex != nil && idx < activeIndex! ? Color.secondary : Color.primary)
                            )
                            .padding(.vertical, 2)
                            .id(seg.id)
                            .onTapGesture { onTap(idx) }
                            .animation(.easeInOut(duration: 0.2), value: activeIndex)
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: activeIndex) { _, newIdx in
                if let newIdx, newIdx < segments.count {
                    withAnimation(.easeInOut) {
                        proxy.scrollTo(segments[newIdx].id, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Simple flow layout (word-wrap)
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let rowHeights: [CGFloat] = rows.map { row -> CGFloat in
            let h: CGFloat = row.map { sv -> CGFloat in sv.sizeThatFits(.unspecified).height }.max() ?? 0
            return h
        }
        let totalRowHeight: CGFloat = rowHeights.reduce(0, +)
        let gapHeight: CGFloat = CGFloat(max(rows.count - 1, 0)) * spacing
        let height: CGFloat = totalRowHeight + gapHeight
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowH = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for sv in row {
                let sz = sv.sizeThatFits(.unspecified)
                sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += rowH + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var x: CGFloat = 0
        let maxW = proposal.width ?? .infinity
        for sv in subviews {
            let w = sv.sizeThatFits(.unspecified).width
            if x + w > maxW, !rows[rows.endIndex - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.endIndex - 1].append(sv)
            x += w + spacing
        }
        return rows
    }
}
