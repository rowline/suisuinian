import Foundation
import CoreMotion

/// Optional experimental manager to start listening when the user raises their wrist
/// Requires specific background modes and user permissions on watchOS
class MotionTriggerManager {
    static let shared = MotionTriggerManager()
    private let motionManager = CMMotionManager()
    
    private init() {}
    
    func startMonitoring() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.deviceMotionUpdateInterval = 0.5
        motionManager.startDeviceMotionUpdates(to: .main) { (motion, error) in
            guard let motion = motion else { return }
            
            // Detect classic "wrist raise" pattern
            let attitude = motion.attitude
            if attitude.roll > 1.0 && attitude.pitch > 0.5 {
                // Potential wrist raise detected
                // Prompt user to record via complications or trigger audio safely
                print("Wrist Raise detected!")
            }
        }
    }
    
    func stopMonitoring() {
        motionManager.stopDeviceMotionUpdates()
    }
}
