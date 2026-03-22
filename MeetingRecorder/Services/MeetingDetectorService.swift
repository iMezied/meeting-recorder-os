import Foundation
import AppKit

final class MeetingDetectorService: ObservableObject {
    @Published var detectedMeeting: MeetingSource?
    @Published var isMonitoring = false

    var onMeetingDetected: ((MeetingSource) -> Void)?
    var onMeetingEnded: (() -> Void)?

    private var pollTimer: Timer?
    private var wasInMeeting = false
    private let pollInterval: TimeInterval = 5.0

    private let processMap: [(processName: String, source: MeetingSource)] = [
        ("zoom.us", .zoom),
        ("CptHost", .zoom),
        ("Microsoft Teams", .teams),
        ("MSTeams", .teams),
        ("Microsoft Teams (work or school)", .teams),
    ]

    // MARK: - Monitoring Control

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkForMeetings()
        }
        checkForMeetings()
        print("[MeetingDetector] Monitoring started")
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        isMonitoring = false
        print("[MeetingDetector] Monitoring stopped")
    }

    // MARK: - Detection Logic

    private func checkForMeetings() {
        let detected = detectFromProcesses() ?? detectGoogleMeet()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let source = detected {
                if !self.wasInMeeting {
                    self.detectedMeeting = source
                    self.wasInMeeting = true
                    self.onMeetingDetected?(source)
                    print("[MeetingDetector] Meeting detected: \(source.displayName)")
                }
            } else {
                if self.wasInMeeting {
                    self.detectedMeeting = nil
                    self.wasInMeeting = false
                    self.onMeetingEnded?()
                    print("[MeetingDetector] Meeting ended")
                }
            }
        }
    }

    private func detectFromProcesses() -> MeetingSource? {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        for app in runningApps {
            guard app.isActive || app.activationPolicy == .regular else { continue }
            guard let name = app.localizedName ?? app.bundleIdentifier else { continue }

            for (processName, source) in processMap {
                if name.localizedCaseInsensitiveContains(processName) {
                    if source == .zoom {
                        return isZoomInMeeting() ? .zoom : nil
                    }
                    return source
                }
            }
        }

        return nil
    }

    private func isZoomInMeeting() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "CptHost"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func detectGoogleMeet() -> MeetingSource? {
        let browsers: [(app: String, script: String)] = [
            ("Google Chrome", chromeScript),
            ("Google Chrome Canary", chromeScript),
            ("Arc", arcScript),
            ("Safari", safariScript)
        ]

        for (appName, script) in browsers {
            if isBrowserRunning(appName), checkBrowserForMeet(script: script, app: appName) {
                return .googleMeet
            }
        }
        return nil
    }

    private func isBrowserRunning(_ appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == appName }
    }

    private func checkBrowserForMeet(script: String, app: String) -> Bool {
        let appleScript = NSAppleScript(source: script.replacingOccurrences(of: "{{APP}}", with: app))
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        return result?.stringValue?.contains("meet.google.com") == true
    }

    // MARK: - AppleScript Templates

    private var chromeScript: String {
        """
        tell application "{{APP}}"
            set tabURLs to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabURLs to tabURLs & URL of t & ","
                end repeat
            end repeat
            return tabURLs
        end tell
        """
    }

    private var safariScript: String {
        """
        tell application "Safari"
            set tabURLs to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabURLs to tabURLs & URL of t & ","
                end repeat
            end repeat
            return tabURLs
        end tell
        """
    }

    private var arcScript: String {
        """
        tell application "Arc"
            set tabURLs to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set tabURLs to tabURLs & URL of t & ","
                end repeat
            end repeat
            return tabURLs
        end tell
        """
    }

    deinit {
        stopMonitoring()
    }
}
