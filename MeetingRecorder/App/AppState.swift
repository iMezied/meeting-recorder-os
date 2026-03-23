import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: - Recording State
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var currentMeetingSource: MeetingSource = .manual
    @Published var recordingLevel: Float = 0.0

    // MARK: - Processing State
    @Published var isTranscribing = false
    @Published var transcriptionProgress: Double = 0.0
    @Published var isSummarizing = false
    @Published var isAnalyzingSentiment = false

    // MARK: - Data
    @Published var meetings: [Meeting] = []
    @Published var selectedMeetingID: UUID?

    // MARK: - Services
    let audioService = AudioRecordingService()
    let meetingDetector = MeetingDetectorService()
    let transcriptionService = TranscriptionService()
    let storageService = StorageService()
    let aiService = AIService()

    // MARK: - Settings
    @AppStorage("whisperModelSize") var whisperModelSize = "base"
    @AppStorage("autoRecord") var autoRecord = true
    @AppStorage("autoTranscribe") var autoTranscribe = true
    @AppStorage("selectedLanguage") var selectedLanguage = "auto"
    @AppStorage("audioInputDevice") var audioInputDevice = "default"
    @AppStorage("ollamaModel") var ollamaModel = "llama3.2"

    private var durationTimer: Timer?

    var selectedMeeting: Meeting? {
        guard let id = selectedMeetingID else { return nil }
        return meetings.first { $0.id == id }
    }

    private init() {
        setupBindings()
        loadMeetings()
    }

    private func setupBindings() {
        meetingDetector.onMeetingDetected = { [weak self] source in
            guard let self, self.autoRecord, !self.isRecording else { return }
            Task { @MainActor in
                self.currentMeetingSource = source
                await self.startRecording()
            }
        }
        meetingDetector.onMeetingEnded = { [weak self] in
            guard let self, self.isRecording else { return }
            Task { @MainActor in
                await self.stopRecording()
            }
        }
        audioService.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.recordingLevel = level
            }
        }
    }

    func loadMeetings() {
        meetings = storageService.loadAllMeetings()
    }

    // MARK: - Recording

    func startRecording() async {
        guard !isRecording else { return }
        let meetingDir = storageService.createMeetingDirectory(source: currentMeetingSource)
        let audioPath = meetingDir.appendingPathComponent("audio.wav")
        do {
            try audioService.startRecording(to: audioPath, deviceID: audioInputDevice)
            isRecording = true
            recordingDuration = 0
            startDurationTimer()
            NotificationHelper.send(title: "Recording Started", body: "Recording \(currentMeetingSource.displayName) meeting...")
        } catch {
            AppLogger.error("Failed to start recording: \(error)", category: .audio)
            NotificationHelper.send(title: "Recording Failed", body: error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        let audioURL = audioService.stopRecording()
        isRecording = false
        stopDurationTimer()
        guard let audioURL else { return }

        let meeting = Meeting(
            id: UUID(), date: Date(), source: currentMeetingSource,
            duration: recordingDuration, audioPath: audioURL.path,
            status: autoTranscribe ? .transcribing : .recorded
        )
        storageService.saveMeeting(meeting)
        meetings.insert(meeting, at: 0)
        NotificationHelper.send(title: "Recording Saved", body: "Duration: \(meeting.formattedDuration)")

        if autoTranscribe {
            await transcribe(meeting: meeting)
        }
    }

    func toggleRecording() async {
        if isRecording { await stopRecording() }
        else { currentMeetingSource = .manual; await startRecording() }
    }

    // MARK: - Transcription

    func transcribe(meeting: Meeting, modelSize: String? = nil) async {
        guard !isTranscribing else {
            AppLogger.warning("Transcription skipped — already in progress", category: .transcription)
            return
        }

        let model = modelSize ?? whisperModelSize
        AppLogger.info("Starting transcription for meeting \(meeting.id) with model: \(model)", category: .transcription)
        AppLogger.info("Audio file: \(meeting.audioPath)", category: .transcription)

        // Verify audio file exists
        guard FileManager.default.fileExists(atPath: meeting.audioPath) else {
            AppLogger.error("Audio file not found: \(meeting.audioPath)", category: .transcription)
            return
        }

        // Remove old whisper output JSON if it exists (force fresh transcription)
        let whisperJSON = meeting.audioPath + ".json"
        if FileManager.default.fileExists(atPath: whisperJSON) {
            try? FileManager.default.removeItem(atPath: whisperJSON)
            AppLogger.info("Removed stale whisper output: \(whisperJSON)", category: .transcription)
        }

        isTranscribing = true
        transcriptionProgress = 0

        // Update status to show transcribing
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index].status = .transcribing
            storageService.saveMeeting(meetings[index])
        }

        defer {
            isTranscribing = false
            transcriptionProgress = 0
            AppLogger.info("Transcription state reset (isTranscribing = false)", category: .transcription)
        }

        do {
            let transcript = try await transcriptionService.transcribe(
                audioPath: meeting.audioPath, language: selectedLanguage, modelSize: model
            ) { [weak self] progress in
                Task { @MainActor in self?.transcriptionProgress = progress }
            }

            AppLogger.info("Transcription complete: \(transcript.segments.count) segments, language: \(transcript.language)", category: .transcription)

            let transcriptPath = URL(fileURLWithPath: meeting.audioPath)
                .deletingLastPathComponent().appendingPathComponent("transcript.json")
            try storageService.saveTranscript(transcript, to: transcriptPath)
            AppLogger.info("Transcript saved to: \(transcriptPath.path)", category: .transcription)

            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index].transcriptPath = transcriptPath.path
                meetings[index].status = .transcribed
                storageService.saveMeeting(meetings[index])
            }
            NotificationHelper.send(title: "Transcription Complete", body: "\(transcript.segments.count) segments — \(meeting.source.displayName)")
        } catch {
            AppLogger.error("Transcription failed: \(error)", category: .transcription)
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index].status = .failed(error.localizedDescription)
                storageService.saveMeeting(meetings[index])
            }
            NotificationHelper.send(title: "Transcription Failed", body: error.localizedDescription)
        }
    }

    // MARK: - AI Analysis

    func summarize(meeting: Meeting) async {
        guard !isSummarizing, let transcriptPath = meeting.transcriptPath,
              let transcript = storageService.loadTranscript(from: transcriptPath) else { return }

        isSummarizing = true
        do {
            let running = await aiService.isOllamaRunning()
            guard running else { throw AIServiceError.ollamaNotRunning }

            let summary = try await aiService.summarize(transcript: transcript, model: ollamaModel)
            let summaryURL = meeting.directoryURL.appendingPathComponent("summary.json")
            try storageService.saveSummary(summary, to: summaryURL)

            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index].summaryPath = summaryURL.path
                meetings[index].status = .summarized
                storageService.saveMeeting(meetings[index])
            }
            NotificationHelper.send(title: "Summary Ready", body: "\(meeting.source.displayName) meeting summarized")
        } catch {
            AppLogger.error("Summarization failed: \(error)", category: .ai)
            NotificationHelper.send(title: "Summary Failed", body: error.localizedDescription)
        }
        isSummarizing = false
    }

    func analyzeSentiment(meeting: Meeting) async {
        guard !isAnalyzingSentiment, let transcriptPath = meeting.transcriptPath,
              let transcript = storageService.loadTranscript(from: transcriptPath) else { return }

        isAnalyzingSentiment = true
        do {
            let running = await aiService.isOllamaRunning()
            guard running else { throw AIServiceError.ollamaNotRunning }

            let sentiment = try await aiService.analyzeSentiment(transcript: transcript, model: ollamaModel)
            let sentimentURL = meeting.directoryURL.appendingPathComponent("sentiment.json")
            try storageService.saveSentiment(sentiment, to: sentimentURL)

            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index].sentimentPath = sentimentURL.path
                storageService.saveMeeting(meetings[index])
            }
            NotificationHelper.send(title: "Analysis Ready", body: "\(meeting.source.displayName) meeting analyzed")
        } catch {
            AppLogger.error("Sentiment analysis failed: \(error)", category: .ai)
            NotificationHelper.send(title: "Analysis Failed", body: error.localizedDescription)
        }
        isAnalyzingSentiment = false
    }

    // MARK: - Notes

    func saveNotes(meeting: Meeting, notes: String) {
        let notesURL = meeting.directoryURL.appendingPathComponent("notes.txt")
        do {
            try storageService.saveNotes(notes, to: notesURL)
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index].notesPath = notesURL.path
                storageService.saveMeeting(meetings[index])
            }
        } catch {
            AppLogger.error("Failed to save notes: \(error)", category: .notes)
        }
    }

    func deleteMeeting(_ meeting: Meeting) {
        storageService.deleteMeeting(meeting)
        meetings.removeAll { $0.id == meeting.id }
        if selectedMeetingID == meeting.id { selectedMeetingID = nil }
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordingDuration += 1 }
        }
    }
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
