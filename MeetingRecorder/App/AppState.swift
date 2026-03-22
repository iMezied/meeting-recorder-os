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

    // MARK: - Data
    @Published var meetings: [Meeting] = []
    @Published var selectedMeetingID: UUID?

    // MARK: - Services
    let audioService = AudioRecordingService()
    let meetingDetector = MeetingDetectorService()
    let transcriptionService = TranscriptionService()
    let storageService = StorageService()

    // MARK: - Settings
    @AppStorage("whisperModelSize") var whisperModelSize = "base"
    @AppStorage("autoRecord") var autoRecord = true
    @AppStorage("autoTranscribe") var autoTranscribe = true
    @AppStorage("selectedLanguage") var selectedLanguage = "auto"
    @AppStorage("audioInputDevice") var audioInputDevice = "default"

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
            print("Failed to start recording: \(error)")
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

    func transcribe(meeting: Meeting) async {
        guard !isTranscribing else { return }
        isTranscribing = true
        transcriptionProgress = 0
        do {
            let transcript = try await transcriptionService.transcribe(
                audioPath: meeting.audioPath, language: selectedLanguage, modelSize: whisperModelSize
            ) { [weak self] progress in
                Task { @MainActor in self?.transcriptionProgress = progress }
            }
            let transcriptPath = URL(fileURLWithPath: meeting.audioPath)
                .deletingLastPathComponent().appendingPathComponent("transcript.json")
            try storageService.saveTranscript(transcript, to: transcriptPath)

            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index].transcriptPath = transcriptPath.path
                meetings[index].status = .transcribed
                storageService.saveMeeting(meetings[index])
            }
            NotificationHelper.send(title: "Transcription Complete", body: "\(meeting.source.displayName) meeting transcribed")
        } catch {
            print("Transcription failed: \(error)")
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index].status = .failed(error.localizedDescription)
                storageService.saveMeeting(meetings[index])
            }
        }
        isTranscribing = false
        transcriptionProgress = 0
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
