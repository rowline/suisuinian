import Foundation
import Combine

struct LocalRecording: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let date: Date
    let size: String
    
    var name: String {
        url.lastPathComponent
    }
}

@MainActor
class RecordingManager: ObservableObject {
    @Published var recordings: [LocalRecording] = []
    
    func fetchRecordings() {
        let documentPath = AppGroupContainer.recordingsURL
        print("🔍 fetchRecordings reading: \(documentPath.path)")
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: documentPath,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            let m4aFiles = files.filter { $0.pathExtension.lowercased() == "m4a" }
            print("🎵 Found \(m4aFiles.count) m4a file(s) out of \(files.count) total")

            var fetched: [LocalRecording] = []
            for url in m4aFiles {
                let attr = try FileManager.default.attributesOfItem(atPath: url.path)
                let date = attr[.creationDate] as? Date ?? Date()
                let sizeInt = attr[.size] as? Int64 ?? 0
                let sizeStr = ByteCountFormatter.string(fromByteCount: sizeInt, countStyle: .file)
                fetched.append(LocalRecording(id: UUID(), url: url, date: date, size: sizeStr))
            }

            self.recordings = fetched.sorted(by: { $0.date > $1.date })
            print("✅ recordings updated: \(self.recordings.count) items")
        } catch {
            print("❌ Failed to fetch local recordings: \(error)")
        }
    }
    
    func delete(recording: LocalRecording) {
        do {
            try FileManager.default.removeItem(at: recording.url)
            fetchRecordings()
        } catch {
            print("❌ Failed to delete recording: \(error)")
        }
    }
}
