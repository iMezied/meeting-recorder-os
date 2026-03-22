import AVFoundation
import Foundation

final class AudioRecordingService: NSObject, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var currentOutputURL: URL?

    var onAudioLevel: ((Float) -> Void)?

    // MARK: - Available Devices

    static func availableInputDevices() -> [AudioDevice] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices

        let defaultDevice = AVCaptureDevice.default(for: .audio)

        return devices.map { device in
            AudioDevice(
                id: device.uniqueID,
                name: device.localizedName,
                isInput: true,
                isDefault: device.uniqueID == defaultDevice?.uniqueID
            )
        }
    }

    // MARK: - Permission

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    @discardableResult
    static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: - Recording

    func startRecording(to url: URL, deviceID: String = "default") throws {
        guard AudioRecordingService.isAuthorized else {
            throw RecordingError.noMicrophonePermission
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            print("[AudioService] Failed to create recorder: \(error)")
            throw RecordingError.failedToStart
        }

        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.delegate = self

        guard audioRecorder?.record() == true else {
            audioRecorder = nil
            throw RecordingError.failedToStart
        }

        currentOutputURL = url
        startLevelMonitoring()
        print("[AudioService] Recording to: \(url.path)")
    }

    func stopRecording() -> URL? {
        stopLevelMonitoring()
        guard let recorder = audioRecorder else { return nil }
        recorder.stop()
        let url = currentOutputURL
        audioRecorder = nil
        currentOutputURL = nil
        print("[AudioService] Recording stopped. File: \(url?.path ?? "nil")")
        return url
    }

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    // MARK: - Level Monitoring

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            recorder.updateMeters()
            let level = recorder.averagePower(forChannel: 0)
            let normalizedLevel = max(0, min(1, (level + 50) / 50))
            self.onAudioLevel?(normalizedLevel)
        }
    }

    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        onAudioLevel?(0)
    }
}

extension AudioRecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { print("[AudioService] Recording finished with error") }
    }
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("[AudioService] Encoding error: \(error?.localizedDescription ?? "unknown")")
    }
}

enum RecordingError: LocalizedError {
    case noMicrophonePermission
    case failedToStart
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .noMicrophonePermission:
            return "Microphone permission is required. Grant access in System Settings → Privacy & Security → Microphone."
        case .failedToStart:
            return "Failed to start recording. Check your audio device settings."
        case .deviceNotFound:
            return "Selected audio device not found."
        }
    }
}
