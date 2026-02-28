import SwiftUI
import AVFoundation
import Speech
import Combine

// Represents one transcribed segment with timing info
struct TranscriptionSegment: Identifiable, Codable {
    var id = UUID()
    var text: String
    var timestamp: TimeInterval   // start time in seconds
    var duration: TimeInterval
    var speaker: String?          // Added to represent Diarization info
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
    @Published var isTranscriptIncomplete = false

    // AI Summary
    @Published var summary: String?          // Markdown text from OpenClaw
    @Published var isSummarizing = false
    @Published var summaryError: String?

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

    // MARK: - Transcript & Chat persistence
    private var transcriptFileURL: URL {
        url.deletingPathExtension().appendingPathExtension("transcript")
    }
    private var chatFileURL: URL {
        url.deletingPathExtension().appendingPathExtension("chat")
    }

    struct SavedTranscript: Codable {
        let transcript: String
        let speaker_segments: [SpeakerSegment]?
        
        struct SpeakerSegment: Codable {
            let text: String
            let start: Double
            let end: Double
            let speaker: String?
        }
    }

    struct ChatState: Codable {
        var messages: [ChatMessage]
        var sessionId: String?
    }

    private func saveTranscript(_ text: String, segments: [TranscriptionSegment]) {
        let speakerSegments = segments.map { 
            SavedTranscript.SpeakerSegment(text: $0.text, start: $0.timestamp, end: $0.timestamp + $0.duration, speaker: $0.speaker)
        }
        let saved = SavedTranscript(transcript: text, speaker_segments: speakerSegments)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: transcriptFileURL)
        }
    }
    
    private func loadSavedTranscript() -> SavedTranscript? {
        guard let data = try? Data(contentsOf: transcriptFileURL) else { return nil }
        if let saved = try? JSONDecoder().decode(SavedTranscript.self, from: data) { return saved }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty, !text.hasPrefix("{") {
            return SavedTranscript(transcript: text, speaker_segments: nil)
        }
        return nil
    }

    private func saveChatHistory() {
        let state = ChatState(messages: chatMessages, sessionId: chatSessionId)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: chatFileURL)
        }
    }
    
    private func loadChatHistory() {
        guard let data = try? Data(contentsOf: chatFileURL),
              let state = try? JSONDecoder().decode(ChatState.self, from: data) else { return }
        self.chatMessages = state.messages
        self.chatSessionId = state.sessionId
    }

    private func checkCompleteness(_ text: String) -> Bool {
        let dur = audioPlayer?.duration ?? 0
        guard dur > 0 else { return false }
        return Double(text.count) / dur < 1.0  // < 1 char/sec = suspicious
    }

    // MARK: - ASR entry point
    func startTranscription() {
        errorMessage = nil
        loadChatHistory()
        if let saved = loadSavedTranscript() {
            if let speakerSegments = saved.speaker_segments, !speakerSegments.isEmpty {
                segments = speakerSegments.map {
                    TranscriptionSegment(text: $0.text, timestamp: $0.start, duration: $0.end - $0.start, speaker: $0.speaker)
                }
            } else {
                let words = saved.transcript.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                segments = words.enumerated().map { i, w in
                    TranscriptionSegment(text: w, timestamp: Double(i) * 0.4, duration: 0.35, speaker: nil)
                }
            }
            transcriptionStatus = "Loaded from cache"
            isTranscribing = false
            isTranscriptIncomplete = checkCompleteness(saved.transcript)
            if summary == nil { summarize(transcript: saved.transcript) }
            return
        }
        isTranscribing = true
        isTranscriptIncomplete = false
        transcriptionStatus = "Connecting to Mac transcription service…"
        Task { await performTranscription() }
    }

    func retranscribe() {
        // Clear existing transcript file
        try? FileManager.default.removeItem(at: transcriptFileURL)
        // Reset state
        summary = nil
        summaryError = nil
        segments = .init()
        isSummarizing = false
        chatMessages = .init()
        chatSessionId = nil
        transcriptContext = nil
        
        // Also remove chat history
        try? FileManager.default.removeItem(at: chatFileURL)
        
        // Start fresh
        isTranscribing = true
        isTranscriptIncomplete = false
        transcriptionStatus = "Re-transcribing via Mac service…"
        Task { await performTranscription(force: true) }
    }

    func continueTranscription() {
        isTranscribing = true
        isTranscriptIncomplete = false
        transcriptionStatus = "Continuing transcription…"
        Task { await performTranscription() }
    }

    // MARK: - Transcription via Mac proxy (mlx-whisper)
    private static let proxyTranscribeURL = URL(string: "http://127.0.0.1:19001/transcribe")!

    struct ProxyTranscriptionResponse: Decodable {
        let transcript: String
        let speaker_segments: [SpeakerSegment]?
        
        struct SpeakerSegment: Decodable {
            let text: String
            let start: Double
            let end: Double
            let speaker: String?
        }
    }

    static func proxyTranscribe(fileURL: URL, force: Bool = false) async throws -> ProxyTranscriptionResponse {
        var req = URLRequest(url: proxyTranscribeURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300
        
        struct ReqBody: Encodable { let filePath: String; let force: Bool }
        req.httpBody = try JSONEncoder().encode(ReqBody(filePath: fileURL.path, force: force))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Proxy error"
            throw NSError(domain: "ASR", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return try JSONDecoder().decode(ProxyTranscriptionResponse.self, from: data)
    }

    private func performTranscription(force: Bool = false) async {
        do {
            await MainActor.run { transcriptionStatus = "Transcribing via Whisper…" }
            
            let resp = try await Self.proxyTranscribe(fileURL: url, force: force)
            let text = resp.transcript.trimmingCharacters(in: .whitespacesAndNewlines)

            var segs: [TranscriptionSegment] = []
            if let speakerSegments = resp.speaker_segments, !speakerSegments.isEmpty {
                // Map Pyannote+Whisper merged segments directly
                segs = speakerSegments.enumerated().map { i, s in
                    TranscriptionSegment(
                        text: s.text,
                        timestamp: s.start,
                        duration: s.end - s.start,
                        speaker: s.speaker
                    )
                }
            } else {
                // Fallback: Build display segments (word-by-word, evenly spread)
                let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                segs  = words.enumerated().map { i, w in
                    TranscriptionSegment(
                        text: w,
                        timestamp: Double(i) * 0.4,
                        duration: 0.35,
                        speaker: nil
                    )
                }
            }

            await MainActor.run {
                self.segments = segs
                self.isTranscribing = false
                self.transcriptionStatus = "Transcription complete"
                self.isTranscriptIncomplete = false
                self.saveTranscript(text, segments: segs)
                if !text.isEmpty { self.summarize(transcript: text) }
                else { self.errorMessage = "No speech detected." }
            }
        } catch {
            await MainActor.run {
                // Proxy unreachable → fall back to on-device SFSpeechRecognizer
                if (error as NSError).code == NSURLErrorCannotConnectToHost ||
                   (error as NSError).code == NSURLErrorTimedOut {
                    self.transcriptionStatus = "Proxy offline — using on-device ASR…"
                    self.fallbackToSFSpeech()
                } else {
                    self.errorMessage = "Mac Proxy Error: \(error.localizedDescription)"
                    self.isTranscribing = false
                }
            }
        }
    }

    /// Fallback: local SFSpeechRecognizer (works without the Mac proxy)
    private func fallbackToSFSpeech() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, status == .authorized else {
                    self?.errorMessage = "Speech recognition not authorized."
                    self?.isTranscribing = false
                    return
                }
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
                      recognizer.isAvailable else {
                    self.errorMessage = "Speech recognizer unavailable."
                    self.isTranscribing = false
                    return
                }
                let request = SFSpeechURLRecognitionRequest(url: self.url)
                request.shouldReportPartialResults = true
                if #available(iOS 16, *) { request.addsPunctuation = true }
                recognizer.recognitionTask(with: request) { [weak self] result, error in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if let result {
                            self.segments = result.bestTranscription.segments.map {
                                TranscriptionSegment(text: $0.substring, timestamp: $0.timestamp, duration: $0.duration, speaker: nil)
                            }
                            if result.isFinal {
                                self.isTranscribing = false
                                self.transcriptionStatus = "Transcription complete"
                                self.saveTranscript(result.bestTranscription.formattedString, segments: self.segments)
                                self.summarize(transcript: result.bestTranscription.formattedString)
                            }
                        }
                        if let error { self.errorMessage = error.localizedDescription; self.isTranscribing = false }
                    }
                }
            }
        }
    }

    // MARK: - AI Summary
    func summarize(transcript: String) {
        guard !isSummarizing, !transcript.isEmpty else { return }
        isSummarizing = true
        summaryError = nil
        summary = nil
        Task {
            do {
                let result = try await OpenClawSummarizer.summarize(
                    transcript: transcript, audioPath: url.path)
                isSummarizing = false
                summary = result
            } catch {
                isSummarizing = false
                summaryError = error.localizedDescription
            }
        }
    }

    // MARK: - Chat with OpenClaw
    @Published var chatMessages: [ChatMessage] = []
    @Published var isSendingChat = false
    private var chatSessionId: String?          // OpenClaw session for this recording
    private var transcriptContext: String?       // cached full text for 1st-turn context

    func sendChatMessage(_ text: String) {
        guard !text.isEmpty else { return }
        chatMessages.append(ChatMessage(role: .user, text: text))
        saveChatHistory()
        isSendingChat = true
        let sessionId  = chatSessionId
        
        let finalMessage: String
        if chatSessionId == nil, let ctx = transcriptContext {
            finalMessage = "以下是一段录音的转录内容，请根据这段内容回答我的问题。\n\n【转录内容】\n\(ctx)\n\n【我的问题】\n\(text)"
        } else {
            finalMessage = text
        }
        
        Task {
            do {
                let reply = try await OpenClawSummarizer.chat(
                    message: finalMessage, useGlobalScope: false, sessionId: sessionId)
                await MainActor.run {
                    chatSessionId = reply.sessionId
                    chatMessages.append(ChatMessage(role: .assistant, text: reply.text))
                    isSendingChat = false
                    saveChatHistory()
                }
            } catch {
                await MainActor.run {
                    chatMessages.append(ChatMessage(role: .assistant, text: "⚠️ \(error.localizedDescription)"))
                    isSendingChat = false
                    saveChatHistory()
                }
            }
        }
    }

    /// Call this after transcript is ready to pre-load context for chat
    func prepareChat(transcript: String) {
        transcriptContext = transcript
    }

    // MARK: - Helpers
    var activeSegmentIndex: Int? {
        let idx = segments.lastIndex(where: { $0.timestamp <= currentTime })
        return idx
    }
}

