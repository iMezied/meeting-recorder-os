import Foundation
import os

/// Centralized logging for the MeetingRecorder app.
/// Logs to both Xcode console and a persistent log file for easy tracing.
enum AppLogger {

    enum Category: String {
        case audio = "Audio"
        case detector = "Detector"
        case transcription = "Transcription"
        case ai = "AI"
        case storage = "Storage"
        case ui = "UI"
        case notes = "Notes"
        case app = "App"
    }

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let logFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logsDir = appSupport.appendingPathComponent("MeetingRecorder/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let fileName = "meeting-recorder-\(dayFormatter.string(from: Date())).log"
        return logsDir.appendingPathComponent(fileName)
    }()

    static func debug(_ message: String, category: Category) {
        log(message, level: .debug, category: category)
    }

    static func info(_ message: String, category: Category) {
        log(message, level: .info, category: category)
    }

    static func warning(_ message: String, category: Category) {
        log(message, level: .warning, category: category)
    }

    static func error(_ message: String, category: Category) {
        log(message, level: .error, category: category)
    }

    private static func log(_ message: String, level: Level, category: Category) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(message)"

        // Console output
        print(line)

        // File output (append)
        let lineWithNewline = line + "\n"
        if let data = lineWithNewline.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }

    /// Returns the path to today's log file
    static var logFilePath: String {
        logFileURL.path
    }
}
