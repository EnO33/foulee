import SwiftUI

/// The big top card of the Today screen. Switches between
/// "marche à venir" and "marche terminée" presentations driven by
/// `snapshot.hasWalkedToday`. The bell next to the primary CTA opens
/// a menu to snooze the reminder or flip the global notifications
/// toggle without leaving the screen.
struct TodayHeroCard: View {
    var snapshot: TodaySnapshot
    var notificationsEnabled: Bool
    /// System permission is denied: the pref alone would lie ("activés" while
    /// iOS delivers nothing), so the bell surfaces the real state instead.
    var notificationsDenied: Bool
    var onStart: () -> Void
    var onSummary: () -> Void
    var onSnooze: (TimeInterval) -> Void
    var onToggleNotifications: () -> Void
    var onOpenNotificationSettings: () -> Void

    /// Step-goal fill (outer ring), clamped so overshoot doesn't wrap.
    private var stepsProgress: Double {
        guard snapshot.stepsGoal > 0 else { return 0 }
        return min(max(Double(snapshot.steps) / Double(snapshot.stepsGoal), 0), 1)
    }

    /// Activity-goal fill (inner ring). Full once the walk is marked done so
    /// the ring closes even if the logged minutes round just under the goal.
    private var minutesProgress: Double {
        if snapshot.hasWalkedToday { return 1 }
        guard snapshot.minutesGoal > 0 else { return 0 }
        return min(max(Double(snapshot.minutes) / Double(snapshot.minutesGoal), 0), 1)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                ring
                content
            }
            TodayGoalLegend(
                steps: snapshot.steps,
                stepsGoal: snapshot.stepsGoal,
                minutes: snapshot.minutes,
                minutesGoal: snapshot.minutesGoal
            )
            actionRow
        }
        .padding(22)
        .fouleeGlass(cornerRadius: 28)
    }

    private var ring: some View {
        DualProgressRing(outerProgress: stepsProgress, innerProgress: minutesProgress) {
            ringCenter
        }
        .frame(width: 128, height: 128)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progression du jour")
        .accessibilityValue(
            "Pas \(snapshot.steps.formattedFR) sur \(snapshot.stepsGoal.formattedFR), "
                + "activité \(snapshot.minutes) sur \(snapshot.minutesGoal) minutes"
        )
    }

    @ViewBuilder
    private var ringCenter: some View {
        if snapshot.hasWalkedToday {
            VStack(spacing: 2) {
                Image(systemName: FouleeIcon.check)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(FouleeColor.accentMid)
                Text("Fait")
                    .font(FouleeFont.footnote.weight(.semibold))
            }
        } else {
            Image(systemName: FouleeIcon.walk)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(FouleeColor.accentMid)
        }
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
        } else if snapshot.isRestDay {
            VStack(alignment: .leading, spacing: 10) {
                Chip(
                    label: "Jour de repos",
                    systemIcon: "moon.stars.fill",
                    tint: FouleeColor.accentSecondary,
                    fill: FouleeColor.accentSecondary.opacity(0.16)
                )
                Text("Pas de marche prévue aujourd'hui — profite de ta pause.")
                    .font(FouleeFont.title3)
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
            if snapshot.hasWalkedToday {
                // Already walked: still let the user start another walk — the
                // single "Voir le résumé" button used to be the only option.
                SecondaryButton(title: "Voir le résumé", systemIcon: FouleeIcon.sparkle, action: onSummary)
                PrimaryButton(title: "Marcher encore", systemIcon: FouleeIcon.play, action: onStart)
            } else {
                PrimaryButton(title: "Démarrer la marche", systemIcon: FouleeIcon.play, action: onStart)
                reminderMenu
            }
        }
    }

    /// The pref says on, but iOS won't deliver anything.
    private var remindersBlocked: Bool { notificationsEnabled && notificationsDenied }

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
            if remindersBlocked {
                Button {
                    onOpenNotificationSettings()
                } label: {
                    Label("Autoriser dans Réglages", systemImage: "gear")
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
            Image(systemName: notificationsEnabled && !remindersBlocked ? "bell.fill" : "bell.slash.fill")
                .font(.system(size: 20))
                .foregroundStyle(bellStyle)
                .frame(width: 50, height: 50)
                .background(Color.gray.opacity(0.16), in: Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Rappels de marche")
        .accessibilityValue(bellAccessibilityValue)
        .accessibilityHint("Reporter le rappel ou activer les rappels")
    }

    private var bellStyle: some ShapeStyle {
        if remindersBlocked { return AnyShapeStyle(.orange) }
        return notificationsEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    private var bellAccessibilityValue: String {
        if remindersBlocked { return "refusées dans Réglages" }
        return notificationsEnabled ? "activés" : "désactivés"
    }
}

private let frenchDecimalFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "fr_FR")
    formatter.numberStyle = .decimal
    return formatter
}()

extension Int {
    /// French-locale thousands grouping (`4218` → `"4 218"`). Uses a shared
    /// cached formatter — allocating a `NumberFormatter` per call is costly and
    /// this runs on every render of the step counters.
    var formattedFR: String {
        frenchDecimalFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
