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

        AppLogger.info("Starting transcription", category: .transcription)
        AppLogger.info("  Audio: \(audioPath)", category: .transcription)
        AppLogger.info("  Binary: \(whisperPath)", category: .transcription)
        AppLogger.info("  Model: \(modelPath) (\(modelSize))", category: .transcription)
        AppLogger.info("  Language: \(language)", category: .transcription)

        // Check audio file exists and log size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioPath),
           let size = attrs[.size] as? Int64 {
            AppLogger.info("  Audio file size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))", category: .transcription)
        }

        var arguments = [
            "--model", modelPath,
            "--file", audioPath,
            "--output-json-full",
            "--print-progress",
            "--language", language,
        ]

        // For mixed-language meetings, add a bilingual prompt to prevent
        // whisper from translating or hallucinating in single-language mode
        if language == "auto" {
            arguments += [
                "--prompt",
                "This is a bilingual meeting conversation in Arabic and English. Transcribe each language as spoken, do not translate."
            ]
            AppLogger.info("  Using bilingual prompt for mixed-language support", category: .transcription)
        }

        AppLogger.debug("Whisper arguments: \(arguments.joined(separator: " "))", category: .transcription)

        let (stdout, stderr) = try await runProcess(
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
        AppLogger.info("Whisper process completed", category: .transcription)
        AppLogger.debug("Whisper stdout length: \(stdout.count) chars", category: .transcription)

        // Log stderr for debugging (contains whisper's info output)
        let stderrLines = stderr.components(separatedBy: .newlines).filter { !$0.isEmpty }
        for line in stderrLines.suffix(10) {
            AppLogger.debug("Whisper stderr: \(line)", category: .transcription)
        }

        // whisper-cli --output-json-full writes a .json file next to the audio
        let jsonPath = audioPath + ".json"
        let jsonURL = URL(fileURLWithPath: jsonPath)

        if FileManager.default.fileExists(atPath: jsonPath) {
            AppLogger.info("Found whisper JSON output at: \(jsonPath)", category: .transcription)
            let transcript = try parseWhisperJSON(at: jsonURL, modelSize: modelSize)
            AppLogger.info("Parsed \(transcript.segments.count) segments, language: \(transcript.language)", category: .transcription)
            return transcript
        }

        AppLogger.warning("No JSON output found, falling back to text parsing", category: .transcription)
        let transcript = parseWhisperTextOutput(stdout, modelSize: modelSize)
        AppLogger.info("Text parsing produced \(transcript.segments.count) segments", category: .transcription)
        return transcript
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
        let knownPaths = [
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/opt/homebrew/bin/whisper",
            "/usr/local/bin/whisper-cli",
            "/usr/local/bin/whisper-cpp",
            "/usr/local/bin/whisper",
        ]

        for path in knownPaths {
            if FileManager.default.fileExists(atPath: path) {
                AppLogger.info("Found whisper at: \(path)", category: .transcription)
                return path
            }
        }

        if let fromShell = resolveFromShell("whisper-cli") ?? resolveFromShell("whisper-cpp") ?? resolveFromShell("whisper") {
            AppLogger.info("Found whisper via shell: \(fromShell)", category: .transcription)
            return fromShell
        }

        AppLogger.error("whisper-cli not found in any known path", category: .transcription)
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

        let brewModelPath = "/opt/homebrew/share/whisper-cpp/models/\(modelFile)"
        if FileManager.default.fileExists(atPath: brewModelPath) {
            return brewModelPath
        }

        let brewIntelPath = "/usr/local/share/whisper-cpp/models/\(modelFile)"
        if FileManager.default.fileExists(atPath: brewIntelPath) {
            return brewIntelPath
        }

        AppLogger.error("Model not found: \(size)", category: .transcription)
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

                    AppLogger.debug("Whisper exit code: \(task.terminationStatus)", category: .transcription)

                    if task.terminationStatus != 0 {
                        AppLogger.error("Whisper failed with exit code \(task.terminationStatus)", category: .transcription)
                        AppLogger.error("Whisper stderr: \(stderrAccum.prefix(500))", category: .transcription)
                        continuation.resume(throwing: TranscriptionError.processFailed(stderrAccum))
                    } else {
                        continuation.resume(returning: (stdout, stderrAccum))
                    }
                } catch {
                    AppLogger.error("Failed to launch whisper: \(error)", category: .transcription)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Parsing

    private func parseWhisperJSON(at url: URL, modelSize: String) throws -> Transcript {
        let data = try Data(contentsOf: url)

        // Log raw JSON for debugging (first 500 chars)
        if let rawJSON = String(data: data, encoding: .utf8) {
            AppLogger.debug("Whisper JSON (first 500 chars): \(String(rawJSON.prefix(500)))", category: .transcription)
        }

        struct WhisperOutput: Decodable {
            let transcription: [WhisperSegment]?
            let result: WhisperResult?
        }

        struct WhisperResult: Decodable {
            let language: String?
        }

        struct WhisperSegment: Decodable {
            let timestamps: WhisperTimestamps
            let offsets: WhisperOffsets?
            let text: String

            struct WhisperTimestamps: Decodable {
                let from: String
                let to: String
            }

            struct WhisperOffsets: Decodable {
                let from: Int
                let to: Int
            }
        }

        let output = try JSONDecoder().decode(WhisperOutput.self, from: data)
        let rawSegments = output.transcription ?? []
        AppLogger.info("Whisper JSON contains \(rawSegments.count) raw segments", category: .transcription)
        AppLogger.info("Detected language: \(output.result?.language ?? "unknown")", category: .transcription)

        // Log first few segments for debugging
        for (i, seg) in rawSegments.prefix(3).enumerated() {
            AppLogger.debug("  Segment \(i): from=\(seg.timestamps.from) to=\(seg.timestamps.to) offsets=\(seg.offsets?.from ?? -1)-\(seg.offsets?.to ?? -1) text=\"\(seg.text.prefix(60))\"", category: .transcription)
        }

        // Parse segments and assign speaker labels
        var currentSpeaker = 1
        var speakerCount = 1
        var segments: [TranscriptSegment] = []
        var previousEndTime: Double = 0

        for (index, seg) in rawSegments.enumerated() {
            let rawText = seg.text.trimmingCharacters(in: .whitespaces)

            if rawText.contains("[SPEAKER_TURN]") {
                speakerCount += 1
                currentSpeaker = speakerCount
            }

            let cleanText = rawText
                .replacingOccurrences(of: "[SPEAKER_TURN]", with: "")
                .trimmingCharacters(in: .whitespaces)

            guard !cleanText.isEmpty else { continue }

            // Use offsets (milliseconds) if available, otherwise parse timestamp strings
            let startTime: Double
            let endTime: Double
            if let offsets = seg.offsets {
                startTime = Double(offsets.from) / 1000.0
                endTime = Double(offsets.to) / 1000.0
            } else {
                startTime = parseTimestamp(seg.timestamps.from)
                endTime = parseTimestamp(seg.timestamps.to)
            }

            // Detect speaker change based on significant pause (>1.5s gap)
            if index > 0 && previousEndTime > 0 && (startTime - previousEndTime) > 1.5 {
                speakerCount += 1
                currentSpeaker = speakerCount
                AppLogger.debug("Speaker change at \(String(format: "%.1f", startTime))s (gap: \(String(format: "%.1f", startTime - previousEndTime))s)", category: .transcription)
            }
            previousEndTime = endTime

            segments.append(TranscriptSegment(
                index: segments.count,
                startTime: startTime,
                endTime: endTime,
                text: cleanText,
                language: output.result?.language,
                speaker: "Speaker \(currentSpeaker)"
            ))
        }

        // Clean up whisper's output JSON (we save our own format)
        try? FileManager.default.removeItem(at: url)

        let uniqueSpeakers = Set(segments.map { $0.speaker ?? "" }).count
        AppLogger.info("Final: \(segments.count) segments, \(uniqueSpeakers) speakers detected", category: .transcription)

        return Transcript(
            segments: segments,
            language: output.result?.language ?? "auto",
            modelUsed: modelSize,
            processedAt: Date()
        )
    }

    private func parseWhisperTextOutput(_ output: String, modelSize: String) -> Transcript {
        let pattern = #"\[(\d{2}:\d{2}:\d{2}[\.,]\d{3}) --> (\d{2}:\d{2}:\d{2}[\.,]\d{3})\]\s+(.*)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let lines = output.components(separatedBy: .newlines)

        AppLogger.debug("Parsing text output: \(lines.count) lines", category: .transcription)

        var segments: [TranscriptSegment] = []
        var currentSpeaker = 1
        var speakerCount = 1
        var previousEndTime: Double = 0

        for (_, line) in lines.enumerated() {
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

                if !segments.isEmpty && previousEndTime > 0 && (startTime - previousEndTime) > 1.5 {
                    speakerCount += 1
                    currentSpeaker = speakerCount
                }
                previousEndTime = endTime

                segments.append(TranscriptSegment(
                    index: segments.count,
                    startTime: startTime,
                    endTime: endTime,
                    text: cleanText,
                    language: nil,
                    speaker: "Speaker \(currentSpeaker)"
                ))
            }
        }

        AppLogger.info("Text parsing: \(segments.count) segments found", category: .transcription)

        return Transcript(
            segments: segments,
            language: "auto",
            modelUsed: modelSize,
            processedAt: Date()
        )
    }

    /// Parses timestamps in format "HH:MM:SS.mmm" or "HH:MM:SS,mmm"
    private func parseTimestamp(_ ts: String) -> Double {
        // Handle both "00:00:05.000" and "00:00:05,000" formats
        let normalized = ts.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.components(separatedBy: ":")
        guard parts.count == 3 else {
            AppLogger.warning("Invalid timestamp format: \(ts)", category: .transcription)
            return 0
        }
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
