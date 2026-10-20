import SkyKit
import SwiftUI

/// The aiming layer drawn over the live view.
///
/// Deliberately not a planetarium. At 2am, cold, with a shower peaking, the only questions
/// that matter are "am I pointed at the right patch of sky" and "how much do I turn". So
/// this shows an arrow, a distance, and the handful of landmarks worth confirming against —
/// nothing that needs reading.
struct SkyOverlayView: View {

    let plan: SkyDirector.Plan?
    let aim: HorizontalCoordinates
    /// Where the arrow leads: the plan's pick or the person's.
    let target: HorizontalCoordinates?
    let hasFix: Bool
    /// Showers and radiants — the events, which are Pro.
    let showsEvents: Bool
    /// The aim target and the arrow to it.
    let showsAim: Bool

    /// The lens's field of view across the sensor's long side.
    let fieldOfView: Double
    /// How far the image is turned about the lens axis — see `PreviewGeometry.imageRoll`.
    let imageRoll: Double
    /// The preview buffer as delivered, portrait. Its shape decides the letterbox.
    let buffer: CGSize
    /// The stars' correction to the field of view; 1 until the sky is locked.
    var fieldScale: Double = 1
    /// Markers placed from a plate solve of the live view, not from the compass alone.
    var isLocked = false

    /// The landmark last tapped, with where it was drawn and how many times in a row.
    @State private var tapped: StarTap?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // The tap layer sits under the markers and takes the whole frame; the
                // markers themselves never take a touch, so the hit area is a circle
                // around where each is drawn, not its label's bounding box.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        tap(at: point, in: geometry.size)
                    }
                Group {
                    if let plan, hasFix {
                        milkyWayBand(plan: plan, in: geometry.size)
                        landmarks(plan: plan, in: geometry.size)
                        if showsAim, let target {
                            targetMarker(target, in: geometry.size)
                        }
                    }
                    horizonLine(in: geometry.size)
                    if isLocked {
                        lockBadge(in: geometry.size)
                    }
                    guidanceOverlay
                    if let tapped {
                        StarInfoBubble(tap: tapped)
                            .position(x: tapped.point.x, y: max(60, tapped.point.y - 64))
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Tapping a star

    private func tap(at point: CGPoint, in size: CGSize) {
        guard let plan, hasFix else { return }
        let nearest = plan.landmarks
            .compactMap { landmark -> StarTap? in
                guard let drawn = project(landmark.direction, in: size) else { return nil }
                return StarTap(landmark: landmark, point: drawn, count: 1)
            }
            .min { $0.distance(to: point) < $1.distance(to: point) }
        guard var hit = nearest, hit.distance(to: point) < 32 else {
            tapped = nil
            return
        }
        if tapped?.landmark.name == hit.landmark.name { hit.count = (tapped?.count ?? 0) + 1 }
        tapped = hit
    }

    // MARK: - Projection

    /// A sky direction on the screen, by the plate solver's own camera model. See
    /// `PreviewGeometry` for the two errors the earlier flat sketch made.
    private func project(_ target: HorizontalCoordinates, in size: CGSize) -> CGPoint? {
        geometry(in: size).project(target)
    }

    private func geometry(in size: CGSize) -> PreviewGeometry {
        PreviewGeometry(
            aim: aim, imageRoll: imageRoll, lensFieldOfView: fieldOfView, buffer: buffer, view: size,
            fieldScale: fieldScale
        )
    }

    // MARK: - Layers

    /// The Milky Way as the band it is: the galactic equator joined point to point, heavier
    /// where the band is bright. Segments that leave the projection are simply not drawn,
    /// so the band fades at the edges instead of tearing across the screen.
    private func milkyWayBand(plan: SkyDirector.Plan, in size: CGSize) -> some View {
        let points = plan.milkyWay
        let projected = points.map { project($0.direction, in: size) }
        return ZStack {
            ForEach(points.indices, id: \.self) { index in
                let next = (index + 1) % points.count
                // Both ends on screen (with a margin), and no further apart than a 10°
                // step can honestly be: the projection is only a sketch past the edges, and
                // a segment to a badly placed point draws a line across the whole frame.
                if let from = projected[index], let to = projected[next],
                   points[index].direction.isAboveHorizon || points[next].direction.isAboveHorizon,
                   isNearScreen(from, in: size), isNearScreen(to, in: size),
                   hypot(to.x - from.x, to.y - from.y) < size.width * 0.5 {
                    let brightness = (points[index].brightness + points[next].brightness) / 2
                    let segment = Path { path in
                        path.move(to: from)
                        path.addLine(to: to)
                    }
                    // A soft wide glow for the band, and a faint crisp line so it still
                    // reads where the glow is too dim: the outer arm, or a bright horizon.
                    segment
                        .stroke(
                            NightTheme.secondary.opacity(0.35 + 0.5 * brightness),
                            style: StrokeStyle(lineWidth: 4 + 16 * brightness, lineCap: .round)
                        )
                        .blur(radius: 3 + 5 * brightness)
                    segment
                        .stroke(
                            NightTheme.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 5])
                        )
                }
            }
            if let core = projected.first.flatMap({ $0 }), plan.milkyWayCore.isAboveHorizon {
                Text("MILKY WAY")
                    .font(NightTheme.mono(9, weight: .semibold))
                    .foregroundStyle(NightTheme.secondary.opacity(0.9))
                    .skyLegible()
                    .position(x: core.x, y: core.y + 18)
            }
        }
    }

    private func isNearScreen(_ point: CGPoint, in size: CGSize) -> Bool {
        let margin: CGFloat = 60
        return point.x > -margin && point.x < size.width + margin
            && point.y > -margin && point.y < size.height + margin
    }

    private func landmarks(plan: SkyDirector.Plan, in size: CGSize) -> some View {
        ZStack {
            // Directions were resolved when the plan was built. This body re-runs at
            // display rate, and the only thing that changes between redraws is where the
            // phone points — not where the sky is.
            ForEach(plan.landmarks) { landmark in
                if let point = project(landmark.direction, in: size) {
                    landmarkMarker(landmark)
                        .position(point)
                }
            }

            // The Moon, when it is up, is the thing you are trying to keep out of frame.
            if plan.conditions.isMoonUp,
               let point = project(plan.conditions.moonPosition, in: size) {
                VStack(spacing: 2) {
                    Circle()
                        .strokeBorder(NightTheme.accent, lineWidth: 2)
                        .frame(width: 26, height: 26)
                    Text(String(
                        format: String(localized: "MOON %d%%"), Int(plan.conditions.moon.illuminatedFraction * 100)
                    ))
                        .font(NightTheme.mono(9))
                        .foregroundStyle(NightTheme.accent)
                }
                .position(point)
            }

            ForEach(Array(plan.showers.prefix(1).enumerated()), id: \.offset) { _, activity in
                if showsEvents, activity.radiant.isAboveHorizon,
                   let point = project(activity.radiant, in: size) {
                    radiantMarker(name: activity.shower.name)
                        .position(point)
                }
            }
        }
    }

    /// One marker for stars and planets alike — brighter objects get bigger dots, the way
    /// a printed chart plots them. Planets are ringed and carry their magnitude, since
    /// they are the ones you might aim a focus at.
    private func landmarkMarker(_ landmark: SkyDirector.Landmark) -> some View {
        let planet = landmark.isPlanet
        let color = planet ? NightTheme.accent : NightTheme.primary
        let diameter = planet
            ? max(7.0, 13.0 - landmark.magnitude * 1.5)
            : max(4.0, 9.0 - landmark.magnitude * 2.0)

        return VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.24))
                    .frame(width: diameter * 2.3, height: diameter * 2.3)
                Circle()
                    .fill(color)
                    .frame(width: diameter, height: diameter)
                if planet {
                    Circle()
                        .stroke(color.opacity(0.7), lineWidth: 1)
                        .frame(width: diameter * 1.7, height: diameter * 1.7)
                }
            }
            Text(landmark.name.uppercased())
                .font(NightTheme.mono(planet ? 10 : 9, weight: planet ? .bold : .medium))
                .foregroundStyle(planet ? color : color.opacity(0.9))
                .skyLegible()
            if planet {
                Text(String(format: "mag %.1f", landmark.magnitude))
                    .font(NightTheme.mono(8))
                    .foregroundStyle(color.opacity(0.85))
                    .skyLegible()
            }
        }
    }

    private func radiantMarker(name: String) -> some View {
        VStack(spacing: 3) {
            // Radiating spokes: a visual reminder that meteors stream *outward* from here,
            // and that pointing straight at it is the beginner's mistake.
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    Rectangle()
                        .fill(NightTheme.secondary)
                        .frame(width: 1, height: 14)
                        .offset(y: -12)
                        .rotationEffect(.degrees(Double(index) * 45))
                }
                Circle()
                    .strokeBorder(NightTheme.primary, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
            }
            Text(String(format: String(localized: "RADIANT · %@"), name.uppercased()))
                .font(NightTheme.mono(9, weight: .semibold))
                .foregroundStyle(NightTheme.primary)
        }
    }

    private func targetMarker(_ target: HorizontalCoordinates, in size: CGSize) -> some View {
        Group {
            if let point = project(target, in: size) {
                ZStack {
                    Circle()
                        .strokeBorder(NightTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: 90, height: 90)
                    Text("AIM HERE")
                        .font(NightTheme.mono(10, weight: .bold))
                        .foregroundStyle(NightTheme.accent)
                        .offset(y: 58)
                }
                .position(point)
            }
        }
    }

    /// A horizon reference, so tilt is readable without looking away from the sky. Drawn
    /// through two points of the real horizon, so it tilts with the phone.
    @ViewBuilder
    private func horizonLine(in size: CGSize) -> some View {
        let geometry = geometry(in: size)
        if let left = geometry.project(HorizontalCoordinates(azimuth: aim.azimuth - 10, altitude: 0)),
           let right = geometry.project(HorizontalCoordinates(azimuth: aim.azimuth + 10, altitude: 0)),
           hypot(right.x - left.x, right.y - left.y) > 1 {
            // Extended well past both edges; the view clips what falls outside.
            let reach = 4 * max(size.width, size.height) / hypot(right.x - left.x, right.y - left.y)
            let from = CGPoint(x: left.x - (right.x - left.x) * reach, y: left.y - (right.y - left.y) * reach)
            let to = CGPoint(x: right.x + (right.x - left.x) * reach, y: right.y + (right.y - left.y) * reach)
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
            .stroke(NightTheme.dim.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
        }
    }

    /// Says the markers come from the stars themselves, so a person knows they can trust
    /// "that dot is Vega" to the pixel.
    private func lockBadge(in size: CGSize) -> some View {
        Text("LOCKED TO STARS")
            .font(NightTheme.mono(9, weight: .bold))
            .foregroundStyle(NightTheme.accent)
            .skyLegible()
            .position(x: size.width / 2, y: geometry(in: size).imageRect.minY + 14)
    }

    // MARK: - Guidance

    @ViewBuilder
    private var guidanceOverlay: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(compassPoint(forAzimuth: aim.azimuth))
                        .font(NightTheme.mono(22, weight: .bold))
                        .foregroundStyle(NightTheme.primary)
                    Text(String(format: String(localized: "%.0f° az · %.0f° up"), aim.azimuth, aim.altitude))
                        .font(NightTheme.mono(11))
                        .foregroundStyle(NightTheme.dim)
                }
                Spacer()
                if !hasFix {
                    Text("WAITING FOR\nLOCATION")
                        .font(NightTheme.mono(10))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(NightTheme.dim)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Spacer()
        }
    }
}

