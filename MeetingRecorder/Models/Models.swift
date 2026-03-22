import Foundation

// MARK: - Meeting

struct Meeting: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let source: MeetingSource
    let duration: TimeInterval
    let audioPath: String
    var transcriptPath: String?
    var summaryPath: String?
    var sentimentPath: String?
    var notesPath: String?
    var status: MeetingStatus
    var title: String?

    var displayTitle: String {
        if let title { return title }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return "\(source.displayName) — \(formatter.string(from: date))"
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var directoryURL: URL {
        URL(fileURLWithPath: audioPath).deletingLastPathComponent()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Meeting, rhs: Meeting) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Meeting Source

enum MeetingSource: String, Codable, CaseIterable {
    case zoom = "zoom"
    case googleMeet = "google_meet"
    case teams = "teams"
    case manual = "manual"

    var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .googleMeet: return "Google Meet"
        case .teams: return "Teams"
        case .manual: return "Manual"
        }
    }

    var iconName: String {
        switch self {
        case .zoom: return "video.fill"
        case .googleMeet: return "globe"
        case .teams: return "person.3.fill"
        case .manual: return "mic.fill"
        }
    }
}

// MARK: - Meeting Status

enum MeetingStatus: Codable, Equatable {
    case recording
    case recorded
    case transcribing
    case transcribed
    case summarized
    case failed(String)

    var displayText: String {
        switch self {
        case .recording: return "Recording"
        case .recorded: return "Recorded"
        case .transcribing: return "Transcribing..."
        case .transcribed: return "Transcribed"
        case .summarized: return "Summarized"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }
}

// MARK: - Transcript

struct Transcript: Codable {
    let segments: [TranscriptSegment]
    let language: String
    let modelUsed: String
    let processedAt: Date

    var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }

    var formattedText: String {
        segments.map { segment in
            let timestamp = formatTimestamp(segment.startTime)
            return "[\(timestamp)] \(segment.text)"
        }.joined(separator: "\n")
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct TranscriptSegment: Codable, Identifiable {
    var id: Int { index }
    let index: Int
    let startTime: Double
    let endTime: Double
    let text: String
    let language: String?
    let speaker: String?
}

// MARK: - Meeting Summary

struct MeetingSummary: Codable {
    let summary: String
    let keyPoints: [String]
    let actionItems: [ActionItem]
    let decisions: [String]
    let generatedAt: Date
}

struct ActionItem: Codable, Identifiable {
    var id: String { description }
    let description: String
    let assignee: String?
}

// MARK: - Meeting Sentiment

struct MeetingSentiment: Codable {
    let overallTone: String
    let speakers: [SpeakerSentiment]
    let dynamics: [String]
    let generatedAt: Date
}

struct SpeakerSentiment: Codable, Identifiable {
    var id: String { speaker }
    let speaker: String
    let style: String
    let sentiment: String
    let engagement: String
}

// MARK: - Audio Device

struct AudioDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isInput: Bool
    let isDefault: Bool
}
