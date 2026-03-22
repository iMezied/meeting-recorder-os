import SwiftUI

@main
struct MeetingRecorderApp: App {
    @StateObject private var appState = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        Task { await AudioRecordingService.requestPermission() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.isRecording ? "record.circle.fill" : "mic.circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(appState.isRecording ? .red : .primary)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - AppDelegate manages the library window via NSWindow

class AppDelegate: NSObject, NSApplicationDelegate {
    private var libraryWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppState.shared.meetingDetector.startMonitoring()
        }
    }

    static var shared: AppDelegate {
        NSApplication.shared.delegate as! AppDelegate
    }

    func openLibraryWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = libraryWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = MainWindowView()
            .environmentObject(AppState.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Meeting Recorder"
        window.contentView = NSHostingView(rootView: contentView)
        window.minSize = NSSize(width: 860, height: 520)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        libraryWindow = window
    }

    static func openMainWindow() {
        AppDelegate.shared.openLibraryWindow()
    }

    static func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
