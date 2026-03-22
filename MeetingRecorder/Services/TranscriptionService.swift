import Foundation

/// Transcription service that uses whisper.cpp CLI for speech-to-text.
/// Shells out to the `whisper-cli` binary installed via Homebrew.
final class TranscriptionService {

    private let modelsDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MeetingRecorder/models", isDirectory: true)
    }()

    // MARK: - Public API

    func transcribe(
        audioPath: String,
        language: String = "auto",
        modelSize: String = "base",
        onProgress: @escaping (Double) -> Void
    ) async throws -> Transcript {

        let whisperPath = try resolveWhisperBinary()
        let modelPath = try resolveModelPath(size: modelSize)

        print("[Transcription] Starting: \(audioPath)")
        print("[Transcription] Binary: \(whisperPath)")
        print("[Transcription] Model: \(modelPath)")
        print("[Transcription] Language: \(language)")

        let arguments = [
            "--model", modelPath,
            "--file", audioPath,
            "--output-json-full",
            "--print-progress",
            "--language", language,
        ]

        let (stdout, _) = try await runProcess(
            executable: whisperPath,
            arguments: arguments,
            onStderr: { line in
                if let range = line.range(of: "progress = "),
                   let percentStr = line[range.upperBound...].split(separator: "%").first,
                   let percent = Double(percentStr) {
                    onProgress(percent / 100.0)
                }
            }
        )

        onProgress(1.0)

        // whisper-cli --output-json-full writes a .json file next to the audio
        let jsonPath = audioPath + ".json"
        let jsonURL = URL(fileURLWithPath: jsonPath)

        if FileManager.default.fileExists(atPath: jsonPath) {
            return try parseWhisperJSON(at: jsonURL, modelSize: modelSize)
        }

        // Fallback: parse stdout text output
        return parseWhisperTextOutput(stdout, modelSize: modelSize)
    }

    func isWhisperInstalled() -> Bool {
        (try? resolveWhisperBinary()) != nil
    }

    func availableModels() -> [String] {
        guard FileManager.default.fileExists(atPath: modelsDir.path) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path)) ?? []
        return files
            .filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
            .map { $0.replacingOccurrences(of: "ggml-", with: "")
                     .replacingOccurrences(of: ".bin", with: "") }
    }

    // MARK: - Binary Resolution

    private func resolveWhisperBinary() throws -> String {
        // Check known Homebrew paths directly (sandboxed apps don't inherit shell PATH)
        let knownPaths = [
            "/opt/homebrew/bin/whisper-cli",        // Apple Silicon Homebrew (v1.8+)
            "/opt/homebrew/bin/whisper-cpp",         // Older Homebrew name
            "/opt/homebrew/bin/whisper",             // Alternative name
            "/usr/local/bin/whisper-cli",            // Intel Homebrew (v1.8+)
            "/usr/local/bin/whisper-cpp",            // Older Intel Homebrew
            "/usr/local/bin/whisper",                // Alternative name
        ]

        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                print("[Transcription] Found whisper at: \(path)")
                return path
            }
        }

        // Fallback: use a login shell to resolve (inherits full user PATH)
        if let fromShell = resolveFromShell("whisper-cli") ?? resolveFromShell("whisper-cpp") ?? resolveFromShell("whisper") {
            print("[Transcription] Found whisper via shell: \(fromShell)")
            return fromShell
        }

        throw TranscriptionError.whisperNotFound
    }

    private func resolveFromShell(_ binary: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "which \(binary)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty else { return nil }
            return path
        } catch {
            return nil
        }
    }

    // MARK: - Model Resolution

    private func resolveModelPath(size: String) throws -> String {
        let modelFile = "ggml-\(size).bin"
        let modelPath = modelsDir.appendingPathComponent(modelFile)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath.path
        }

        // Check Homebrew's default model location
        let brewModelPath = "/opt/homebrew/share/whisper-cpp/models/\(modelFile)"
        if FileManager.default.fileExists(atPath: brewModelPath) {
            return brewModelPath
        }

        // Intel Homebrew location
        let brewIntelPath = "/usr/local/share/whisper-cpp/models/\(modelFile)"
        if FileManager.default.fileExists(atPath: brewIntelPath) {
            return brewIntelPath
        }

        throw TranscriptionError.modelNotFound(size)
    }

    // MARK: - Process Execution

    private func runProcess(
        executable: String,
        arguments: [String],
        onStderr: @escaping (String) -> Void
    ) async throws -> (stdout: String, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: executable)
                task.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                task.standardOutput = stdoutPipe
                task.standardError = stderrPipe

                var stderrAccum = ""

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                    stderrAccum += line
                    onStderr(line)
                }

                do {
                    try task.run()
                    task.waitUntilExit()

                    stderrPipe.fileHandleForReading.readabilityHandler = nil

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

                    if task.terminationStatus != 0 {
                        continuation.resume(throwing: TranscriptionError.processFailed(stderrAccum))
                    } else {
                        continuation.resume(returning: (stdout, stderrAccum))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Parsing

    private func parseWhisperJSON(at url: URL, modelSize: String) throws -> Transcript {
        let data = try Data(contentsOf: url)

        struct WhisperOutput: Decodable {
            let transcription: [WhisperSegment]?
            let result: WhisperResult?
        }

        struct WhisperResult: Decodable {
            let language: String?
        }

        struct WhisperSegment: Decodable {
            let timestamps: WhisperTimestamps
            let text: String

            struct WhisperTimestamps: Decodable {
                let from: String
                let to: String
            }
        }

        let output = try JSONDecoder().decode(WhisperOutput.self, from: data)

        // Parse segments and assign speaker labels based on time gaps and turn markers
        var currentSpeaker = 1
        var speakerCount = 1
        var segments: [TranscriptSegment] = []
        var previousEndTime: Double = 0

        for (index, seg) in (output.transcription ?? []).enumerated() {
            let rawText = seg.text.trimmingCharacters(in: .whitespaces)

            // Check for [SPEAKER_TURN] marker (if present from whisper)
            if rawText.contains("[SPEAKER_TURN]") {
                speakerCount += 1
                currentSpeaker = speakerCount
            }

            let cleanText = rawText
                .replacingOccurrences(of: "[SPEAKER_TURN]", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleanText.isEmpty else { continue }

            let startTime = parseTimestamp(seg.timestamps.from)
            let endTime = parseTimestamp(seg.timestamps.to)

            // Detect speaker change based on significant pause (>1.5s gap between segments)
            if index > 0 && (startTime - previousEndTime) > 1.5 {
                speakerCount += 1
                currentSpeaker = speakerCount
            }
            previousEndTime = endTime

            segments.append(TranscriptSegment(
                index: index,
                startTime: startTime,
                endTime: endTime,
                text: cleanText,
                language: output.result?.language,
                speaker: "Speaker \(currentSpeaker)"
            ))
        }

        // Clean up whisper's output JSON (we save our own format)
        try? FileManager.default.removeItem(at: url)

        return Transcript(
            segments: segments,
            language: output.result?.language ?? "auto",
            modelUsed: modelSize,
            processedAt: Date()
        )
    }

    private func parseWhisperTextOutput(_ output: String, modelSize: String) -> Transcript {
        let pattern = #"\[(\d{2}:\d{2}:\d{2}\.\d{3}) --> (\d{2}:\d{2}:\d{2}\.\d{3})\]\s+(.*)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let lines = output.components(separatedBy: .newlines)

        var segments: [TranscriptSegment] = []
        var currentSpeaker = 1
        var speakerCount = 1
        var previousEndTime: Double = 0

        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex?.firstMatch(in: line, range: range) {
                let start = String(line[Range(match.range(at: 1), in: line)!])
                let end = String(line[Range(match.range(at: 2), in: line)!])
                var text = String(line[Range(match.range(at: 3), in: line)!])

                if text.contains("[SPEAKER_TURN]") {
                    speakerCount += 1
                    currentSpeaker = speakerCount
                    text = text.replacingOccurrences(of: "[SPEAKER_TURN]", with: "")
                }

                let cleanText = text.trimmingCharacters(in: .whitespaces)
                guard !cleanText.isEmpty else { continue }

                let startTime = parseTimestamp(start)
                let endTime = parseTimestamp(end)

                // Detect speaker change based on significant pause
                if !segments.isEmpty && (startTime - previousEndTime) > 1.5 {
                    speakerCount += 1
                    currentSpeaker = speakerCount
                }
                previousEndTime = endTime

                segments.append(TranscriptSegment(
                    index: index,
                    startTime: startTime,
                    endTime: endTime,
                    text: cleanText,
                    language: nil,
                    speaker: "Speaker \(currentSpeaker)"
                ))
            }
        }

        return Transcript(
            segments: segments,
            language: "auto",
            modelUsed: modelSize,
            processedAt: Date()
        )
    }

    private func parseTimestamp(_ ts: String) -> Double {
        let parts = ts.components(separatedBy: ":")
        guard parts.count == 3 else { return 0 }
        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0
        return hours * 3600 + minutes * 60 + seconds
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case whisperNotFound
    case modelNotFound(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .whisperNotFound:
            return "whisper-cli not found. Install it with: brew install whisper-cpp"
        case .modelNotFound(let size):
            return "Model '\(size)' not found. Run: curl -L -o ~/Library/Application\\ Support/MeetingRecorder/models/ggml-\(size).bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(size).bin"
        case .processFailed(let msg):
            return "Transcription failed: \(msg)"
        }
    }
}
