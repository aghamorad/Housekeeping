// Housekeeping — Animated Scanning & Progress Banner
//
// Displays the animated Housekeeper Octopus mascot with moving arms,
// tentacle wave motion, live file/step progress, reassurance badging,
// and senior-friendly large touch targets (75-Year-Old Rule).

import SwiftUI
import AppKit

/// A warm, reassuring, animated scanning banner featuring the Housekeeper Octopus mascot.
/// Displays animated arm and tentacle motion, live path discovery, step counters, and clear safety guarantees.
/// Used during Clean Up scanning, App Uninstaller scanning, and App Update querying.
struct HousekeeperScanningBanner: View {
    let title: String
    let subtitle: String
    var currentItem: String? = nil
    var stepCount: String? = nil
    var progressFraction: Double? = nil
    var onStop: (() -> Void)? = nil

    @Environment(\.uiStyle) private var style
    @State private var pulseAura = false

    var body: some View {
        HStack(spacing: 18) {
            // Animated Housekeeper Mascot
            ZStack {
                Circle()
                    .fill(style.accent.opacity(pulseAura ? 0.22 : 0.08))
                    .frame(width: 68, height: 68)
                    .scaleEffect(pulseAura ? 1.08 : 0.96)
                    .animation(HousekeepingMotion.breathe, value: pulseAura)

                if let cleaningMascot = HousekeeperMascot.loadClutterCleaning() ?? HousekeeperMascot.loadMacCleaning() {
                    Image(nsImage: cleaningMascot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 58, height: 58)
                        .offset(y: pulseAura ? -3 : 2)
                        .animation(HousekeepingMotion.breathe, value: pulseAura)
                        .shadow(color: style.accent.opacity(0.2), radius: 6, x: 0, y: 3)
                } else {
                    WorkingOctopus(size: 60, working: true)
                        .shadow(color: style.accent.opacity(0.2), radius: 6, x: 0, y: 3)
                }
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(style.isRetro ? style.titleFont : .system(size: 16, weight: .bold))
                        .foregroundStyle(style.text)

                    Spacer()

                    if let stepCount {
                        Text(stepCount)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(style.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(style.accent)
                    }
                }

                if let currentItem, !currentItem.isEmpty {
                    Text(currentItem)
                        .font(style.pathFont)
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text(subtitle)
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                }

                if let fraction = progressFraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [style.accentShaded, style.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(fraction))))
                        }
                    }
                    .frame(height: 5)
                }

                HStack(spacing: 8) {
                    Label("100% Safe & Read-Only · Nothing is moved or deleted without confirmation", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(style.accent)

                    Spacer()

                    if let onStop {
                        Button(action: onStop) {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop Scan")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Stop reading; results found so far remain visible.")
                    }
                }
            }
        }
        .padding(16)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(style.accent.opacity(0.35), lineWidth: 1)
        )
        .onAppear {
            pulseAura = true
        }
    }
}
