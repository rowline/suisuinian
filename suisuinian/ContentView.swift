import SwiftUI
import AppIntents



struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var recordingManager = RecordingManager()
    @State private var reports: [DailyReport] = []
    
    @State private var isLoadingReports = false
    @State private var viewMode = 1 // default to Recordings
    @State private var searchText = ""
    @State private var isPTTActive = false
    @State private var initialVoiceText: String? = nil
    @State private var showGlobalChat = false
    
    @Environment(\.scenePhase) private var scenePhase
    
    private var reportsURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("DailyReports")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack {
                    Picker("View Mode", selection: $viewMode) {
                        Text("Daily Reports").tag(0)
                        Text("Recordings").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if viewMode == 0 {
                        reportsView
                    } else {
                        recordingsView
                    }
                    
                    bottomControlBar
                }
            }
            .navigationTitle("碎碎念")
            .sheet(isPresented: $showGlobalChat, onDismiss: { initialVoiceText = nil }) {
                GlobalChatView(initialText: initialVoiceText)
            }
            .onAppear {
                recordingManager.fetchRecordings()
                loadSavedReports()
                Task { await fetchLatestReport() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    recordingManager.fetchRecordings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newWatchRecordingArrived)) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    recordingManager.fetchRecordings()
                }
            }
        }
    }

    // MARK: - Subviews
    private var reportsView: some View {
        Group {
            if isLoadingReports {
                Spacer()
                ProgressView("Generating Today's AI Report...")
                Spacer()
            } else if reports.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Reports Yet",
                    systemImage: "doc.text.image",
                    description: Text("Provide some recordings today to generate a daily report.")
                )
                Button("Generate Now") { Task { await fetchLatestReport() } }
                    .buttonStyle(.bordered)
                Spacer()
            } else {
                List(reports) { report in
                    NavigationLink(destination: ReportDetailView(report: report)) {
                        VStack(alignment: .leading) {
                            Text(report.date, style: .date)
                                .font(.headline)
                            Text("AI Generated Summary")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .refreshable { await fetchLatestReport() }
            }
        }
    }
    
    private var recordingsView: some View {
        Group {
            if recordingManager.recordings.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "mic.slash",
                    description: Text("Voice notes you capture will appear here.")
                )
                Spacer()
            } else {
                List {
                    ForEach(recordingManager.recordings, id: \.url) { recording in
                        NavigationLink(destination: RecordingDetailView(recording: recording)) {
                            VStack(alignment: .leading) {
                                Text(recording.date, style: .date)
                                    .font(.headline)
                                Text("\(recording.date, style: .time) • \(recording.size)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            recordingManager.delete(recording: recordingManager.recordings[index])
                        }
                    }
                }
                .refreshable { recordingManager.fetchRecordings() }
            }
        }
    }
    
    private var bottomControlBar: some View {
        VStack(spacing: 8) {
            if isPTTActive {
                Text("正在倾听，松开即搜...")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .transition(.opacity)
            }
            
            HStack(spacing: 12) {
                // 1. Text Search Input
                TextField("问问你的大脑...", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(20)
                    .onSubmit {
                        guard !searchText.isEmpty else { return }
                        initialVoiceText = searchText
                        searchText = ""
                        showGlobalChat = true
                    }
                
                // 2. Center Mic (Push to Talk)
                Button(action: {}) {
                    ZStack {
                        Circle()
                            .fill(isPTTActive ? Color.blue : Color.primary.opacity(0.1))
                            .frame(width: 50, height: 50)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(isPTTActive ? .white : .primary)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isPTTActive {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                isPTTActive = true
                                audioRecorder.startRecording()
                            }
                        }
                        .onEnded { _ in
                            isPTTActive = false
                            audioRecorder.stopRecording()
                            // Trigger Handoff
                            handleVoiceSearchHandoff()
                        }
                )
                
                // 3. Long Recording Button
                Button(action: {
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            recordingManager.fetchRecordings()
                        }
                    } else {
                        audioRecorder.startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(audioRecorder.isRecording ? Color.red : Color.primary.opacity(0.05))
                            .frame(width: 44, height: 44)
                        Image(systemName: audioRecorder.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 20))
                            .foregroundColor(audioRecorder.isRecording ? .white : .red)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 10)
        .padding(.bottom, 25) // Better spacing for home indicator
        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
        .background(.ultraThinMaterial)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: -2)
    }
    
    // Bridge logic: Transcribe the short PTT audio and feed to chat
    private func handleVoiceSearchHandoff() {
        guard let url = audioRecorder.latestRecordingURL else { return }
        
        Task {
            do {
                // Use the proxy to transcribe this specifically
                let result = try await RecordingDetailViewModel.proxyTranscribe(fileURL: url)
                if !result.transcript.isEmpty {
                    await MainActor.run {
                        self.initialVoiceText = result.transcript
                        self.showGlobalChat = true
                    }
                }
            } catch {
                print("PTT Transcription failed: \(error)")
            }
        }
    }


    // MARK: - Data Fetching
    func fetchLatestReport() async {
        // 0. Check if we already have a report for today
        if let existing = reports.first(where: { Calendar.current.isDateInToday($0.date) }) {
            print("📅 Found existing report for today: \(existing.id)")
            return 
        }

        isLoadingReports = true
        
        // 1. Find all transcripts from today
        let transcripts = fetchLocalTranscripts(forTodayOnly: true)
        if transcripts.isEmpty {
            isLoadingReports = false
            return
        }
        
        do {
            let df = DateFormatter()
            df.dateStyle = .long
            let summary = try await OpenClawSummarizer.dailySummarize(
                transcripts: transcripts,
                dateString: df.string(from: Date())
            )
            let newReport = DailyReport(date: Date(), markdownContent: summary)
            reports.insert(newReport, at: 0)
            saveReport(newReport)
        } catch {
            print("Could not generate daily report: \(error)")
        }
        isLoadingReports = false
    }
    
    private func fetchLocalTranscripts(forTodayOnly: Bool) -> [String] {
        let docsURL = AppGroupContainer.recordingsURL
        
        guard let docs = try? FileManager.default.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        
        var results: [String] = []
        for url in docs where url.pathExtension == "transcript" {
            if forTodayOnly {
                // Check if the file was created today
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let cDate = attrs[.creationDate] as? Date {
                    if !Calendar.current.isDateInToday(cDate) { continue }
                }
            }
            
            if let data = try? Data(contentsOf: url) {
                if let decoded = try? JSONDecoder().decode(RecordingDetailViewModel.SavedTranscript.self, from: data) {
                    results.append(decoded.transcript)
                } else if let txt = String(data: data, encoding: .utf8) {
                    results.append(txt)
                }
            }
        }
        return results
    }
    
    private func saveReport(_ report: DailyReport) {
        let filename = "report_\(report.id.uuidString).json"
        let url = reportsURL.appendingPathComponent(filename)
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: url)
        }
    }
    
    private func loadSavedReports() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: reportsURL, includingPropertiesForKeys: [.creationDateKey]) else { return }
        
        var loaded: [DailyReport] = []
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let report = try? JSONDecoder().decode(DailyReport.self, from: data) {
                loaded.append(report)
            }
        }
        self.reports = loaded.sorted(by: { $0.date > $1.date })
    }
}

