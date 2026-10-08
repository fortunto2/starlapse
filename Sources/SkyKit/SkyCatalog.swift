import Foundation

/// A landmark bright enough to find with the naked eye, used to orient the overlay and
/// to give the user something to confirm against ("that bright one is Vega").
public struct NamedStar: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let constellation: String
    public let position: EquatorialCoordinates
    /// Apparent visual magnitude — lower is brighter. Sirius is −1.46; the naked-eye
    /// limit under a dark sky is about 6.
    public let magnitude: Double
}

public enum SkyCatalog {

    /// The brightest stars plus the handful of pointers people actually navigate by.
    /// Deliberately short: a phone overlay with 9000 catalogue stars is unreadable, and
    /// the point here is orientation, not a planetarium.
    public static let brightStars: [NamedStar] = [
        NamedStar(name: "Sirius", constellation: "Canis Major",
                  position: EquatorialCoordinates(raHours: 6, raMinutes: 45, dec: -16.7),
                  magnitude: -1.46),
        NamedStar(name: "Arcturus", constellation: "Boötes",
                  position: EquatorialCoordinates(raHours: 14, raMinutes: 16, dec: 19.2),
                  magnitude: -0.05),
        NamedStar(name: "Vega", constellation: "Lyra",
                  position: EquatorialCoordinates(raHours: 18, raMinutes: 37, dec: 38.8),
                  magnitude: 0.03),
        NamedStar(name: "Capella", constellation: "Auriga",
                  position: EquatorialCoordinates(raHours: 5, raMinutes: 17, dec: 46.0),
                  magnitude: 0.08),
        NamedStar(name: "Rigel", constellation: "Orion",
                  position: EquatorialCoordinates(raHours: 5, raMinutes: 15, dec: -8.2),
                  magnitude: 0.13),
        NamedStar(name: "Procyon", constellation: "Canis Minor",
                  position: EquatorialCoordinates(raHours: 7, raMinutes: 39, dec: 5.2),
                  magnitude: 0.34),
        NamedStar(name: "Betelgeuse", constellation: "Orion",
                  position: EquatorialCoordinates(raHours: 5, raMinutes: 55, dec: 7.4),
                  magnitude: 0.50),
        NamedStar(name: "Altair", constellation: "Aquila",
                  position: EquatorialCoordinates(raHours: 19, raMinutes: 51, dec: 8.9),
                  magnitude: 0.76),
        NamedStar(name: "Aldebaran", constellation: "Taurus",
                  position: EquatorialCoordinates(raHours: 4, raMinutes: 36, dec: 16.5),
                  magnitude: 0.85),
        NamedStar(name: "Antares", constellation: "Scorpius",
                  position: EquatorialCoordinates(raHours: 16, raMinutes: 29, dec: -26.4),
                  magnitude: 1.09),
        NamedStar(name: "Spica", constellation: "Virgo",
                  position: EquatorialCoordinates(raHours: 13, raMinutes: 25, dec: -11.2),
                  magnitude: 1.04),
        NamedStar(name: "Pollux", constellation: "Gemini",
                  position: EquatorialCoordinates(raHours: 7, raMinutes: 45, dec: 28.0),
                  magnitude: 1.14),
        NamedStar(name: "Deneb", constellation: "Cygnus",
                  position: EquatorialCoordinates(raHours: 20, raMinutes: 41, dec: 45.3),
                  magnitude: 1.25),
        NamedStar(name: "Regulus", constellation: "Leo",
                  position: EquatorialCoordinates(raHours: 10, raMinutes: 8, dec: 12.0),
                  magnitude: 1.35),
        NamedStar(name: "Polaris", constellation: "Ursa Minor",
                  position: EquatorialCoordinates(raHours: 2, raMinutes: 32, dec: 89.3),
                  magnitude: 1.98),
        NamedStar(name: "Mirfak", constellation: "Perseus",
                  position: EquatorialCoordinates(raHours: 3, raMinutes: 24, dec: 49.9),
                  magnitude: 1.79),
        NamedStar(name: "Schedar", constellation: "Cassiopeia",
                  position: EquatorialCoordinates(raHours: 0, raMinutes: 40, dec: 56.5),
                  magnitude: 2.24),
        NamedStar(name: "Dubhe", constellation: "Ursa Major",
                  position: EquatorialCoordinates(raHours: 11, raMinutes: 4, dec: 61.8),
                  magnitude: 1.79),
        // The one entry that is not here for brightness. ξ Geminorum, 3.35: the Twins' foot,
        // an hour of right ascension east of Sirius and a fine star to say hello to.
        NamedStar(name: "Alzirr", constellation: "Gemini",
                  position: EquatorialCoordinates(raHours: 6, raMinutes: 45, dec: 12.9),
                  magnitude: 3.35),
        // ε Aurigae, 3.0: every 27 years a dark disc the size of Saturn's orbit eclipses
        // it for two years. Kept for the same reason as its neighbour above.
        NamedStar(name: "Almaaz", constellation: "Auriga",
                  position: EquatorialCoordinates(raHours: 5, raMinutes: 2, dec: 43.8),
                  magnitude: 2.98),
    ]

    /// Polaris — the pivot the whole sky turns around. Point the camera at it and stars
    /// trail in concentric circles; point away and they streak in arcs.
    public static var polaris: NamedStar {
        brightStars.first { $0.name == "Polaris" } ?? brightStars[0]
    }

    /// The galactic centre in Sagittarius — the brightest, most structured part of the
    /// Milky Way and the single best wide-field target of the northern summer.
    public static let galacticCenter = EquatorialCoordinates(raHours: 17, raMinutes: 46, dec: -28.9)

    /// Points along the galactic plane every 30°, so the overlay can draw the Milky Way as
    /// an arc rather than a dot. Computed from the galactic frame; see `Galactic.swift`.
    public static var milkyWayPlane: [EquatorialCoordinates] {
        galacticEquator(step: 30).map(\.position)
    }
}
