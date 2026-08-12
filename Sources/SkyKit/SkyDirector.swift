import Foundation

/// What kind of thing a sky landmark is. Drives how it is drawn and how it ranks as a
/// focus target — a planet is a disc, so it snaps into focus more decisively than a star.
public enum LandmarkKind: Sendable, Hashable {
    case star
    case planet
}

/// Turns "it's a clear night in August" into "point the phone there, for this long".
///
/// This is the part that earns the app. Pointing at the radiant is the mistake every
/// beginner makes: meteors radiate *away* from it, so at the radiant they are foreshortened
/// into dots, while 30–50° off they draw their full length across the frame. Add the Moon
/// as a moving light source you want at your back, and a horizon you want to stay above,
/// and the answer stops being obvious enough to eyeball.
public enum SkyDirector {

    // MARK: - Conditions

    public struct Conditions: Sendable {
        public let twilight: SolarSystem.TwilightPhase
        public let moon: SolarSystem.MoonState
        public let moonPosition: HorizontalCoordinates

        /// How dark it actually is, 0…1. Combines twilight with moonlight, because a full
        /// Moon at 40° ruins a sky that the Sun has long since left.
        public let darkness: Double

        public var isMoonUp: Bool { moonPosition.isAboveHorizon }

        /// One line a human can act on.
        public var summary: String {
            if !twilight.isDarkEnoughForAstrophotography {
                return "\(twilight.rawValue) — wait for full darkness"
            }
            if isMoonUp && moon.illuminatedFraction > 0.35 {
                let percent = Int(moon.illuminatedFraction * 100)
                return "\(moon.phaseName) (\(percent)%) up at \(Int(moonPosition.altitude))° — shoot away from it"
            }
            if isMoonUp {
                return "Dark, thin \(moon.phaseName.lowercased()) — good"
            }
            return "Astronomical night, no Moon — best conditions"
        }
    }

    // MARK: - Shower activity

    public struct ShowerActivity: Sendable, Identifiable {
        public var id: String { shower.code }
        public let shower: MeteorShower
        public let radiant: HorizontalCoordinates
        /// Meteors per hour a real observer should expect right now — ZHR knocked down for
        /// radiant altitude, distance from peak night, and moonlight.
        public let expectedHourlyRate: Double

        public var isWorthShooting: Bool { expectedHourlyRate >= 3 }
    }

    // MARK: - Aim

    public struct AimPoint: Sendable {
        public let direction: HorizontalCoordinates
        public let subject: String
        public let reason: String

        public var compass: String { compassPoint(forAzimuth: direction.azimuth) }
    }

    /// Something in the sky worth drawing, already converted to a direction.
    ///
    /// The conversion happens once, when the plan is built. Overlay views run at display
    /// rate and must not be re-deriving sidereal time for the same instant thirty times a
    /// second — the only thing that changes between redraws is where the phone is pointed.
    public struct Landmark: Sendable, Hashable, Identifiable {
        public var id: String { name }
        public let name: String
        public let kind: LandmarkKind
        /// Apparent visual magnitude — lower is brighter.
        public let magnitude: Double
        public let direction: HorizontalCoordinates

        public var isPlanet: Bool { kind == .planet }
    }

    public struct Plan: Sendable {
        public let date: Date
        public let location: GeographicCoordinates
        public let conditions: Conditions
        public let showers: [ShowerActivity]
        /// Bright stars and visible planets, positions already resolved.
        public let landmarks: [Landmark]
        public let milkyWayCore: HorizontalCoordinates
        public let celestialPole: HorizontalCoordinates
        public let aim: AimPoint
        /// The best thing to focus on. Autofocus is useless against a dark sky, so manual
        /// focus needs a bright point source — a planet is the brightest one available
        /// short of the Moon, and unlike the Moon it never blows out the frame.
        public let focusTarget: Landmark?

        public var headlineShower: ShowerActivity? { showers.first }

        /// Planets currently up and bright enough to see, brightest first.
        public var visiblePlanets: [Landmark] {
            landmarks.filter(\.isPlanet)
        }
    }

    // MARK: - Entry point

    /// Everything the capture screen needs for one moment in time.
    public static func plan(at location: GeographicCoordinates, date: Date) -> Plan {
        let jd = AstroTime.julianDate(from: date)
        let moon = SolarSystem.moonState(jd: jd)
        let moonPosition = moon.position.horizontal(at: location, date: date)
        let twilight = SolarSystem.twilightPhase(at: location, date: date)

        let conditions = Conditions(
            twilight: twilight,
            moon: moon,
            moonPosition: moonPosition,
            darkness: darknessScore(twilight: twilight, moon: moon, moonPosition: moonPosition)
        )

        let showers = MeteorShower.active(on: date)
            .map { shower in
                let radiant = shower.radiant.horizontal(at: location, date: date)
                return ShowerActivity(
                    shower: shower,
                    radiant: radiant,
                    expectedHourlyRate: expectedRate(
                        shower: shower,
                        radiant: radiant,
                        date: date,
                        conditions: conditions
                    )
                )
            }
            .sorted { $0.expectedHourlyRate > $1.expectedHourlyRate }

        let milkyWay = SkyCatalog.galacticCenter.horizontal(at: location, date: date)
        let pole = SkyCatalog.polaris.position.horizontal(at: location, date: date)
        let landmarks = resolveLandmarks(at: location, date: date, jd: jd)

        return Plan(
            date: date,
            location: location,
            conditions: conditions,
            showers: showers,
            landmarks: landmarks,
            milkyWayCore: milkyWay,
            celestialPole: pole,
            aim: aimPoint(
                showers: showers,
                milkyWay: milkyWay,
                pole: pole,
                conditions: conditions
            ),
            // Brightest thing high enough to be clear of horizon haze. Planets win over
            // stars at equal magnitude — they are disc sources, so they cut through
            // seeing better and snap into focus more decisively.
            focusTarget: landmarks
                .filter { $0.direction.altitude > 15 }
                .min { left, right in
                    let leftScore = left.magnitude - (left.isPlanet ? 0.5 : 0)
                    let rightScore = right.magnitude - (right.isPlanet ? 0.5 : 0)
                    return leftScore < rightScore
                }
        )
    }

