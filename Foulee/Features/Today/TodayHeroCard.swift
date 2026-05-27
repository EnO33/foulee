import SwiftUI

/// The big top card of the Today screen. Switches between
/// "marche à venir" and "marche terminée" presentations driven by
/// `snapshot.hasWalkedToday`.
struct TodayHeroCard: View {
    var snapshot: TodaySnapshot
    var onPrimaryTap: () -> Void
    var onReminderTap: () -> Void

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
            Button(action: onReminderTap) {
                Image(systemName: FouleeIcon.bell)
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.16), in: Circle())
            }
            .buttonStyle(.pressable)
        }
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
