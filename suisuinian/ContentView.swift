import SwiftUI
import AppIntents

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var recordingManager = RecordingManager()
    @State private var reports: [DailyReport] = []
    @State private var isLoadingReports = false
    @State private var viewMode = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack {
                Picker("View Mode", selection: $viewMode) {
                    Text("Reports").tag(0)
                    Text("Local Recordings").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if viewMode == 0 {
                    if isLoadingReports {
                        Spacer()
                        ProgressView("Loading Daily Report...")
                        Spacer()
                    } else if reports.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "No Reports Yet",
                            systemImage: "doc.text.image",
                            description: Text("Your Daily Suisuinian Report will appear here when ready.")
                        )
                        Spacer()
                    } else {
                        List(reports) { report in
                            NavigationLink(destination: ReportDetailView(report: report)) {
                                VStack(alignment: .leading) {
                                    Text("Report: \\(report.date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.headline)
                                    Text("\\(report.extractedTasks.count) action items found")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    if recordingManager.recordings.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "No Recordings",
                            systemImage: "mic.slash",
                            description: Text("Voice notes you capture will appear here pending synchronization.")
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
                        .refreshable {
                            recordingManager.fetchRecordings()
                        }
                    }
                }
                
                // Manual capture button (Fallback if Action Button is not available)
                Button(action: {
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording()
                        // Refresh exactly after stop finishes saving and syncing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            recordingManager.fetchRecordings()
                        }
                    } else {
                        audioRecorder.startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(audioRecorder.isRecording ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: audioRecorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 30)
                
                Text(audioRecorder.isRecording ? "Listening..." : "Tap to record or use Action Button")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("碎碎念 Brain")
            .onAppear {
                recordingManager.fetchRecordings()
                Task { await fetchLatestReport() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    // Refresh every time app comes to foreground (picks up Watch-synced files)
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

    // Move viewMode here so it lives with the other state vars above
    // Simulates fetching a report
    func fetchLatestReport() async {
        isLoadingReports = true
        do {
            let report = try await NetworkManager.shared.fetchDailyReport()
            reports = [report]
        } catch {
            print("Could not fetch reports: \(error)")
        }
        isLoadingReports = false
    }
}

struct ReportDetailView: View {
    let report: DailyReport
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(report.markdownContent)
                    .padding()
                
                if !report.extractedTasks.isEmpty {
                    Text("Action Items")
                        .font(.title2).bold()
                        .padding(.horizontal)
                    
                    ForEach(report.extractedTasks) { task in
                        HStack {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(task.isCompleted ? .green : .gray)
                            Text(task.title)
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .navigationTitle(report.date.formatted(date: .abbreviated, time: .omitted))
    }
}

#Preview {
    ContentView()
}
