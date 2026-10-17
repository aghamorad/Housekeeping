// Housekeeping — the check that runs without being asked
//
// The setup screen is a place the reader goes. This file is the other half of
// monitoring: once a week, quietly, the app reads the same facts in the
// background and says something only when the answer has changed for the worse.
//
// The rules for a background check are stricter than for an opened screen. It
// never changes anything, it never opens a window, and it does not use the
// network — the maintenance checks are excluded, because a weekly question is
// not a reason to spend someone's connection. If it finds something that is
// broken or running the wrong copy, it posts one local notification; if it
// finds only untidiness, it records the reading and says nothing.

import Foundation
import UserNotifications

@MainActor
extension AppState {

    /// Seven days, in seconds. The check is deliberately not more frequent: the
    /// setup does not change on its own, and a monitor that speaks often is one
    /// that gets ignored.
    private static var terminalHealthInterval: TimeInterval { 7 * 24 * 60 * 60 }
    private static let lastTerminalHealthReadKey = "housekeeping.terminalHealth.lastRead"

    /// Called once when the main window appears. Cheap when it is not due: one
    /// UserDefaults read.
    func runWeeklyTerminalHealthCheckIfNeeded() {
        let last = UserDefaults.standard.double(forKey: Self.lastTerminalHealthReadKey)
        let now = Date().timeIntervalSince1970
        guard last == 0 || now - last >= Self.terminalHealthInterval else { return }
        // The first reading is a baseline, not news: the reader is looking at the
        // app already, and a notification about a setup they have never seen
        // checked would arrive before they know what it refers to.
        let isFirstReading = last == 0
        guard !environmentIsReading, !environmentIsWorking else { return }

        // Written before the reading starts, so a crash during it cannot make
        // every launch try again.
        UserDefaults.standard.set(now, forKey: Self.lastTerminalHealthReadKey)

        Task { [weak self] in
            guard let self else { return }
            let runner = ProcessRunner()
            let report = await EnvironmentAudit(
                runner: runner,
                homePath: NSHomeDirectory(),
                brewPath: ProcessRunner.brewPath()
            ).run(includeMaintenance: false)

            if Task.isCancelled { return }

            self.recordEnvironmentHistory(
                kind: .scan,
                summary: "Weekly background check: " + Self.describe(report),
                detail: report.findings.prefix(20).map { "\($0.severity.label): \($0.title)" }
            )

            guard !isFirstReading else { return }
            let attention = report.findings.filter { $0.severity != .untidy }
            guard !attention.isEmpty else { return }
            await self.postTerminalHealthNotification(
                count: attention.count,
                first: attention[0].title
            )
        }
    }

    /// Re-reads the setup and records that reading as a verification. The rows
    /// on screen are replaced exactly as they are by a Check; the difference is
    /// only what the history says the reading was for.
    func verifyTerminalHealth() {
        guard !environmentIsReading, !environmentIsWorking else { return }
        let task = beginSetupReading()
        Task { [weak self] in
            await task?.value
            guard let self, !Task.isCancelled else { return }
            self.recordEnvironmentHistory(
                kind: .verification,
                summary: "Verified: " + Self.describe(EnvironmentReport(
                    findings: self.environmentFindings,
                    notes: self.environmentNotes
                )),
                detail: self.environmentFindings.prefix(20).map { "\($0.severity.label): \($0.title)" }
            )
        }
    }

    func recordEnvironmentHistory(
        kind: EnvironmentHistoryEntry.Kind,
        summary: String,
        detail: [String] = []
    ) {
        environmentHistory.record(kind: kind, summary: summary, detail: detail)
        environmentHistoryEntries = environmentHistory.entries
    }

    static func describe(_ report: EnvironmentReport) -> String {
        let broken = report.findings.filter { $0.severity == .broken }.count
        let shadowed = report.findings.filter { $0.severity == .shadowed }.count
        let untidy = report.findings.filter { $0.severity == .untidy }.count

        if report.findings.isEmpty { return "nothing found." }
        var parts: [String] = []
        if broken > 0 { parts.append("\(broken) not working") }
        if shadowed > 0 { parts.append("\(shadowed) running a different copy") }
        if untidy > 0 { parts.append("\(untidy) untidy") }
        return parts.joined(separator: ", ") + "."
    }

    private func postTerminalHealthNotification(count: Int, first: String) async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Terminal Health needs a look"
        content.body = count == 1
            ? first
            : "\(count) things need attention — \(first), and others."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "housekeeping.terminal-health",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
