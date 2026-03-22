import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Top bar (replaces toolbar since we're in NSWindow)
            HStack(spacing: 12) {
                Text("Meeting Recorder")
                    .font(.headline)

                Spacer()

                // Monitoring toggle
                Button(action: {
                    if appState.meetingDetector.isMonitoring {
                        appState.meetingDetector.stopMonitoring()
                    } else {
                        appState.meetingDetector.startMonitoring()
                    }
                }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.meetingDetector.isMonitoring ? .green : .gray.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(appState.meetingDetector.isMonitoring ? "Monitoring" : "Auto-detect off")
                            .font(.caption)
                            .foregroundStyle(appState.meetingDetector.isMonitoring ? .secondary : .secondary.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                // Recording button
                Button(action: { Task { await appState.toggleRecording() } }) {
                    HStack(spacing: 5) {
                        if appState.isRecording {
                            Image(systemName: "stop.fill").font(.caption).foregroundStyle(.white)
                            Text("Stop").font(.caption.weight(.medium)).foregroundStyle(.white)
                        } else {
                            Image(systemName: "record.circle").font(.caption).foregroundStyle(.white)
                            Text("Record").font(.caption.weight(.medium)).foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(appState.isRecording ? Color.red : Color.accentColor)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.04))

            Divider()

            // Main content
            HSplitView {
                SidebarView()
                    .frame(minWidth: 240, idealWidth: 260, maxWidth: 320)

                if let meeting = appState.selectedMeeting {
                    MeetingDetailView(meeting: meeting)
                        .frame(minWidth: 500)
                        .id(meeting.id)
                } else {
                    EmptyStateView()
                        .frame(minWidth: 500)
                }
            }
        }
        .onAppear {
            NotificationHelper.requestPermission()
            Task { await AudioRecordingService.requestPermission() }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var filterSource: MeetingSource?

    private var filteredMeetings: [Meeting] {
        appState.meetings.filter { meeting in
            let matchesSearch = searchText.isEmpty
                || meeting.displayTitle.localizedCaseInsensitiveContains(searchText)
            let matchesFilter = filterSource == nil || meeting.source == filterSource
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack(spacing: 8) {
                if appState.meetingDetector.isMonitoring {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Monitoring").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Circle().fill(.gray.opacity(0.4)).frame(width: 6, height: 6)
                    Text("Idle").font(.caption2).foregroundStyle(.secondary.opacity(0.6))
                }
                Spacer()
                if appState.isRecording {
                    Text("REC")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.04))

            Divider()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary.opacity(0.6))
                TextField("Search meetings...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(8)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    FilterChip(title: "All", isSelected: filterSource == nil) { filterSource = nil }
                    ForEach(MeetingSource.allCases, id: \.self) { source in
                        FilterChip(title: source.displayName, icon: source.iconName, isSelected: filterSource == source) {
                            filterSource = filterSource == source ? nil : source
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            Divider()

            // Meeting list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredMeetings) { meeting in
                        MeetingRowView(
                            meeting: meeting,
                            isSelected: appState.selectedMeetingID == meeting.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                appState.selectedMeetingID = meeting.id
                            }
                        }
                        .contextMenu {
                            if meeting.status == .recorded {
                                Button("Transcribe") {
                                    Task { await appState.transcribe(meeting: meeting) }
                                }
                            }
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(
                                    meeting.audioPath,
                                    inFileViewerRootedAtPath: meeting.directoryURL.path
                                )
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                appState.deleteMeeting(meeting)
                            }
                        }

                        if meeting.id != filteredMeetings.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Image(systemName: "internaldrive").font(.caption2)
                Text(appState.storageService.formattedStorageUsed()).font(.caption2)
                Spacer()
                Text("\(appState.meetings.count) meetings").font(.caption2)
            }
            .foregroundStyle(.secondary.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Meeting Row

struct MeetingRowView: View {
    let meeting: Meeting
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: meeting.source.iconName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                Text(meeting.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
            }

            // Transcript preview
            if let path = meeting.transcriptPath, let preview = loadPreview(from: path) {
                Text(preview)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.6) : .secondary.opacity(0.5))
                    .lineLimit(2)
            }

            HStack {
                Text(meeting.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                Spacer()
                StatusBadge(status: meeting.status, inverted: isSelected)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }

    private func loadPreview(from path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let preview = try? JSONDecoder().decode(PreviewTranscript.self, from: data) else { return nil }
        let text = preview.segments.prefix(3).map(\.text).joined(separator: " ")
        return text.count > 100 ? String(text.prefix(100)) + "..." : (text.isEmpty ? nil : text)
    }
}

private struct PreviewTranscript: Decodable {
    let segments: [PreviewSegment]
    struct PreviewSegment: Decodable { let text: String }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon { Image(systemName: icon).font(.system(size: 9)) }
                Text(title).font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
            )
            .foregroundStyle(isSelected ? .blue : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: MeetingStatus
    var inverted: Bool = false

    var body: some View {
        Text(status.displayText)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(inverted ? Color.white.opacity(0.2) : statusColor.opacity(0.15))
            )
            .foregroundStyle(inverted ? .white : statusColor)
    }

    private var statusColor: Color {
        switch status {
        case .recording: return .red
        case .recorded: return .orange
        case .transcribing: return .blue
        case .transcribed: return .green
        case .summarized: return .purple
        case .failed: return .gray
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("Select a meeting to view details")
                .font(.title3).foregroundStyle(.secondary)
            Text("Or press Record to start a new recording")
                .font(.caption).foregroundStyle(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
