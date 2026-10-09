import Foundation

/// One thing the camera could be pointed at tonight, with the aim worked out for it.
///
/// `Plan.aim` is the app's pick; these are everything it chose between, so the person
/// can overrule it. A shower candidate is an event and gated like one; the rest is the
/// constant sky and free.
public struct AimCandidate: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case shower(code: String)
        case milkyWay
        case pole
        case planet(name: String)
    }

    public let kind: Kind
    public let aim: SkyDirector.AimPoint

    public var id: Kind { kind }
    public var isEvent: Bool {
        if case .shower = kind { return true }
        return false
    }
}

/// Where to point, and what else could be pointed at.
extension SkyDirector {

    // MARK: - Where to point

    /// Pick a direction to actually aim the camera.
    ///
    /// With an active shower we orbit the radiant at 40° and choose the offset that sits
    /// highest and furthest from the Moon. With no shower worth chasing we fall back to the
    /// Milky Way core, and failing that to the celestial pole, where a long stack turns
    /// into concentric star trails instead of a smear.
    static func aimPoint(
        showers: [ShowerActivity],
        milkyWay: HorizontalCoordinates,
        pole: HorizontalCoordinates,
        conditions: Conditions
    ) -> AimPoint {
        if let shower = showers.first, shower.isWorthShooting, shower.radiant.isAboveHorizon {
            let direction = bestOffset(from: shower.radiant, conditions: conditions)
            return AimPoint(
                direction: direction,
                subject: shower.shower.name,
                reason: "40° off the radiant — that is where the trails are longest"
            )
        }

        if milkyWay.altitude > 15 {
            return AimPoint(
                direction: milkyWay,
                subject: "Milky Way core",
                reason: "Galactic centre is \(Int(milkyWay.altitude))° up — the richest wide-field target"
            )
        }

        return AimPoint(
            direction: pole,
            subject: "Star trails around Polaris",
            reason: "Nothing bright is up — stack on the pole and let the sky draw circles"
        )
    }

    /// The menu behind the aim: what the plan weighed, and what it passed over.
    static func aimCandidates(
        showers: [ShowerActivity],
        milkyWay: HorizontalCoordinates,
        pole: HorizontalCoordinates,
        landmarks: [Landmark],
        conditions: Conditions
    ) -> [AimCandidate] {
        var candidates: [AimCandidate] = showers
            .filter { $0.isWorthShooting && $0.radiant.isAboveHorizon }
            .map { shower in
                AimCandidate(
                    kind: .shower(code: shower.shower.code),
                    aim: AimPoint(
                        direction: bestOffset(from: shower.radiant, conditions: conditions),
                        subject: shower.shower.name,
                        reason: "40° off the radiant — that is where the trails are longest"
                    )
                )
            }
        if milkyWay.isAboveHorizon {
            candidates.append(AimCandidate(
                kind: .milkyWay,
                aim: AimPoint(
                    direction: milkyWay,
                    subject: "Milky Way core",
                    reason: "Galactic centre is \(Int(milkyWay.altitude))° up — the richest wide-field target"
                )
            ))
        }
        if pole.isAboveHorizon {
            candidates.append(AimCandidate(
                kind: .pole,
                aim: AimPoint(
                    direction: pole,
                    subject: "Star trails around Polaris",
                    reason: "Stack on the pole and let the sky draw circles"
                )
            ))
        }
        for planet in landmarks where planet.isPlanet {
            candidates.append(AimCandidate(
                kind: .planet(name: planet.name),
                aim: AimPoint(
                    direction: planet.direction,
                    subject: planet.name,
                    reason: String(
                        format: "mag %.1f, %.0f° up — a disc, not a point: focus on it first",
                        planet.magnitude, planet.direction.altitude
                    )
                )
            ))
        }
        return candidates
    }

    /// Search a ring of candidate directions around the radiant.
    static func bestOffset(
        from radiant: HorizontalCoordinates,
        conditions: Conditions
    ) -> HorizontalCoordinates {
        let offsetDegrees = 40.0
        var best = radiant
        var bestScore = -Double.infinity

        // Aim for a comfortable working height rather than "as high as possible". Below 25°
        // you shoot through several airmasses of haze and whatever town sits on that
        // horizon; past 65° the tripod head runs out of tilt and you are lying on your back
        // under it. Around 50° is where framing a foreground is still possible.
        let idealAltitude = 50.0

        for bearing in stride(from: 0.0, to: 360.0, by: 15.0) {
            let candidate = offset(from: radiant, by: offsetDegrees, towards: bearing)
            guard candidate.altitude > 25, candidate.altitude < 65 else { continue }

            var score = 1.0 - abs(candidate.altitude - idealAltitude) / 40.0
            if conditions.isMoonUp {
                // Every degree away from the Moon is worth having, up to a point.
                score += min(candidate.separation(from: conditions.moonPosition), 120.0) / 120.0 * 1.5
            }

            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }

        return best
    }

    /// Walk `distance` degrees away from a point along a given bearing, on the sphere.
    /// Same great-circle step as navigation, with altitude standing in for latitude.
    static func offset(
        from origin: HorizontalCoordinates,
        by distance: Double,
        towards bearing: Double
    ) -> HorizontalCoordinates {
        let lat = origin.altitude.radians
        let angular = distance.radians
        let course = bearing.radians

        let sinLat = sin(lat) * cos(angular) + cos(lat) * sin(angular) * cos(course)
        let newLat = asin(sinLat.clamped(to: -1 ... 1))

        let deltaLon = atan2(
            sin(course) * sin(angular) * cos(lat),
            cos(angular) - sin(lat) * sinLat
        )

        return HorizontalCoordinates(
            azimuth: origin.azimuth + deltaLon.degrees,
            altitude: newLat.degrees
        )
    }

    // MARK: - Timing
}
