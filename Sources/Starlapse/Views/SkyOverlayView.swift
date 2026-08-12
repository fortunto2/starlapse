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
    let guidance: AimGuidance?
    let hasFix: Bool

    /// Horizontal field of view of the current lens, for projecting sky onto screen.
    let fieldOfView: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let plan, hasFix {
                    landmarks(plan: plan, in: geometry.size)
                    targetMarker(plan: plan, in: geometry.size)
                }
                horizonLine(in: geometry.size)
                guidanceOverlay
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Projection

    /// Gnomonic-ish projection of a sky direction onto the screen.
    ///
    /// Accurate near the centre and increasingly wrong toward the edges, which is the right
    /// trade: a marker 60° off-axis only needs to say "that way", while one near the middle
    /// needs to sit on the star it names.
    private func project(_ target: HorizontalCoordinates, in size: CGSize) -> CGPoint? {
        let deltaAzimuth = (target.azimuth - aim.azimuth).signedDegrees
        let deltaAltitude = target.altitude - aim.altitude

        let halfField = fieldOfView / 2
        guard abs(deltaAzimuth) < halfField * 1.4, abs(deltaAltitude) < halfField * 1.4 else {
            return nil
        }

        // Azimuth compresses toward the zenith — a degree of azimuth covers less sky the
        // higher you look.
        let horizontalScale = cos(aim.altitude.radians)
        let pixelsPerDegree = size.width / fieldOfView

        return CGPoint(
            x: size.width / 2 + deltaAzimuth * horizontalScale * pixelsPerDegree,
            y: size.height / 2 - deltaAltitude * pixelsPerDegree
        )
    }

    // MARK: - Layers

    private func landmarks(plan: SkyDirector.Plan, in size: CGSize) -> some View {
        ZStack {
            ForEach(SkyCatalog.brightStars) { star in
                let position = star.position.horizontal(at: plan.location, date: plan.date)
                if position.isAboveHorizon, let point = project(position, in: size) {
                    starMarker(name: star.name, magnitude: star.magnitude)
                        .position(point)
                }
            }

            // Planets, which are the brightest things up there after the Moon and the best
            // manual-focus targets on a dark night.
            ForEach(plan.visiblePlanets()) { planet in
                let position = planet.position.horizontal(at: plan.location, date: plan.date)
                if let point = project(position, in: size) {
                    planetMarker(planet)
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
                    Text("MOON \(Int(plan.conditions.moon.illuminatedFraction * 100))%")
                        .font(NightTheme.mono(9))
                        .foregroundStyle(NightTheme.accent)
                }
                .position(point)
            }

            ForEach(Array(plan.showers.prefix(1).enumerated()), id: \.offset) { _, activity in
                if activity.radiant.isAboveHorizon,
                   let point = project(activity.radiant, in: size) {
                    radiantMarker(name: activity.shower.name)
                        .position(point)
                }
            }
        }
    }

    private func starMarker(name: String, magnitude: Double) -> some View {
        // Brighter stars get bigger marks, the way a real chart plots them.
        let diameter = max(4.0, 9.0 - magnitude * 2.0)
        return VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(NightTheme.primary.opacity(0.25))
                    .frame(width: diameter * 2.4, height: diameter * 2.4)
                Circle()
                    .fill(NightTheme.primary)
                    .frame(width: diameter, height: diameter)
            }
            Text(name.uppercased())
                .font(NightTheme.mono(9, weight: .medium))
                .foregroundStyle(NightTheme.primary.opacity(0.9))
                .skyLegible()
        }
    }

    private func planetMarker(_ planet: PlanetPosition) -> some View {
        let diameter = max(7.0, 13.0 - planet.magnitude * 1.5)
        return VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(NightTheme.accent.opacity(0.22))
                    .frame(width: diameter * 2.2, height: diameter * 2.2)
                Circle()
                    .fill(NightTheme.accent)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .stroke(NightTheme.accent.opacity(0.7), lineWidth: 1)
                    .frame(width: diameter * 1.7, height: diameter * 1.7)
            }
            Text(planet.name.uppercased())
                .font(NightTheme.mono(10, weight: .bold))
                .foregroundStyle(NightTheme.accent)
                .skyLegible()
            Text(String(format: "mag %.1f", planet.magnitude))
                .font(NightTheme.mono(8))
                .foregroundStyle(NightTheme.accent.opacity(0.85))
                .skyLegible()
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
            Text("RADIANT · \(name.uppercased())")
                .font(NightTheme.mono(9, weight: .semibold))
                .foregroundStyle(NightTheme.primary)
        }
    }

    private func targetMarker(plan: SkyDirector.Plan, in size: CGSize) -> some View {
        Group {
            if let point = project(plan.aim.direction, in: size) {
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

    /// A horizon reference, so tilt is readable without looking away from the sky.
    private func horizonLine(in size: CGSize) -> some View {
        let pixelsPerDegree = size.width / fieldOfView
        let offset = aim.altitude * pixelsPerDegree

        return Path { path in
            path.move(to: CGPoint(x: 0, y: size.height / 2 + offset))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2 + offset))
        }
        .stroke(NightTheme.dim.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
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
                    Text(String(format: "%.0f° az · %.0f° up", aim.azimuth, aim.altitude))
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

            if let guidance, !guidance.isOnTarget {
                turnInstruction(guidance)
                    .padding(.bottom, 8)
            }
        }
    }

    private func turnInstruction(_ guidance: AimGuidance) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up")
                .font(.system(size: 20, weight: .bold))
                .rotationEffect(guidance.arrowAngle)
                .foregroundStyle(NightTheme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.0f° to target", guidance.separation))
                    .font(NightTheme.mono(13, weight: .semibold))
                    .foregroundStyle(NightTheme.accent)
                Text(guidance.instruction)
                    .font(NightTheme.mono(10))
                    .foregroundStyle(NightTheme.dim)
            }
        }
        .nightPanel()
    }
}
