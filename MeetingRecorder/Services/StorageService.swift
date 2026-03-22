import Foundation

final class StorageService {

    private let baseDir: URL
    private let meetingsIndexFile: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        baseDir = appSupport.appendingPathComponent("MeetingRecorder", isDirectory: true)
        meetingsIndexFile = baseDir.appendingPathComponent("meetings.json")

        let dirs = [
            baseDir,
            baseDir.appendingPathComponent("recordings"),
            baseDir.appendingPathComponent("models")
        ]

        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Directory Management

    func createMeetingDirectory(source: MeetingSource) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmm"
        let timeStr = timeFormatter.string(from: Date())

        let dirName = "\(source.rawValue)-\(timeStr)"
        let dir = baseDir
            .appendingPathComponent("recordings")
            .appendingPathComponent(dateStr)
            .appendingPathComponent(dirName)

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var recordingsDir: URL {
        baseDir.appendingPathComponent("recordings")
    }

    var modelsDirectory: URL {
        baseDir.appendingPathComponent("models")
    }

    // MARK: - Meeting CRUD

    func saveMeeting(_ meeting: Meeting) {
        var all = loadAllMeetings()
        if let index = all.firstIndex(where: { $0.id == meeting.id }) {
            all[index] = meeting
        } else {
            all.insert(meeting, at: 0)
        }
        saveMeetingsList(all)
    }

    func loadAllMeetings() -> [Meeting] {
        guard FileManager.default.fileExists(atPath: meetingsIndexFile.path) else { return [] }
        do {
            let data = try Data(contentsOf: meetingsIndexFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Meeting].self, from: data)
        } catch {
            print("[Storage] Failed to load meetings: \(error)")
            return []
        }
    }

    func deleteMeeting(_ meeting: Meeting) {
        let dir = meeting.directoryURL
        try? FileManager.default.removeItem(at: dir)

        let parentDir = dir.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: parentDir.path)) ?? []
        if contents.isEmpty {
            try? FileManager.default.removeItem(at: parentDir)
        }

        var all = loadAllMeetings()
        all.removeAll { $0.id == meeting.id }
        saveMeetingsList(all)
    }

    // MARK: - Transcript

    func saveTranscript(_ transcript: Transcript, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(transcript)
        try data.write(to: url, options: .atomic)
    }

    func loadTranscript(from path: String) -> Transcript? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Transcript.self, from: data)
        } catch {
            print("[Storage] Failed to load transcript: \(error)")
            return nil
        }
    }

    // MARK: - Summary & Sentiment

    func saveSummary(_ summary: MeetingSummary, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: url, options: .atomic)
    }

    func loadSummary(from path: String) -> MeetingSummary? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MeetingSummary.self, from: data)
        } catch {
            print("[Storage] Failed to load summary: \(error)")
            return nil
        }
    }

    func saveSentiment(_ sentiment: MeetingSentiment, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sentiment)
        try data.write(to: url, options: .atomic)
    }

    func loadSentiment(from path: String) -> MeetingSentiment? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MeetingSentiment.self, from: data)
        } catch {
            print("[Storage] Failed to load sentiment: \(error)")
            return nil
        }
    }

    // MARK: - Notes

    func saveNotes(_ notes: String, to url: URL) throws {
        try notes.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadNotes(from path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    // MARK: - Disk Usage

    func totalStorageUsed() -> Int64 {
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: recordingsDir,
            includingPropertiesForKeys: Array(resourceKeys)
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else { continue }
            totalSize += Int64(values.fileSize ?? 0)
        }
        return totalSize
    }

    func formattedStorageUsed() -> String {
        let bytes = totalStorageUsed()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Private

    private func saveMeetingsList(_ meetings: [Meeting]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(meetings)
            try data.write(to: meetingsIndexFile, options: .atomic)
        } catch {
            print("[Storage] Failed to save meetings index: \(error)")
        }
    }
}