    /// Resolve every drawable object to a direction, once per plan.
    static func resolveLandmarks(
        at location: GeographicCoordinates,
        date: Date,
        jd: Double
    ) -> [Landmark] {
        let planets = PlanetEphemeris.positions(jd: jd)
            .filter(\.isNakedEyeBright)
            .map { planet in
                Landmark(
                    name: planet.name,
                    kind: .planet,
                    magnitude: planet.magnitude,
                    direction: planet.position.horizontal(at: location, date: date)
                )
            }

        let stars = SkyCatalog.brightStars.map { star in
            Landmark(
                name: star.name,
                kind: .star,
                magnitude: star.magnitude,
                direction: star.position.horizontal(at: location, date: date)
            )
        }

        return (planets + stars)
            .filter(\.direction.isAboveHorizon)
            .sorted { $0.magnitude < $1.magnitude }
    }

    // MARK: - Scoring

    /// Rates fall off with the sine of the radiant altitude — a radiant on the horizon
    /// hides half its meteors below it. Moonlight is charged as a flat multiplier: it does
    /// not remove meteors, it removes the faint ones, which is most of them.
    static func expectedRate(
        shower: MeteorShower,
        radiant: HorizontalCoordinates,
        date: Date,
        conditions: Conditions
    ) -> Double {
        guard radiant.isAboveHorizon else { return 0 }

        let altitudeFactor = sin(radiant.altitude.radians)
        let peakFactor = shower.peakProximity(on: date)
        let moonFactor = moonPenalty(conditions: conditions)
        let twilightFactor = conditions.twilight.isDarkEnoughForAstrophotography ? 1.0 : 0.3

        return Double(shower.zenithalHourlyRate) * altitudeFactor * peakFactor * moonFactor * twilightFactor
    }

    static func moonPenalty(conditions: Conditions) -> Double {
        guard conditions.isMoonUp else { return 1.0 }
        // A full Moon costs roughly two thirds of the visible meteors; a thin crescent
        // barely registers. Altitude matters too — a Moon just above the horizon is dimmed
        // by the atmosphere and blocked by terrain.
        let brightness = conditions.moon.illuminatedFraction
        let altitudeWeight = sin(max(0, conditions.moonPosition.altitude).radians)
        return (1.0 - 0.65 * brightness * altitudeWeight).clamped(to: 0.2 ... 1.0)
    }

    static func darknessScore(
        twilight: SolarSystem.TwilightPhase,
        moon: SolarSystem.MoonState,
        moonPosition: HorizontalCoordinates
    ) -> Double {
        let twilightScore: Double = switch twilight {
        case .day: 0.0
        case .civil: 0.15
        case .nautical: 0.45
        case .astronomical: 0.75
        case .night: 1.0
        }

        guard moonPosition.isAboveHorizon else { return twilightScore }
        let moonlight = moon.illuminatedFraction * sin(max(0, moonPosition.altitude).radians)
        return (twilightScore * (1.0 - 0.7 * moonlight)).clamped(to: 0 ... 1)
    }

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

    /// Search a ring of candidate directions around the radiant.
    private static func bestOffset(
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

    /// When tonight this shower is at its best, scanning forward in ten-minute steps.
    ///
    /// Meteor showers almost always improve after midnight: the observer rotates onto the
    /// leading edge of the Earth and sweeps into the debris stream head-on.
    public static func bestTimeTonight(
        for shower: MeteorShower,
        at location: GeographicCoordinates,
        from date: Date,
        hoursAhead: Double = 12
    ) -> (date: Date, rate: Double)? {
        var best: (date: Date, rate: Double)?
        let steps = Int(hoursAhead * 6)

        for step in 0...steps {
            let moment = date.addingTimeInterval(Double(step) * 600)
            let jd = AstroTime.julianDate(from: moment)
            let moon = SolarSystem.moonState(jd: jd)
            let conditions = Conditions(
                twilight: SolarSystem.twilightPhase(at: location, date: moment),
                moon: moon,
                moonPosition: moon.position.horizontal(at: location, date: moment),
                darkness: 1
            )
            let radiant = shower.radiant.horizontal(at: location, date: moment)
            let rate = expectedRate(
                shower: shower,
                radiant: radiant,
                date: moment,
                conditions: conditions
            )

            if rate > (best?.rate ?? 0) {
                best = (moment, rate)
            }
        }

        return best
    }
}
