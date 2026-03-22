import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var whisperInstalled = false
    @State private var availableModels: [String] = []
    @State private var launchAtLogin = false

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gear") }
            audioTab.tabItem { Label("Audio", systemImage: "mic") }
            transcriptionTab.tabItem { Label("Transcription", systemImage: "text.bubble") }
            modelsTab.tabItem { Label("Models", systemImage: "arrow.down.circle") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 440)
        .onAppear { refreshModelState() }
    }

    private func refreshModelState() {
        whisperInstalled = appState.transcriptionService.isWhisperInstalled()
        availableModels = appState.transcriptionService.availableModels()
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { oldValue, newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            print("[Settings] Launch at login error: \(error)")
                            launchAtLogin = !newValue
                        }
                    }
            }
            Section("Recording") {
                Toggle("Auto-record when meeting detected", isOn: $appState.autoRecord)
                Toggle("Auto-transcribe after recording", isOn: $appState.autoTranscribe)
            }
            Section("Storage") {
                HStack {
                    Text("Storage used"); Spacer()
                    Text(appState.storageService.formattedStorageUsed()).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Recordings folder"); Spacer()
                    Button("Open in Finder") { NSWorkspace.shared.open(appState.storageService.recordingsDir) }
                        .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped).padding()
    }

    // MARK: - Audio

    private var audioTab: some View {
        Form {
            Section("Input Device") {
                Picker("Audio Input", selection: $appState.audioInputDevice) {
                    Text("System Default").tag("default")
                    ForEach(AudioRecordingService.availableInputDevices()) { device in
                        Text(device.name + (device.isDefault ? " (Default)" : "")).tag(device.id)
                    }
                }
                Text("For system audio capture, set up a BlackHole Aggregate Device in Audio MIDI Setup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("BlackHole Setup Guide") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To record both your mic and meeting audio:").font(.subheadline.bold())
                    Group {
                        Text("1. Install BlackHole (build from source or existential.audio)")
                        Text("2. Open Audio MIDI Setup")
                        Text("3. Create Multi-Output Device (BlackHole + speakers)")
                        Text("4. Create Aggregate Device (BlackHole + mic)")
                        Text("5. Select the Aggregate Device above")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).padding()
    }

    // MARK: - Transcription

    private var transcriptionTab: some View {
        Form {
            Section("Whisper Engine") {
                HStack {
                    Text("Status"); Spacer()
                    if whisperInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Not Found", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
                if !whisperInstalled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Install:").font(.subheadline.bold())
                        Text("brew install whisper-cpp")
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .padding(6).background(Color.gray.opacity(0.08)).cornerRadius(4)
                    }
                }
            }
            Section("Active Model") {
                Picker("Model", selection: $appState.whisperModelSize) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                    // Ensure the current selection always has a matching tag
                    if !availableModels.contains(appState.whisperModelSize) {
                        Text("\(appState.whisperModelSize) (not downloaded)").tag(appState.whisperModelSize)
                    }
                }
                Text("Download models in the Models tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Language") {
                Picker("Language", selection: $appState.selectedLanguage) {
                    Text("Auto-detect").tag("auto")
                    Text("English").tag("en")
                    Text("Arabic").tag("ar")
                }
            }
        }
        .formStyle(.grouped).padding()
    }

    // MARK: - Models Tab (Download GUI)

    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Whisper Models")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)
            Text("Download models for local transcription. Larger models are more accurate, especially for Arabic.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 1) {
                    ModelDownloadRow(
                        name: "base", size: "142 MB",
                        description: "Fast, good for English",
                        isDownloaded: availableModels.contains("base"),
                        modelsDir: appState.storageService.modelsDirectory,
                        onComplete: refreshModelState
                    )
                    ModelDownloadRow(
                        name: "small", size: "466 MB",
                        description: "Balanced speed and accuracy",
                        isDownloaded: availableModels.contains("small"),
                        modelsDir: appState.storageService.modelsDirectory,
                        onComplete: refreshModelState
                    )
                    ModelDownloadRow(
                        name: "medium", size: "1.5 GB",
                        description: "Better accuracy, slower",
                        isDownloaded: availableModels.contains("medium"),
                        modelsDir: appState.storageService.modelsDirectory,
                        onComplete: refreshModelState
                    )
                    ModelDownloadRow(
                        name: "large-v3", size: "3.1 GB",
                        description: "Best for Arabic and mixed languages",
                        isDownloaded: availableModels.contains("large-v3"),
                        modelsDir: appState.storageService.modelsDirectory,
                        onComplete: refreshModelState
                    )
                }
                .padding(16)
            }
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56)).foregroundStyle(.blue)
            Text("Meeting Recorder").font(.title2.bold())
            Text("v0.1.0 — MVP").font(.subheadline).foregroundStyle(.secondary)
            Text("100% local. Your meetings never leave your Mac.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Model Download Row

struct ModelDownloadRow: View {
    let name: String
    let size: String
    let description: String
    let isDownloaded: Bool
    let modelsDir: URL
    let onComplete: () -> Void

    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var error: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("ggml-\(name)")
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isDownloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if isDownloading {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .frame(width: 100)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Button("Download") {
                    Task { await download() }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            Group {
                if let error {
                    Text(error).font(.caption2).foregroundStyle(.red)
                        .padding(4)
                }
            },
            alignment: .bottom
        )
    }

    private func download() async {
        let urlString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(name).bin"
        guard let url = URL(string: urlString) else { return }

        isDownloading = true
        error = nil
        progress = 0

        do {
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            let destination = modelsDir.appendingPathComponent("ggml-\(name).bin")

            // Use download task with delegate for progress
            let delegate = DownloadDelegate { p in
                Task { @MainActor in self.progress = p }
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempURL, _) = try await session.download(from: url)

            // Move downloaded file to final location
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            session.invalidateAndCancel()

            await MainActor.run {
                progress = 1.0
                isDownloading = false
                onComplete()
            }
        } catch {
            await MainActor.run {
                self.error = "Failed: \(error.localizedDescription)"
                isDownloading = false
            }
        }
    }
}

/// URLSession delegate that reports download progress
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(p)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled in the async call above
    }
}