/// A landmark someone put a finger on.
struct StarTap: Equatable {
    let landmark: SkyDirector.Landmark
    let point: CGPoint
    var count: Int

    func distance(to other: CGPoint) -> CGFloat { hypot(point.x - other.x, point.y - other.y) }

    /// Five taps on one of two particular stars.
    var dedication: String? {
        guard count >= 5 else { return nil }
        switch landmark.name {
        case "Alzirr": return "My son is named after this star ♥"
        case "Almaaz": return "My other son shares its name ♥"
        default: return nil
        }
    }
}

/// Name, constellation, brightness. And, for two stars, a little more.
struct StarInfoBubble: View {
    let tap: StarTap

    var body: some View {
        VStack(spacing: 3) {
            Text(tap.landmark.name.uppercased())
                .font(NightTheme.mono(11, weight: .bold))
                .foregroundStyle(NightTheme.primary)
            Text(detail)
                .font(NightTheme.mono(9))
                .foregroundStyle(NightTheme.secondary)
            if let dedication = tap.dedication {
                Text(dedication)
                    .font(NightTheme.mono(10, weight: .semibold))
                    .foregroundStyle(NightTheme.accent)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NightTheme.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }

    private var detail: String {
        let place = tap.landmark.constellation ?? String(localized: "planet")
        return String(format: String(localized: "%@ · mag %.2f"), place, tap.landmark.magnitude)
    }
}
