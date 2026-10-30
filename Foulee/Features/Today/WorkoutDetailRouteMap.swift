import FouleeKit
import MapKit
import SwiftUI

/// The outing's route at the head of the detail, each leg in its activity's
/// colour (issue #319).
///
/// **A picture in the scroll view, a map once tapped.** The detail scrolls,
/// and a live map would take every vertical drag for itself; so the card
/// draws without interaction, and a tap opens the same route full screen,
/// where it can be panned and zoomed.
///
/// Full screen, **a tap on a line names its leg** (#319): sport, times,
/// distance, pace. A tap rather than a drag, because dragging is what moves
/// the map.
///
/// **A numbered pastille at each kilometre, an arrow between two** (#452), so
/// a loop — whose start and finish meet — still says which way it went. Full
/// screen, the arrows turn with the map.
///
/// Absent when no leg has a route: the detail says nothing rather than
/// showing an empty map.
struct WorkoutDetailRouteMap: View {
    /// The workouts the segments were read from, for the figures a tap shows.
    let legs: [WorkoutSummary]

    @State private var isExpanded = false
    @State private var selectedID: UUID?
    /// The full-screen map's heading, which the arrows make up for.
    @State private var heading: Double = 0

    /// Built once: the conversion walks every point of the route.
    private let strokes: [RouteLines.Stroke]
    private let activities: [RecordedActivity]
    private let kilometres: [RouteMarks.Mark]
    private let arrows: [RouteMarks.Mark]

    init(route: [RouteSegment], legs: [WorkoutSummary]) {
        self.legs = legs
        self.strokes = route.map { segment in
            RouteLines.Stroke(
                id: segment.id,
                coordinates: segment.coordinates.map(\.locationCoordinate),
                tint: segment.activity.tint
            )
        }
        self.activities = route.map(\.activity).firstOccurrences
        self.kilometres = RouteMarks.kilometres(along: route.map(\.coordinates))
        self.arrows = RouteMarks.arrows(along: route.map(\.coordinates))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { isExpanded = true } label: {
                map(interactive: false)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    // The map itself must not see the touch — it would claim
                    // the scroll view's drags — but the button must: without a
                    // content shape of its own, a label that refuses hit
                    // testing leaves the button nothing to be tapped on.
                    .allowsHitTesting(false)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Parcours de la sortie")
            .accessibilityHint("Ouvre la carte en plein écran")
            if activities.count > 1 {
                legend
            }
        }
        .padding(14)
        .fouleeGlass(cornerRadius: 22)
        .sheet(isPresented: $isExpanded, onDismiss: { selectedID = nil }, content: { expanded })
    }

    private func map(interactive: Bool) -> some View {
        Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
            RouteLines(strokes: strokes, highlighted: interactive ? selectedID : nil)
            ForEach(Array(arrows.enumerated()), id: \.offset) { _, arrow in
                Annotation("", coordinate: arrow.coordinate.locationCoordinate, anchor: .center) {
                    RouteArrow(bearing: arrow.bearing - (interactive ? heading : 0))
                }
                .annotationTitles(.hidden)
            }
            ForEach(Array(kilometres.enumerated()), id: \.offset) { index, mark in
                Annotation(String(localized: "Kilomètre \(index + 1)"), coordinate: mark.coordinate.locationCoordinate, anchor: .center) {
                    KilometrePastille(number: index + 1)
                }
                .annotationTitles(.hidden)
            }
            if let end = strokes.last?.coordinates.last {
                Annotation(String(localized: "Arrivée"), coordinate: end) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.75), in: Circle())
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    /// Pick the line under the finger, or clear the pick when the tap missed
    /// every line. The route is projected at tap time, so the tolerance is in
    /// points at whatever zoom the map is at.
    private func select(at location: CGPoint, with proxy: MapProxy) {
        let projected = strokes.map { stroke in
            stroke.coordinates.compactMap { proxy.convert($0, to: .local) }
        }
        selectedID = RouteHitTest.nearestStroke(to: location, among: projected).map { strokes[$0].id }
    }

    private var selectedLeg: WorkoutSummary? {
        selectedID.flatMap { id in legs.first { $0.id == id } }
    }

    /// The picked leg's figures, or the hint that a tap gives them.
    @ViewBuilder
    private var selectionCard: some View {
        if let leg = selectedLeg {
            HStack(spacing: 12) {
                Image(systemName: leg.activity.icon)
                    .scaledSystemFont(size: 18, weight: .semibold)
                    .foregroundStyle(leg.activity.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(leg.activity.label)
                        .font(FouleeFont.headline)
                    Text(OutingBreakdown.legText(leg))
                        .font(FouleeFont.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(leg.durationSeconds.walkClockText)
                    .scaledNumericFont(size: 18, weight: .semibold)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([leg.activity.label, OutingBreakdown.legSpokenText(leg)].joined(separator: ", "))
        } else if legs.count > 1 {
            Text("Touche une portion pour son détail")
                .font(FouleeFont.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
    }

    /// Which colour is which. Glyph and word with every swatch: the colour is
    /// never the only thing saying which sport a line was.
    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(activities, id: \.self) { activity in
                HStack(spacing: 6) {
                    Capsule()
                        .fill(activity.tint)
                        .frame(width: 18, height: 5)
                    Image(systemName: activity.icon)
                        .scaledSystemFont(size: 12, weight: .semibold)
                        .foregroundStyle(activity.tint)
                    Text(activity.label)
                        .font(FouleeFont.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Légende : \(activities.map(\.label).formatted(.list(type: .and).locale(.app)))"))
    }

    private var expanded: some View {
        ZStack(alignment: .topTrailing) {
            MapReader { proxy in
                map(interactive: true)
                    .onMapCameraChange(frequency: .continuous) { heading = $0.camera.heading }
                    // Simultaneous, not `onTapGesture`: the map's own
                    // recognisers (pan, double-tap zoom) win over a plain tap
                    // handler, which then never fires — verified by driving the
                    // screen from a UI test.
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            select(at: value.location, with: proxy)
                        }
                    )
            }
            .ignoresSafeArea()
            SheetCloseButton(accessibilityLabel: "Fermer la carte") { isExpanded = false }
        }
        // On the screen's safe area, not the map's full-bleed frame: the card
        // keeps clear of the home indicator, and of the camera and hinge
        // margins on the iPhone Duo's inner screen (#663).
        .overlay(alignment: .bottom) {
            selectionCard
                .screenColumn(gutter: 16)
                .padding(.bottom, 12)
        }
    }
}

/// A kilometre's number on the route (#452), in the finish flag's colours.
private struct KilometrePastille: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(Color.black.opacity(0.75), in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .accessibilityLabel("Kilomètre \(number)")
    }
}

/// Which way the route runs (#452): `bearing` in degrees clockwise from the
/// top of the map.
private struct RouteArrow: View {
    let bearing: Double

    var body: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 1.5)
            .rotationEffect(.degrees(bearing))
            .accessibilityHidden(true)
    }
}
