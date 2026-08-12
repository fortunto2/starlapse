import Foundation

/// Time scales used by the sky math.
///
/// Everything here follows Meeus, *Astronomical Algorithms* (2nd ed.). We deliberately stay
/// in the "low precision" branch of every formula: the app points a hand-held phone at the
/// sky, so sub-arcminute accuracy would be spent on nothing. Errors stay well under 0.1°,
/// a fifth of the Moon's apparent diameter.
public enum AstroTime {

    /// Julian Date for an instant. The Unix epoch is JD 2440587.5.
    public static func julianDate(from date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
    }

    /// Julian centuries elapsed since the J2000.0 epoch.
    public static func julianCenturies(since jd: Double) -> Double {
        (jd - 2_451_545.0) / 36_525.0
    }

    /// Greenwich Mean Sidereal Time, degrees in `[0, 360)`. Meeus eq. 12.4.
    public static func greenwichMeanSiderealTime(jd: Double) -> Double {
        let t = julianCenturies(since: jd)
        let gmst = 280.460_618_37
            + 360.985_647_366_29 * (jd - 2_451_545.0)
            + 0.000_387_933 * t * t
            - (t * t * t) / 38_710_000.0
        return gmst.normalizedDegrees
    }

    /// Local Mean Sidereal Time, degrees in `[0, 360)`. East longitude is positive.
    ///
    /// LST is the right ascension currently crossing the observer's meridian — the single
    /// number that turns a star chart into "look over there".
    public static func localSiderealTime(jd: Double, longitude: Double) -> Double {
        (greenwichMeanSiderealTime(jd: jd) + longitude).normalizedDegrees
    }

    /// Obliquity of the ecliptic in degrees — the tilt separating the ecliptic (where the
    /// Sun and Moon travel) from the equator (where RA/Dec are measured). Meeus eq. 22.2.
    public static func obliquityOfEcliptic(jd: Double) -> Double {
        let t = julianCenturies(since: jd)
        return 23.439_291 - 0.013_004_2 * t - 1.64e-7 * t * t + 5.04e-7 * t * t * t
    }
}
