import Foundation
import BackgroundTasks

/// Handles background uploads of recorded audio files to the Cloud Brain
class BackgroundUploader {
    
    /// Called from AppDelegate or App structure when the app launches
    static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.rollin.suisuinian.audioupload", using: nil) { task in
            let uploader = BackgroundUploader()
            Task {
                await uploader.handleAppRefresh(task: task as! BGAppRefreshTask)
            }
        }
    }
    
    /// Schedules the next background upload
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.rollin.suisuinian.audioupload")
        // Require network connectivity to upload audio files
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 mins
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \\(error)")
        }
    }
    
    /// Handles the execution of the BGTask
    func handleAppRefresh(task: BGAppRefreshTask) async {
        // Schedule the next one right away
        BackgroundUploader.scheduleAppRefresh()
        
        // Prevent the OS from killing the task if we take too long
        task.expirationHandler = {
            // Cancel any ongoing URLSession uploads
        }
        
        await performUpload()
        task.setTaskCompleted(success: true)
    }

    func performUpload() async {
        do {
            let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            // In a real app, query CoreData or File System for un-uploaded files
            let contents = try FileManager.default.contentsOfDirectory(at: documentPath, includingPropertiesForKeys: nil)
            
            for fileURL in contents where fileURL.pathExtension == "m4a" { // Filter for our custom files
                let success = try await NetworkManager.shared.uploadAudioFile(at: fileURL)
                if success {
                    // Delete local file after upload
                    try FileManager.default.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Background upload failed: \\(error)")
        }
    }
}
