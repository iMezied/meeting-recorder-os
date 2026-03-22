import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting
    @EnvironmentObject var appState: AppState
    @State private var transcript: Transcript?
    @State private var summary: MeetingSummary?
    @State private var sentiment: MeetingSentiment?
    @State private var notesText: String = ""
    @State private var selectedTab: DetailTab = .transcript
    @State private var searchText = ""
    @State private var selectedModel: String = ""
    @State private var availableModels: [String] = []
    @State private var notesSaveTimer: Timer?
    @State private var notesUnsaved = false

    enum DetailTab: String, CaseIterable {
        case transcript = "Transcript"
        case summary = "Summary"
        case sentiment = "Sentiment"
        case notes = "Notes"
        case info = "Info"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            tabBar
            Divider()

            switch selectedTab {
            case .transcript: transcriptView
            case .summary: summaryView
            case .sentiment: sentimentView
            case .info: infoView
            }
        }
        .onAppear {
            loadData()
            availableModels = appState.transcriptionService.availableModels()
            selectedModel = appState.whisperModelSize
        }
        .onChange(of: meeting.id) {
            loadData()
            selectedModel = appState.whisperModelSize
        }
        .onChange(of: meeting.transcriptPath) { loadData() }
        .onChange(of: meeting.summaryPath) { loadData() }
        .onChange(of: meeting.sentimentPath) { loadData() }
        .onChange(of: meeting.status) { loadData() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: meeting.source.iconName)
                    .font(.title3).foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.displayTitle)
                    .font(.headline).lineLimit(1)
                HStack(spacing: 10) {
                    Text(meeting.formattedDuration).font(.caption).foregroundStyle(.secondary)
                    Text(formatDate(meeting.date)).font(.caption).foregroundStyle(.secondary)
                    StatusBadge(status: meeting.status)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                // Model picker
                if !availableModels.isEmpty {
                    Picker("", selection: $selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .frame(width: 100)
                    .controlSize(.small)
                }

                // Transcribe / Re-transcribe button
                if !appState.isTranscribing {
                    Button(action: {
                        Task {
                            await appState.transcribe(meeting: meeting, modelSize: selectedModel)
                        }
                    }) {
                        Label(
                            transcript != nil ? "Re-transcribe" : "Transcribe",
                            systemImage: "text.badge.plus"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Menu {
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(meeting.audioPath, inFileViewerRootedAtPath: meeting.directoryURL.path)
                    }
                    if transcript != nil {
                        Button("Export Transcript (.txt)") { exportTranscript() }
                        Button("Copy Transcript") { copyTranscript() }
                    }
                    Divider()
                    Button("Delete Meeting", role: .destructive) { appState.deleteMeeting(meeting) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 6) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                        Rectangle()
                            .fill(selectedTab == tab ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 100)
            }
            Spacer()
        }
        .padding(.leading, 16)
    }

    // MARK: - Transcript View

    @ViewBuilder
    private var transcriptView: some View {
        if appState.isTranscribing {
            VStack(spacing: 16) {
                ProgressView(value: appState.transcriptionProgress).tint(.blue).frame(width: 200)
                Text("Transcribing... \(Int(appState.transcriptionProgress * 100))%")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let transcript, !transcript.segments.isEmpty {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary.opacity(0.6))
                    TextField("Search transcript...", text: $searchText)
                        .textFieldStyle(.plain).font(.callout)
                }
                .padding(10)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(8)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                // Segments
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSegments) { segment in
                            HStack(alignment: .top, spacing: 10) {
                                Text(formatTimestamp(segment.startTime))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .frame(width: 42, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 3) {
                                    if let speaker = segment.speaker {
                                        Text(speaker)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(speakerColor(speaker))
                                    }
                                    Text(highlightText(segment.text))
                                        .font(.callout)
                                        .lineSpacing(5)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)

                            Divider().padding(.leading, 76)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        } else if transcript != nil && transcript!.segments.isEmpty {
            // Transcript exists but produced no segments — offer re-transcription
            VStack(spacing: 16) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 44)).foregroundStyle(.orange.opacity(0.6))
                Text("Transcript is empty").font(.headline).foregroundStyle(.secondary)
                Text("Try a different model for better results.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Re-transcribe") {
                    Task { await appState.transcribe(meeting: meeting, modelSize: selectedModel) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if meeting.status == .recorded || transcript == nil {
            VStack(spacing: 16) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                Text("No transcript yet").font(.headline).foregroundStyle(.secondary)
                Button("Transcribe Now") {
                    Task { await appState.transcribe(meeting: meeting, modelSize: selectedModel) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                Text("Transcript unavailable").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Summary View

    @ViewBuilder
    private var summaryView: some View {
        if appState.isSummarizing {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Generating summary...").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let summary {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Summary
                    InfoSection(title: "Summary") {
                        Text(summary.summary)
                            .font(.callout).lineSpacing(4).textSelection(.enabled)
                    }

                    // Key Points
                    if !summary.keyPoints.isEmpty {
                        InfoSection(title: "Key Points") {
                            ForEach(summary.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Color.blue).frame(width: 6, height: 6).padding(.top, 6)
                                    Text(point).font(.callout).textSelection(.enabled)
                                }
                            }
                        }
                    }

                    // Action Items
                    if !summary.actionItems.isEmpty {
                        InfoSection(title: "Action Items") {
                            ForEach(summary.actionItems) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checklist").foregroundStyle(.orange).font(.caption)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.description).font(.callout).textSelection(.enabled)
                                        if let assignee = item.assignee {
                                            Text("Assigned to: \(assignee)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Decisions
                    if !summary.decisions.isEmpty {
                        InfoSection(title: "Decisions") {
                            ForEach(summary.decisions, id: \.self) { decision in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                                    Text(decision).font(.callout).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        } else if transcript != nil {
            VStack(spacing: 16) {
                Image(systemName: "text.badge.star")
                    .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                Text("No summary yet").font(.headline).foregroundStyle(.secondary)
                Text("Requires Ollama running locally with a language model.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Generate Summary") { Task { await appState.summarize(meeting: meeting) } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "text.badge.star")
                    .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                Text("Transcribe the meeting first").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sentiment View

    @ViewBuilder
    private var sentimentView: some View {
        if appState.isAnalyzingSentiment {
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Analyzing sentiment...").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let sentiment {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Overall Tone
                    InfoSection(title: "Overall Tone") {
                        Text(sentiment.overallTone)
                            .font(.callout).lineSpacing(4).textSelection(.enabled)
                    }

                    // Speaker Analysis
                    if !sentiment.speakers.isEmpty {
                        InfoSection(title: "Speaker Analysis") {
                            ForEach(sentiment.speakers) { speaker in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(speaker.speaker)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(speakerColor(speaker.speaker))
                                    HStack(spacing: 16) {
                                        Label(speaker.sentiment.capitalized, systemImage: sentimentIcon(speaker.sentiment))
                                            .font(.caption)
                                            .foregroundStyle(sentimentColor(speaker.sentiment))
                                        Label(speaker.engagement.capitalized, systemImage: "chart.bar.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !speaker.style.isEmpty {
                                        Text(speaker.style)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                if speaker.id != sentiment.speakers.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }

                    // Group Dynamics
                    if !sentiment.dynamics.isEmpty {
                        InfoSection(title: "Group Dynamics") {
                            ForEach(sentiment.dynamics, id: \.self) { observation in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(Color.purple).frame(width: 6, height: 6).padding(.top, 6)
                                    Text(observation).font(.callout).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        } else if transcript != nil {
            VStack(spacing: 16) {
                Image(systemName: "person.3.sequence")
                    .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                Text("No sentiment analysis yet").font(.headline).foregroundStyle(.secondary)
                Text("Requires Ollama running locally with a language model.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Analyze Sentiment") { Task { await appState.analyzeSentiment(meeting: meeting) } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "person.3.sequence")
                    .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                Text("Transcribe the meeting first").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Info View

    private var infoView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InfoSection(title: "Recording") {
                    InfoRow(label: "Source", value: meeting.source.displayName)
                    InfoRow(label: "Duration", value: meeting.formattedDuration)
                    InfoRow(label: "Date", value: formatDate(meeting.date))
                    InfoRow(label: "Status", value: meeting.status.displayText)
                }
                InfoSection(title: "Files") {
                    InfoRow(label: "Audio", value: meeting.audioPath)
                    if let p = meeting.transcriptPath { InfoRow(label: "Transcript", value: p) }
                }
                if let t = transcript {
                    InfoSection(title: "Transcript Details") {
                        InfoRow(label: "Segments", value: "\(t.segments.count)")
                        InfoRow(label: "Language", value: t.language)
                        InfoRow(label: "Model", value: t.modelUsed)
                        InfoRow(label: "Words", value: "\(t.fullText.split(separator: " ").count)")
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    private var filteredSegments: [TranscriptSegment] {
        guard let transcript else { return [] }
        if searchText.isEmpty { return transcript.segments }
        return transcript.segments.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadData() {
        if let path = meeting.transcriptPath {
            transcript = appState.storageService.loadTranscript(from: path)
        } else { transcript = nil }

        if let path = meeting.summaryPath {
            summary = appState.storageService.loadSummary(from: path)
        } else { summary = nil }

        if let path = meeting.sentimentPath {
            sentiment = appState.storageService.loadSentiment(from: path)
        } else { sentiment = nil }
    }

    private let speakerColors: [Color] = [.blue, .orange, .green, .purple, .pink, .cyan, .brown, .mint]

    private func speakerColor(_ speaker: String) -> Color {
        // Extract number from "Speaker N" or hash the name
        if let numStr = speaker.split(separator: " ").last, let num = Int(numStr) {
            return speakerColors[(num - 1) % speakerColors.count]
        }
        return speakerColors[abs(speaker.hashValue) % speakerColors.count]
    }

    private func sentimentIcon(_ sentiment: String) -> String {
        switch sentiment.lowercased() {
        case "positive": return "face.smiling"
        case "negative": return "face.dashed"
        case "mixed": return "face.smiling.inverse"
        default: return "minus.circle"
        }
    }

    private func sentimentColor(_ sentiment: String) -> Color {
        switch sentiment.lowercased() {
        case "positive": return .green
        case "negative": return .red
        case "mixed": return .orange
        default: return .secondary
        }
    }

    private func highlightText(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        guard !searchText.isEmpty else { return attr }
        var range = attr.startIndex..<attr.endIndex
        while let found = attr[range].range(of: searchText, options: .caseInsensitive) {
            attr[found].backgroundColor = .yellow.opacity(0.3)
            attr[found].font = .callout.bold()
            range = found.upperBound..<attr.endIndex
        }
        return attr
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f.string(from: date)
    }

    private func formatTimestamp(_ s: Double) -> String {
        String(format: "%02d:%02d", Int(s) / 60, Int(s) % 60)
    }

    private func exportTranscript() {
        guard let transcript else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(meeting.displayTitle).txt"
        panel.begin { r in
            guard r == .OK, let url = panel.url else { return }
            try? transcript.formattedText.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func copyTranscript() {
        guard let transcript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.formattedText, forType: .string)
    }
}

struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
        }
    }
}

struct InfoRow: View {
    let label: String; let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
            Text(value).font(.subheadline).textSelection(.enabled)
        }
    }
}
