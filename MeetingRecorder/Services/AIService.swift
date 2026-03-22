import Foundation

/// Local AI service using ollama for meeting summarization and sentiment analysis.
final class AIService {

    private let baseURL = "http://localhost:11434"

    // MARK: - Public API

    func isOllamaRunning() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func availableModels() async -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            return result.models.map(\.name)
        } catch {
            return []
        }
    }

    func summarize(transcript: Transcript, model: String = "llama3.2") async throws -> MeetingSummary {
        let prompt = buildSummaryPrompt(transcript: transcript)
        let response = try await generate(prompt: prompt, model: model)
        return parseSummaryResponse(response)
    }

    func analyzeSentiment(transcript: Transcript, model: String = "llama3.2") async throws -> MeetingSentiment {
        let prompt = buildSentimentPrompt(transcript: transcript)
        let response = try await generate(prompt: prompt, model: model)
        return parseSentimentResponse(response, transcript: transcript)
    }

    // MARK: - Ollama API

    private func generate(prompt: String, model: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5 minutes for large transcripts

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.3]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.requestFailed("No HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if errorBody.contains("model") && errorBody.contains("not found") {
                throw AIServiceError.modelNotFound(model)
            }
            throw AIServiceError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let result = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return result.response
    }

    // MARK: - Prompts

    private func buildSummaryPrompt(transcript: Transcript) -> String {
        let text = transcript.segments.map { seg in
            let speaker = seg.speaker ?? "Unknown"
            return "[\(speaker)] \(seg.text)"
        }.joined(separator: "\n")

        return """
        You are a meeting assistant. Analyze the following meeting transcript and provide:

        1. A brief summary (2-4 sentences) of what the meeting was about
        2. Key discussion points (bullet points)
        3. Action items with the responsible person if identifiable (bullet points)
        4. Decisions made during the meeting (bullet points)

        Format your response EXACTLY like this:
        SUMMARY:
        <your summary here>

        KEY POINTS:
        - <point 1>
        - <point 2>

        ACTION ITEMS:
        - <action 1>
        - <action 2>

        DECISIONS:
        - <decision 1>
        - <decision 2>

        If the transcript is in Arabic or mixed Arabic/English, provide the summary in the same language mix as the transcript.

        TRANSCRIPT:
        \(text)
        """
    }

    private func buildSentimentPrompt(transcript: Transcript) -> String {
        let text = transcript.segments.map { seg in
            let speaker = seg.speaker ?? "Unknown"
            return "[\(speaker)] \(seg.text)"
        }.joined(separator: "\n")

        return """
        You are a meeting analyst. Analyze the following meeting transcript and assess the sentiment and communication patterns.

        Provide:
        1. Overall meeting tone (e.g., collaborative, tense, productive, casual)
        2. For each speaker, describe their:
           - Communication style (brief description)
           - Sentiment (positive, neutral, negative, mixed)
           - Level of engagement (high, medium, low)
        3. Notable dynamics or observations about the group interaction

        Format your response EXACTLY like this:
        OVERALL TONE:
        <tone description>

        SPEAKERS:
        - <Speaker name>: <style> | Sentiment: <sentiment> | Engagement: <level>
        - <Speaker name>: <style> | Sentiment: <sentiment> | Engagement: <level>

        DYNAMICS:
        - <observation 1>
        - <observation 2>

        If the transcript is in Arabic or mixed Arabic/English, provide the analysis in English.

        TRANSCRIPT:
        \(text)
        """
    }

    // MARK: - Response Parsing

    private func parseSummaryResponse(_ response: String) -> MeetingSummary {
        var summary = ""
        var keyPoints: [String] = []
        var actionItems: [ActionItem] = []
        var decisions: [String] = []

        var currentSection = ""

        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("SUMMARY:") {
                currentSection = "summary"
                let inline = trimmed.replacingOccurrences(of: "SUMMARY:", with: "").trimmingCharacters(in: .whitespaces)
                if !inline.isEmpty { summary = inline }
            } else if trimmed.hasPrefix("KEY POINTS:") {
                currentSection = "keypoints"
            } else if trimmed.hasPrefix("ACTION ITEMS:") {
                currentSection = "actions"
            } else if trimmed.hasPrefix("DECISIONS:") {
                currentSection = "decisions"
            } else {
                let content = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
                switch currentSection {
                case "summary": summary += (summary.isEmpty ? "" : " ") + content
                case "keypoints": keyPoints.append(content)
                case "actions": actionItems.append(ActionItem(description: content, assignee: parseAssignee(content)))
                case "decisions": decisions.append(content)
                default: break
                }
            }
        }

        return MeetingSummary(
            summary: summary,
            keyPoints: keyPoints,
            actionItems: actionItems,
            decisions: decisions,
            generatedAt: Date()
        )
    }

    private func parseSentimentResponse(_ response: String, transcript: Transcript) -> MeetingSentiment {
        var overallTone = ""
        var speakerSentiments: [SpeakerSentiment] = []
        var dynamics: [String] = []

        var currentSection = ""

        for line in response.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("OVERALL TONE:") {
                currentSection = "tone"
                let inline = trimmed.replacingOccurrences(of: "OVERALL TONE:", with: "").trimmingCharacters(in: .whitespaces)
                if !inline.isEmpty { overallTone = inline }
            } else if trimmed.hasPrefix("SPEAKERS:") {
                currentSection = "speakers"
            } else if trimmed.hasPrefix("DYNAMICS:") {
                currentSection = "dynamics"
            } else {
                let content = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
                switch currentSection {
                case "tone": overallTone += (overallTone.isEmpty ? "" : " ") + content
                case "speakers":
                    if let sentiment = parseSpeakerSentiment(content) {
                        speakerSentiments.append(sentiment)
                    }
                case "dynamics": dynamics.append(content)
                default: break
                }
            }
        }

        return MeetingSentiment(
            overallTone: overallTone,
            speakers: speakerSentiments,
            dynamics: dynamics,
            generatedAt: Date()
        )
    }

    private func parseAssignee(_ text: String) -> String? {
        // Try to extract assignee from patterns like "John: do X" or "(assigned to John)"
        if let range = text.range(of: #"\(assigned to ([^)]+)\)"#, options: .regularExpression) {
            let match = text[range]
            return String(match).replacingOccurrences(of: "(assigned to ", with: "").replacingOccurrences(of: ")", with: "")
        }
        if let colonRange = text.range(of: ":") {
            let before = String(text[text.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if before.split(separator: " ").count <= 3 { return before }
        }
        return nil
    }

    private func parseSpeakerSentiment(_ text: String) -> SpeakerSentiment? {
        let parts = text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }

        // Parse "Speaker 1: collaborative style"
        let firstPart = parts[0]
        let nameAndStyle = firstPart.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        let name = nameAndStyle.first ?? "Unknown"
        let style = nameAndStyle.count > 1 ? nameAndStyle[1] : ""

        var sentiment = "neutral"
        var engagement = "medium"

        for part in parts.dropFirst() {
            let lower = part.lowercased()
            if lower.contains("sentiment") {
                sentiment = part.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces).lowercased() ?? "neutral"
            } else if lower.contains("engagement") {
                engagement = part.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces).lowercased() ?? "medium"
            }
        }

        return SpeakerSentiment(
            speaker: name,
            style: style,
            sentiment: sentiment,
            engagement: engagement
        )
    }
}

// MARK: - API Models

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
    struct OllamaModel: Decodable {
        let name: String
    }
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case ollamaNotRunning
    case modelNotFound(String)
    case requestFailed(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .ollamaNotRunning:
            return "Ollama is not running. Start it with: ollama serve"
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Pull it with: ollama pull \(model)"
        case .requestFailed(let msg):
            return "AI request failed: \(msg)"
        case .invalidURL:
            return "Invalid Ollama URL"
        }
    }
}