// MARK: - Report Details
struct ReportDetailView: View {
    let report: DailyReport
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(LocalizedStringKey(report.markdownContent))
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Daily Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = report.markdownContent
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}

// MARK: - Global Chat View
struct GlobalChatView: View {
    @Environment(\.dismiss) var dismiss
    var initialText: String? = nil
    
    @State private var chatMessages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var sessionId: String?
    
    // Persistence path for global chat
    private var chatHistoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("global_chat_history.json")
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hi! I have read all your historical voice notes across time.\nAsk me anything about your past reflections, meetings, or ideas!")
                            .font(.subheadline)
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(12)
                            .padding()

                        ForEach(chatMessages) { msg in
                            HStack {
                                if msg.role == .user { Spacer() }
                                
                                Group {
                                    if let attr = try? AttributedString(markdown: msg.text) {
                                        Text(attr)
                                    } else {
                                        Text(msg.text)
                                    }
                                }
                                .padding(12)
                                .background(msg.role == .user ? Color.blue : Color(UIColor.secondarySystemBackground))
                                .foregroundColor(msg.role == .user ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .textSelection(.enabled)
                                
                                if msg.role == .assistant { Spacer() }
                            }
                            .padding(.horizontal)
                        }
                        
                        if isSending {
                            HStack {
                                ProgressView()
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 20)
                }
                
                Divider()
                HStack {
                    TextField("Ask your Brain anything...", text: $inputText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                    
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                }
                .padding()
                .background(Color(UIColor.systemBackground))
            }
            .navigationTitle("Global Brain Chat")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .onAppear {
                loadHistory()
                if let t = initialText, !t.isEmpty {
                    inputText = t
                    send()
                }
            }
        }
    }
    
    private func prepareGlobalContext() {
        // Obsolete: We now rely on the Mac proxy pointing OpenClaw to the restricted knowledge folder.
        // No need to send massive context text over the local network via JSON anymore!
    }
    
    // Save history to disk
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(chatMessages) {
            try? data.write(to: chatHistoryURL)
        }
        // Also save SessionId manually so the conversation continues properly across app launches
        UserDefaults.standard.set(sessionId, forKey: "GlobalChatSessionId")
    }

    // Load history from disk
    private func loadHistory() {
        if let data = try? Data(contentsOf: chatHistoryURL),
           let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            self.chatMessages = saved
        }
        self.sessionId = UserDefaults.standard.string(forKey: "GlobalChatSessionId")
    }
    
    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        chatMessages.append(ChatMessage(role: .user, text: text))
        saveHistory()
        
        inputText = ""
        isSending = true
        
        // Only use global scope if it's the very first message
        let scope = sessionId == nil ? true : nil
        let s = sessionId
        
        Task {
            do {
                let reply = try await OpenClawSummarizer.chat(message: text, useGlobalScope: scope, sessionId: s)
                await MainActor.run {
                    self.sessionId = reply.sessionId
                    self.chatMessages.append(ChatMessage(role: .assistant, text: reply.text))
                    self.isSending = false
                    self.saveHistory()
                }
            } catch {
                await MainActor.run {
                    self.chatMessages.append(ChatMessage(role: .assistant, text: "Error: \(error.localizedDescription)"))
                    self.isSending = false
                    self.saveHistory()
                }
            }
        }
    }
}
