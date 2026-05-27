import SwiftUI

/// The big top card of the Today screen. Switches between
/// "marche à venir" and "marche terminée" presentations driven by
/// `snapshot.hasWalkedToday`. The bell next to the primary CTA opens
/// a menu to snooze the reminder or flip the global notifications
/// toggle without leaving the screen.
struct TodayHeroCard: View {
    var snapshot: TodaySnapshot
    var notificationsEnabled: Bool
    var onPrimaryTap: () -> Void
    var onSnooze: (TimeInterval) -> Void
    var onToggleNotifications: () -> Void

    private var progress: Double {
        guard snapshot.stepsGoal > 0 else { return 0 }
        return snapshot.hasWalkedToday
            ? 0.86
            : Double(snapshot.steps) / Double(snapshot.stepsGoal)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                ring
                content
            }
            actionRow
        }
        .padding(22)
        .fouleeGlass(cornerRadius: 28)
    }

    private var ring: some View {
        ProgressRing(progress: progress, lineWidth: 11) {
            if snapshot.hasWalkedToday {
                VStack(spacing: 2) {
                    Image(systemName: FouleeIcon.check)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(FouleeColor.accentMid)
                    Text("Fait")
                        .font(FouleeFont.headline)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: FouleeIcon.walk)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(FouleeColor.accentMid)
                    Text(snapshot.steps.formattedFR)
                        .font(FouleeFont.numeric(size: 22))
                    Text("pas")
                        .font(FouleeFont.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 132, height: 132)
    }

    @ViewBuilder
    private var content: some View {
        if snapshot.hasWalkedToday {
            VStack(alignment: .leading, spacing: 10) {
                Chip(
                    label: "Marche terminée",
                    systemIcon: FouleeIcon.check,
                    tint: FouleeColor.success,
                    fill: FouleeColor.success.opacity(0.16)
                )
                Text("Bravo, \(Text("\(snapshot.minutes) min").foregroundStyle(FouleeColor.accentMid)) de marche")
                    .font(FouleeFont.title3)
                Text("Streak prolongée à \(snapshot.streak) jours")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Chip(
                    label: "Marche dans 18 min",
                    systemIcon: FouleeIcon.timer,
                    tint: FouleeColor.accentMid,
                    fill: FouleeColor.accentMid.opacity(0.16)
                )
                Text("Ta fenêtre de marche s'ouvre à \(Text("12:00").foregroundStyle(FouleeColor.accentMid))")
                    .font(FouleeFont.title3)
                Text("Objectif : \(snapshot.minutesGoal) min · \(2_000) pas")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            PrimaryButton(
                title: snapshot.hasWalkedToday ? "Voir le résumé" : "Démarrer la marche",
                systemIcon: snapshot.hasWalkedToday ? FouleeIcon.sparkle : FouleeIcon.play,
                action: onPrimaryTap
            )
            reminderMenu
        }
    }

    private var reminderMenu: some View {
        Menu {
            Section("Plus tard") {
                Button {
                    onSnooze(30 * 60)
                } label: {
                    Label("Dans 30 minutes", systemImage: "clock")
                }
                Button {
                    onSnooze(60 * 60)
                } label: {
                    Label("Dans 1 heure", systemImage: "clock")
                }
            }
            Button(role: notificationsEnabled ? .destructive : nil) {
                onToggleNotifications()
            } label: {
                Label(
                    notificationsEnabled ? "Désactiver les rappels" : "Activer les rappels",
                    systemImage: notificationsEnabled ? "bell.slash" : "bell"
                )
            }
        } label: {
            Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                .font(.system(size: 20))
                .foregroundStyle(notificationsEnabled ? .primary : .secondary)
                .frame(width: 50, height: 50)
                .background(Color.gray.opacity(0.16), in: Circle())
        }
        .menuOrder(.fixed)
    }
}

extension Int {
    /// French-locale thousands grouping (`4218` → `"4 218"`).
    var formattedFR: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
