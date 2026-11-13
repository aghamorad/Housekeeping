// Housekeeping — Permissions & System Doctor View
//
// Senior-friendly diagnostic dashboard checking file permissions, broken network connections,
// Gatekeeper quarantine flags, and background startup services.

import SwiftUI
import AppKit

struct PermissionsDoctorView: View {
    @Environment(\.uiStyle) private var style
    @EnvironmentObject private var appState: AppState
    @StateObject private var doctor = PermissionsDoctorEngine.shared

    @State private var selectedCategory: DoctorCategory?
    @State private var showRecommendations: Bool = true

    private var filteredIssues: [DoctorIssue] {
        if let cat = selectedCategory {
            return doctor.issues.filter { $0.category == cat }
        }
        return doctor.issues
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionToolbar
                recommendationCard

                if doctor.isScanning {
                    scanningBanner
                } else if doctor.issues.isEmpty {
                    allHealthyCard
                } else {
                    categoryFilterBar
                    issuesList
                }
            }
            .padding(24)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { HousekeepingBackdrop(style: style) }
        .task {
            if doctor.issues.isEmpty && doctor.lastScanDate == nil {
                await doctor.scanAll()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if let maintenanceMascot = HousekeeperMascot.loadMaintenance() {
                Image(nsImage: maintenanceMascot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
            } else {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(style.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Fix Permissions & System Doctor")
                        .font(style.isRetro ? style.titleFont : .system(size: 24, weight: .bold))
                        .foregroundStyle(style.text)

                    if !doctor.issues.isEmpty {
                        Text("\(doctor.issues.count) to review")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(style.caution.opacity(0.18)))
                            .foregroundStyle(style.caution)
                    }
                }

                Text("Audits file permissions (such as Gemini workspace configs), broken connections, Gatekeeper quarantine, and startup daemons.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }

            Spacer()

            if let last = doctor.lastScanDate {
                Text("Scanned \(last.formatted(date: .omitted, time: .shortened))")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText.opacity(0.8))
            }
        }
    }

    // MARK: - Action Toolbar

    private var actionToolbar: some View {
        HStack(spacing: 12) {
            let autoFixCount = doctor.issues.filter { $0.canAutoFix }.count

            ThemeButton(
                title: doctor.isFixing ? "Repairing…" : "Fix Recommended Issues (\(autoFixCount))",
                systemImage: "wand.and.stars",
                isPrimary: true,
                isEnabled: autoFixCount > 0 && !doctor.isFixing && !doctor.isScanning,
                help: "Safely restores user permissions on configuration folders, clears stuck proxies, and removes broken startup items."
            ) {
                Task { await doctor.fixAllRecommended() }
            }

            ThemeButton(
                title: doctor.isScanning ? "Scanning…" : "Scan Now",
                systemImage: "arrow.clockwise",
                isEnabled: !doctor.isScanning && !doctor.isFixing,
                help: "Re-run full diagnostics across permissions, network, Gatekeeper, and daemons."
            ) {
                Task { await doctor.scanAll() }
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showRecommendations.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(style.accent)
                    Text(showRecommendations ? "Hide Housekeeper Advice" : "What does Housekeeper Recommend?")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(style.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Recommendation Card

    @ViewBuilder
    private var recommendationCard: some View {
        if showRecommendations && !doctor.recommendationText.isEmpty {
            ThemePanel(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(style.accent)
                        Text("What does Housekeeper Recommend?")
                            .font(style.labelFont)
                            .foregroundStyle(style.text)
                        Spacer()
                    }

                    Text(doctor.recommendationText)
                        .font(style.bodyFont)
                        .foregroundStyle(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if let msg = doctor.fixMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(style.positive)
                Text(msg)
                    .font(style.smallFont)
                    .foregroundStyle(style.text)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.positive.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Scanning Banner

    private var scanningBanner: some View {
        ThemePanel(padding: 24) {
            HStack(spacing: 14) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Doctor is inspecting your Mac…")
                        .font(style.labelFont)
                    Text("Checking ~/.gemini and config folders, Wi-Fi proxies, Gatekeeper flags, and launch daemons.")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - All Healthy Card

    private var allHealthyCard: some View {
        ThemePanel(padding: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(style.positive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All Permissions & Connections Healthy")
                            .font(style.titleFont)
                            .foregroundStyle(style.text)
                        Text("No root-locked configuration folders, stuck network proxies, Gatekeeper flags, or broken daemons found.")
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(title: "All (\(doctor.issues.count))", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(DoctorCategory.allCases) { cat in
                    let count = doctor.issues.filter { $0.category == cat }.count
                    if count > 0 {
                        filterPill(title: "\(cat.rawValue) (\(count))", isSelected: selectedCategory == cat) {
                            selectedCategory = cat
                        }
                    }
                }
            }
        }
    }

    private func filterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? style.accent.opacity(0.25) : style.rowBackground, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? style.accent : style.border, lineWidth: 1))
                .foregroundStyle(isSelected ? style.text : style.secondaryText)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Issues List

    private var issuesList: some View {
        VStack(spacing: 12) {
            ForEach(filteredIssues) { issue in
                issueCard(issue)
            }
        }
    }

    private func issueCard(_ issue: DoctorIssue) -> some View {
        ThemePanel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: issue.category.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(issue.severity == .critical ? style.negative : style.caution)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(issue.title)
                                .font(style.labelFont)
                                .foregroundStyle(style.text)

                            Text(issue.severity.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(issue.severity == .critical ? style.negative.opacity(0.18) : style.caution.opacity(0.18)))
                                .foregroundStyle(issue.severity == .critical ? style.negative : style.caution)
                        }

                        Text(issue.detail)
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if let path = issue.path {
                            Text(path)
                                .font(style.pathFont)
                                .foregroundStyle(style.secondaryText.opacity(0.7))
                                .textSelection(.enabled)
                        }
                    }

                    Spacer()

                    if issue.canAutoFix {
                        ThemeButton(
                            title: "Fix This",
                            systemImage: "wrench.fill",
                            isPrimary: issue.severity == .critical,
                            isEnabled: !doctor.isFixing
                        ) {
                            Task { await doctor.fixSingle(issue: issue) }
                        }
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10))
                        .foregroundStyle(style.accent)
                    Text("Recommendation: \(issue.recommendedFix)")
                        .font(style.smallFont)
                        .foregroundStyle(style.accentLifted)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
