import SwiftUI

struct MeetingDetailView: View {
    let meeting: Meeting
    @EnvironmentObject var appState: AppState
    @State private var transcript: Transcript?
    @State private var selectedTab: DetailTab = .transcript
    @State private var searchText = ""

    enum DetailTab: String, CaseIterable {
        case transcript = "Transcript"
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
            case .info: infoView
            }
        }
        .onAppear { loadTranscript() }
        .onChange(of: meeting.id) { loadTranscript() }
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

            HStack(spacing: 6) {
                if meeting.status == .recorded {
                    Button(action: { Task { await appState.transcribe(meeting: meeting) } }) {
                        Label("Transcribe", systemImage: "text.badge.plus")
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
                            HStack(alignment: .top, spacing: 14) {
                                Text(formatTimestamp(segment.startTime))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .frame(width: 42, alignment: .trailing)

                                Text(highlightText(segment.text))
                                    .font(.callout)
                                    .lineSpacing(5)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)

                            Divider().padding(.leading, 76)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        } else if meeting.status == .recorded {
            VStack(spacing: 16) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 44)).foregroundStyle(.secondary.opacity(0.4))
                Text("No transcript yet").font(.headline).foregroundStyle(.secondary)
                Button("Transcribe Now") { Task { await appState.transcribe(meeting: meeting) } }
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

    private func loadTranscript() {
        guard let path = meeting.transcriptPath else { transcript = nil; return }
        transcript = appState.storageService.loadTranscript(from: path)
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
