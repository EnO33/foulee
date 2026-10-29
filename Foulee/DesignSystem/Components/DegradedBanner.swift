import FouleeKit
import SwiftUI

/// Something Foulée cannot do, and the button that fixes it (issue #611): one
/// look for every degraded state, wherever it shows — the home, an outing,
/// the weather sheet, Réglages.
struct DegradedBanner: View {
    let state: DegradedState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(FouleeColor.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: state.title)
                        .font(FouleeFont.footnote.weight(.semibold))
                    Text(verbatim: state.message)
                        .font(FouleeFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                if let remedy = state.remedy {
                    RemedyButton(remedy: remedy)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .fouleeGlass(cornerRadius: 16)
    }
}

/// The button that opens where a degraded state is fixed, alone for a screen
/// that already says what is missing, such as an empty chart.
struct RemedyButton: View {
    let remedy: DegradedState.Remedy

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(remedy.url)
        } label: {
            Text(verbatim: remedy.title)
                .font(FouleeFont.caption.weight(.semibold))
                .foregroundStyle(FouleeColor.accentMid)
        }
        .buttonStyle(.pressable)
    }
}

extension DegradedState.Remedy {
    /// The page the button opens.
    var url: URL {
        switch self {
        case .openHealth: AppLinks.health
        // A constant of UIKit's, always a valid URL.
        case .openSettings: URL(string: UIApplication.openSettingsURLString) ?? AppLinks.health
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(DegradedState.allCases, id: \.self) { DegradedBanner(state: $0) }
    }
    .padding()
}