// MARK: - View
struct RecordingDetailView: View {
    let recording: LocalRecording
    @StateObject private var vm: RecordingDetailViewModel
    @State private var showChat = false
    @State private var isSummaryExpanded = false

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

            if !isSummaryExpanded {
                // ── Karaoke Transcript ───────────────────────────────────────
                transcriptArea

                Divider()

                // ── Full Playback Controls ───────────────────────────────────
                fullPlayer
            } else {
                // ── Mini Playback Controls ───────────────────────────────────
                miniPlayer
                Divider()
            }

            // ── Summary Card ─────────────────────────────────────────────
            summaryCard
                .frame(maxHeight: isSummaryExpanded ? .infinity : 280, alignment: .top)
        }
        .navigationTitle("Voice Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !vm.segments.isEmpty && !vm.isTranscribing {
                    Button("重新转译") {
                        vm.retranscribe()
                    }
                    .font(.subheadline)
                }
            }
        }
        .sheet(isPresented: $showChat) {

            ChatSheetView(vm: vm)
        }
        .onAppear {
            vm.startTranscription()
        }
        .onDisappear {
            vm.stop()
        }
    }

    // MARK: - Components
    @ViewBuilder
    private var transcriptArea: some View {
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
                // Karaoke transcript with word highlighting
                VStack(spacing: 0) {
                    // Incomplete-transcript banner
                    if vm.isTranscriptIncomplete {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("转录可能不完整")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("继续转译") { vm.continueTranscription() }
                                .font(.caption).buttonStyle(.borderedProminent)
                                .tint(.orange)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        Divider()
                    }
                    if vm.isTranscribing {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text(vm.transcriptionStatus)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    KaraokeTextView(
                        segments: vm.segments,
                        activeIndex: vm.activeSegmentIndex
                    ) { tappedIndex in
                        vm.seek(to: vm.segments[tappedIndex].timestamp)
                        if !vm.isPlaying { vm.togglePlayback() }
                    }
                }
            }
        }
        .padding(.horizontal)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var fullPlayer: some View {
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

        HStack(spacing: 32) {
            Button { vm.seekRelative(-10) } label: { Image(systemName: "gobackward.10").font(.title2) }
            Button { vm.togglePlayback() } label: {
                Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
            }
            Button { vm.seekRelative(10) } label: { Image(systemName: "goforward.10").font(.title2) }
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var miniPlayer: some View {
        HStack(spacing: 12) {
            Button { vm.togglePlayback() } label: {
                Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
            Slider(value: Binding(
                get: { vm.currentTime },
                set: { vm.seek(to: $0) }
            ), in: 0...max(vm.duration, 1))
            Text(formatTime(vm.currentTime))
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - AI Summary Card
    @ViewBuilder
    private var summaryCard: some View {
        if vm.isSummarizing || vm.summary != nil || vm.summaryError != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.purple)
                        .clipShape(Circle())
                    Text("AI 总结")
                        .font(.headline).fontWeight(.bold)
                    Spacer()
                    if vm.isSummarizing {
                        ProgressView().scaleEffect(0.8)
                    } else if vm.summary != nil {
                        Button {
                            // Seed context if not already set
                            let transcript = vm.segments.map(\.text).joined(separator: " ")
                            vm.prepareChat(transcript: transcript)
                            showChat = true
                        } label: {
                            Label("继续聊", systemImage: "sparkles")
                                .font(.caption).fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.mini)
                        
                        // Expand/Collapse Toggle
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSummaryExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isSummaryExpanded ? "chevron.down" : "chevron.up")
                                .font(.subheadline).bold()
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(Color(UIColor.tertiarySystemFill))
                                .clipShape(Circle())
                        }
                        .padding(.leading, 4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if vm.summary != nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSummaryExpanded.toggle()
                        }
                    }
                }

                if vm.isSummarizing {
                    Text("OpenClaw 正在处理…")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let summary = vm.summary {
                    ScrollView {
                        Group {
                            if let attr = try? AttributedString(
                                markdown: summary,
                                options: AttributedString.MarkdownParsingOptions(
                                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                                )
                            ) {
                                Text(attr)
                            } else {
                                Text(summary)
                            }
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                    .frame(maxHeight: .infinity)
                } else if let err = vm.summaryError {
                    HStack {
                        Text("❌ \(err)")
                            .font(.caption).foregroundStyle(.red)
                        Spacer()
                        Button("重试") {
                            let full = vm.segments.map { $0.text }.joined(separator: " ")
                            vm.summarize(transcript: full)
                        }
                        .font(.caption).buttonStyle(.bordered)
                    }
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 8, y: -2)
            .padding([.horizontal, .bottom], 12)
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Karaoke word-highlight view (Groups by Speaker)
struct KaraokeTextView: View {
    let segments: [TranscriptionSegment]
    let activeIndex: Int?
    let onTap: (Int) -> Void
    
    // Group segments by speaker blocks to render them with labels
    // We store the global index so we can still highlight correctly
    struct SpeakerBlock: Identifiable {
        let id = UUID()
        let speakerName: String
        var words: [(globalIndex: Int, segment: TranscriptionSegment)]
    }
    
    private var speakerBlocks: [SpeakerBlock] {
        var blocks: [SpeakerBlock] = []
        var currentBlock: SpeakerBlock?
        
        for (i, seg) in segments.enumerated() {
            let spk = seg.speaker ?? "说话人"
            if currentBlock?.speakerName == spk {
                currentBlock?.words.append((i, seg))
            } else {
                if let cb = currentBlock { blocks.append(cb) }
                currentBlock = SpeakerBlock(speakerName: spk, words: [(i, seg)])
            }
        }
        if let cb = currentBlock { blocks.append(cb) }
        return blocks
    }

    private func attributedString(for words: [(globalIndex: Int, segment: TranscriptionSegment)]) -> AttributedString {
        var result = AttributedString()
        for (idx, item) in words.enumerated() {
            var word = AttributedString(item.segment.text)
            let gIdx = item.globalIndex
            if gIdx == activeIndex {
                word.foregroundColor = .systemBlue
                word.font = UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize)
            } else if let active = activeIndex, gIdx < active {
                word.foregroundColor = .secondaryLabel
            } else {
                word.foregroundColor = .label
            }
            result += word
            if idx < words.count - 1 {
                var space = AttributedString("\n")
                space.foregroundColor = .clear
                space.font = .system(size: 8)
                result += space
            }
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(speakerBlocks) { block in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.speakerName)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(UIColor.tertiarySystemFill))
                                .clipShape(Capsule())
                            
                            Text(attributedString(for: block.words))
                                .font(.body)
                                .lineSpacing(6)
                                .onTapGesture {
                                    // Optionally: tap on a block could jump to its first word
                                    if let first = block.words.first {
                                        onTap(first.globalIndex)
                                    }
                                }
                        }
                        .id("block-\(block.words.first?.globalIndex ?? 0)")
                    }
                    
                    // Invisible anchor at the active position for auto-scroll
                    if let idx = activeIndex, idx < segments.count {
                        Color.clear.frame(height: 0).id("active")
                    }
                }
                .padding(.vertical, 12)
                .animation(.easeInOut(duration: 0.15), value: activeIndex)
            }
            .onChange(of: activeIndex) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("active", anchor: .center)
                }
            }
        }
    }
}
