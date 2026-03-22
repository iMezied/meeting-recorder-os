import SwiftUI

/// Minimal menu bar dropdown — recording controls only.
/// Meeting list lives in the full library window.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Meeting Recorder")
                    .font(.headline)
                Spacer()
                // Monitoring indicator
                if appState.meetingDetector.isMonitoring {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("Monitoring")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Recording controls
            VStack(spacing: 12) {
                if appState.isRecording {
                    recordingView
                } else if appState.isTranscribing {
                    transcribingView
                } else {
                    idleView
                }
            }
            .padding(16)

            Divider()

            // Actions
            VStack(spacing: 2) {
                Button {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        AppDelegate.openMainWindow()
                    }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Meeting Library")
                        Spacer()
                        if !appState.meetings.isEmpty {
                            Text("\(appState.meetings.count)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .cornerRadius(8)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .padding(.vertical, 8)

            Divider()

            // Footer
            HStack {
                SettingsLink {
                    Text("Settings...")
                        .font(.caption)
                }
                .onHover { _ in }
                .simultaneousGesture(TapGesture().onEnded {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        for window in NSApplication.shared.windows {
                            if window.title.contains("Settings") || window.title.contains("Preferences") {
                                window.makeKeyAndOrderFront(nil)
                                window.orderFrontRegardless()
                            }
                        }
                    }
                })

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
        .task {
            await AudioRecordingService.requestPermission()
        }
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 10) {
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10)
                    .modifier(PulseAnimation())
                Text("Recording")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                Spacer()
                Text(formatDuration(appState.recordingDuration))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Audio level
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(appState.recordingLevel))
                        .animation(.easeOut(duration: 0.1), value: appState.recordingLevel)
                }
            }
            .frame(height: 6)

            HStack {
                Image(systemName: appState.currentMeetingSource.iconName)
                Text(appState.currentMeetingSource.displayName)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }

            Button(action: { Task { await appState.stopRecording() } }) {
                HStack { Image(systemName: "stop.fill"); Text("Stop Recording") }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(.red)
        }
    }

    private var transcribingView: some View {
        VStack(spacing: 10) {
            HStack {
                ProgressView().scaleEffect(0.7)
                Text("Transcribing...").font(.subheadline.bold())
                Spacer()
                Text("\(Int(appState.transcriptionProgress * 100))%")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            ProgressView(value: appState.transcriptionProgress).tint(.blue)
        }
    }

    private var idleView: some View {
        VStack(spacing: 10) {
            Button(action: { Task { await appState.toggleRecording() } }) {
                HStack { Image(systemName: "record.circle"); Text("Start Recording") }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600; let m = (Int(seconds) % 3600) / 60; let s = Int(seconds) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false
    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
