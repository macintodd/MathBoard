import Canvas
import Foundation

public enum MathBoardDiagnostics {
    @MainActor
    public static func startRuntimeMonitoring() {
        MBDiagnosticRuntimeMonitor.shared.start()
    }

    public static func emit(_ category: String, _ message: String, extra: [String: String]? = nil) {
        MBDiagnosticLogger.emit(category, message, extra: extra)
    }
}
