import Foundation
import Network
import os

// Bounded persistent event log for diagnosing intermittent canvas freezes.
// Writes append-only JSONL session files to {AppDocuments}/mb_diagnostics/.
// Each launch gets a new session file, so repeated restarts do not overwrite
// earlier freeze evidence. A combined human-readable export is regenerated at
// {AppDocuments}/mb_diagnostics_export.txt for the in-app ShareLink.
// No student PII — logs structural state only
// (tool names, slide indices, widget types, gesture transitions, errors).
//
// Usage from any context:
//   MBDiagnosticLogger.emit("Tool", "switched to text")
//   MBDiagnosticLogger.emit("Widget", "interactionBegan", extra: ["type": "trivialPursuit"])
//
// Export: call `await MBDiagnosticLogger.shared.exportText()` or share
// `MBDiagnosticLogger.shared.logFileURL`.
public actor MBDiagnosticLogger {
    public static let shared = MBDiagnosticLogger()

    private let osLogger = Logger(subsystem: "com.mathboard.MathBoard", category: "CanvasDiag")
    public nonisolated let diagnosticsDirectoryURL: URL
    public nonisolated let logFileURL: URL
    public nonisolated let currentSessionLogFileURL: URL
    public nonisolated let sessionID: String
    private var pendingExportRefresh: Task<Void, Never>?

    private struct LogEntry: Codable, Sendable {
        let t: Double
        let sid: String?
        let cat: String
        let msg: String
        var ext: [String: String]?
    }

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = docs.appendingPathComponent("mb_diagnostics", isDirectory: true)
        diagnosticsDirectoryURL = directory
        logFileURL = docs.appendingPathComponent("mb_diagnostics_export.txt")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let launchStamp = formatter.string(from: Date())
        let launchID = UUID().uuidString
        sessionID = "\(launchStamp)-\(launchID)"
        currentSessionLogFileURL = directory.appendingPathComponent("mb_diagnostics-\(sessionID).jsonl")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: currentSessionLogFileURL.path) {
            FileManager.default.createFile(atPath: currentSessionLogFileURL.path, contents: nil)
        }
    }

    /// Fire-and-forget — safe to call from any synchronous context.
    public static func emit(_ category: String, _ message: String, extra: [String: String]? = nil) {
        Task { await shared.append(category: category, message: message, extra: extra) }
    }

    private func append(category: String, message: String, extra: [String: String]?) {
        let entry = LogEntry(
            t: Date().timeIntervalSince1970,
            sid: sessionID,
            cat: category,
            msg: message,
            ext: extra
        )
        if let ext = extra, !ext.isEmpty {
            let extStr = ext.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
            osLogger.info("[\(category)] \(message) | \(extStr)")
        } else {
            osLogger.info("[\(category)] \(message)")
        }

        persist(entry)
        scheduleExportRefresh()
    }

    private func persist(_ entry: LogEntry) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(entry) else { return }
        var line = data
        line.append(0x0A)

        if let handle = try? FileHandle(forWritingTo: currentSessionLogFileURL) {
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } catch {
                try? handle.close()
            }
        } else {
            try? line.write(to: currentSessionLogFileURL, options: .atomic)
        }
    }

    private func scheduleExportRefresh() {
        pendingExportRefresh?.cancel()
        pendingExportRefresh = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            refreshExportFile()
        }
    }

    private func loadPersistedEntries() -> [LogEntry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: diagnosticsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        return urls
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { url -> [LogEntry] in
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) else {
                    return []
                }
                return text
                    .split(separator: "\n")
                    .compactMap { try? decoder.decode(LogEntry.self, from: Data($0.utf8)) }
            }
            .sorted { $0.t < $1.t }
    }

    private func refreshExportFile() {
        let text = formattedExportText()
        try? text.data(using: .utf8)?.write(to: logFileURL, options: .atomic)
    }

    private func formattedExportText() -> String {
        let fmt = ISO8601DateFormatter()
        return loadPersistedEntries().map { e in
            let ts = fmt.string(from: Date(timeIntervalSince1970: e.t))
            let sid = e.sid.map { " [session=\($0)]" } ?? ""
            var line = "[\(ts)]\(sid) [\(e.cat)] \(e.msg)"
            if let ext = e.ext, !ext.isEmpty {
                line += " | " + ext.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
            }
            return line
        }.joined(separator: "\n")
    }

    /// Flush pending writes immediately and return human-readable log text.
    public func exportText() -> String {
        refreshExportFile()
        return (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
    }

    /// Immediately flush without waiting for the debounce timer.
    public func flushNow() {
        pendingExportRefresh?.cancel()
        refreshExportFile()
    }
}

@MainActor
public final class MBDiagnosticRuntimeMonitor {
    public static let shared = MBDiagnosticRuntimeMonitor()

    private var hasStarted = false
    private var mainThreadTimer: Timer?
    private var lastMainThreadTick = Date()
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.mathboard.diagnostics.network")

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true

        MBDiagnosticLogger.emit("App", "launched", extra: [
            "session": MBDiagnosticLogger.shared.sessionID
        ])

        startMainThreadWatchdog()
        startNetworkMonitor()
    }

    private func startMainThreadWatchdog() {
        lastMainThreadTick = Date()
        mainThreadTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                MBDiagnosticRuntimeMonitor.shared.recordMainThreadTick()
            }
        }
    }

    private func recordMainThreadTick() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastMainThreadTick)
        if elapsed > 2.0 {
            MBDiagnosticLogger.emit("MainThread", "stallDetected", extra: [
                "seconds": String(format: "%.2f", elapsed)
            ])
        }
        lastMainThreadTick = now
    }

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { path in
            var extra: [String: String] = [
                "status": path.status.diagnosticName,
                "expensive": "\(path.isExpensive)",
                "constrained": "\(path.isConstrained)"
            ]
            if !path.availableInterfaces.isEmpty {
                extra["interfaces"] = path.availableInterfaces
                    .map(\.type.diagnosticName)
                    .sorted()
                    .joined(separator: ",")
            }
            MBDiagnosticLogger.emit("Network", "pathChanged", extra: extra)
        }
        networkMonitor.start(queue: networkQueue)
    }
}

private extension NWPath.Status {
    var diagnosticName: String {
        switch self {
        case .satisfied:
            return "satisfied"
        case .unsatisfied:
            return "unsatisfied"
        case .requiresConnection:
            return "requiresConnection"
        @unknown default:
            return "unknown"
        }
    }
}

private extension NWInterface.InterfaceType {
    var diagnosticName: String {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .wiredEthernet:
            return "wiredEthernet"
        case .loopback:
            return "loopback"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }
}
