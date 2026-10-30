import FouleeKit
import SwiftUI

/// « Partager mon bilan » (issue #410): pick the shape, see the picture, send
/// it through the system share sheet with a one-line message.
///
/// The image is rendered here, once per format, rather than inside the share
/// button: `ShareLink` reads its item when the sheet opens, and a render on
/// that path would be redone on every body evaluation.
struct RecapShareSheet: View {
    let recap: Recap
    var onClose: () -> Void

    @State private var format = RecapShareFormat.square
    @State private var image: UIImage?

    private var card: RecapShareCard { RecapShareCard(recap: recap) }

    var body: some View {
        VStack(spacing: 18) {
            SheetHeader(eyebrow: "Partager", title: .verbatim(card.heading))
            Picker("Format", selection: $format) {
                ForEach(RecapShareFormat.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            preview
                .frame(maxHeight: .infinity)
            shareButton
        }
        .screenColumn()
        .padding(.top, 28)
        .padding(.bottom, 20)
        .overlay(alignment: .topTrailing) { SheetCloseButton(action: onClose) }
        .presentationBackground { SheetBackground() }
        .task(id: format) { image = RecapShareRenderer.image(of: recap, as: format) }
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .accessibilityLabel("Aperçu de l'image partagée : \(card.summary)")
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let image {
            let picture = Image(uiImage: image)
            ShareLink(
                item: picture,
                subject: Text(card.heading),
                message: Text(card.message),
                preview: SharePreview("\(card.heading) · \(card.periodTitle)", image: picture)
            ) {
                Label("Partager", systemImage: "square.and.arrow.up")
                    .font(FouleeFont.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(FouleeColor.buttonGradient, in: Capsule())
                    .shadow(color: FouleeColor.accentMid.opacity(0.35), radius: 12, x: 0, y: 8)
            }
            .buttonStyle(.pressable)
        }
    }
}
