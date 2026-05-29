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

    /// 0 → 1 fill of the ring. Once the walk goal is hit for the day,
    /// the ring is full regardless of step count (the `hasWalkedToday`
    /// criterion is minute-based, but visually the user expects the
    /// circle closed once they're done). Pending state is clamped so a
    /// step count past the daily goal doesn't overshoot.
    private var progress: Double {
        if snapshot.hasWalkedToday { return 1 }
        guard snapshot.stepsGoal > 0 else { return 0 }
        let ratio = Double(snapshot.steps) / Double(snapshot.stepsGoal)
        return min(max(ratio, 0), 1)
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
                    label: countdownLabel,
                    systemIcon: FouleeIcon.timer,
                    tint: FouleeColor.accentMid,
                    fill: FouleeColor.accentMid.opacity(0.16)
                )
                windowSentence
                    .font(FouleeFont.title3)
                Text("Objectif : \(snapshot.minutesGoal) min · \(snapshot.stepsGoal.formattedFR) pas")
                    .font(FouleeFont.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Walk window countdown

    /// Minutes between `Date.now` and `snapshot.walkWindowStart` (today).
    /// Negative when the window already opened today.
    private var minutesUntilWindow: Int? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = snapshot.walkWindowStart.hour
        components.minute = snapshot.walkWindowStart.minute
        guard let windowStart = calendar.date(from: components) else { return nil }
        return Int(windowStart.timeIntervalSinceNow / 60)
    }

    private var formattedWindowStart: String {
        guard let hour = snapshot.walkWindowStart.hour,
              let minute = snapshot.walkWindowStart.minute else { return "—" }
        return String(format: "%02d:%02d", hour, minute)
    }

    private var countdownLabel: String {
        guard let minutes = minutesUntilWindow else { return "Marche du midi" }
        if minutes <= 0 { return "C'est l'heure de bouger" }
        if minutes < 60 { return "Marche dans \(minutes) min" }
        let hours = minutes / 60
        let remaining = minutes % 60
        if remaining == 0 { return "Marche dans \(hours) h" }
        return "Marche dans \(hours) h \(remaining)"
    }

    @ViewBuilder
    private var windowSentence: some View {
        let accent = Text(formattedWindowStart).foregroundStyle(FouleeColor.accentMid)
        if let minutes = minutesUntilWindow, minutes <= 0 {
            Text("Ta fenêtre est ouverte — départ depuis \(accent)")
        } else {
            Text("Ta fenêtre de marche s'ouvre à \(accent)")
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
