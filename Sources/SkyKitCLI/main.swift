import Foundation
import SkyKit

// CLI-First: the same domain code the app runs, driven deterministically from a terminal.
// No camera, no simulator, no UI — if the aiming advice is wrong, it is wrong here first,
// and here it takes 200ms to find out.
//
//   swift run starlapse-sky tonight --lat 28.754 --lon -17.885
//   swift run starlapse-sky tonight --lat 55.75 --lon 37.62 --at 2026-08-13T22:00:00Z

let arguments = CommandLine.arguments

func value(for flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func printUsage() {
    print("""
    starlapse-sky — what to shoot tonight, and where to point

    USAGE
      starlapse-sky tonight  --lat <deg> --lon <deg> [--at <ISO8601>]
      starlapse-sky showers  [--at <ISO8601>]
      starlapse-sky moon     --lat <deg> --lon <deg> [--at <ISO8601>]

    Longitude is east-positive. Times are UTC; omit --at for now.
    """)
}

let isoFormatter = ISO8601DateFormatter()

let date: Date = {
    guard let raw = value(for: "--at") else { return Date() }
    guard let parsed = isoFormatter.date(from: raw) else {
        FileHandle.standardError.write(Data("Bad --at, expected ISO8601 like 2026-08-13T22:00:00Z\n".utf8))
        exit(2)
    }
    return parsed
}()

func requireLocation() -> GeographicCoordinates {
    guard let lat = value(for: "--lat").flatMap(Double.init),
          let lon = value(for: "--lon").flatMap(Double.init) else {
        FileHandle.standardError.write(Data("Missing --lat / --lon\n".utf8))
        exit(2)
    }
    return GeographicCoordinates(latitude: lat, longitude: lon)
}

func bar(_ fraction: Double, width: Int = 20) -> String {
    let filled = Int((fraction.clamped(to: 0 ... 1) * Double(width)).rounded())
    return String(repeating: "█", count: filled) + String(repeating: "·", count: width - filled)
}

func formatDirection(_ direction: HorizontalCoordinates) -> String {
    let compass = compassPoint(forAzimuth: direction.azimuth)
    return String(format: "%@ %.0f° az, %.0f° up", compass, direction.azimuth, direction.altitude)
}

/// `String(format:)` ignores field widths on `%@`, so columns get padded by hand.
func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

switch arguments.dropFirst().first {

case "tonight":
    let location = requireLocation()
    let plan = SkyDirector.plan(at: location, date: date)

    print("")
    print("  \(isoFormatter.string(from: plan.date))")
    print("  \(String(format: "%.3f", location.latitude)), \(String(format: "%.3f", location.longitude))")
    print("")
    print("  CONDITIONS  \(bar(plan.conditions.darkness))  \(Int(plan.conditions.darkness * 100))%")
    print("  \(plan.conditions.summary)")
    print("")

    if plan.showers.isEmpty {
        print("  No active meteor showers.")
    } else {
        print("  ACTIVE SHOWERS")
        for activity in plan.showers {
            let position = activity.radiant.isAboveHorizon
                ? formatDirection(activity.radiant)
                : String(format: "below horizon (%.0f°)", activity.radiant.altitude)
            let rate = String(format: "%5.1f/h", activity.expectedHourlyRate)
            print("    \(pad(activity.shower.name, 26)) \(rate)   radiant: \(position)")
        }
    }

    print("")
    print("  POINT THE CAMERA")
    print("    \(formatDirection(plan.aim.direction))")
    print("    \(plan.aim.subject) — \(plan.aim.reason)")
    print("")
    print("  Milky Way core   \(formatDirection(plan.milkyWayCore))")
    print("  Celestial pole   \(formatDirection(plan.celestialPole))")

    if let headline = plan.headlineShower,
       let best = SkyDirector.bestTimeTonight(
           for: headline.shower, at: location, from: date
       ), best.rate > headline.expectedHourlyRate * 1.1 {
        print("")
        print("  Better later: \(isoFormatter.string(from: best.date)) → \(String(format: "%.1f", best.rate))/h")
    }
    print("")

case "showers":
    let active = MeteorShower.active(on: date)
    print("")
    if active.isEmpty {
        print("  No active showers on \(isoFormatter.string(from: date)).")
    } else {
        for shower in active {
            let stats = String(
                format: "ZHR %3d  %2d km/s  peak %02d-%02d  ×%.2f",
                shower.zenithalHourlyRate, shower.velocityKmPerSecond,
                shower.peak.month, shower.peak.day, shower.peakProximity(on: date)
            )
            print("  \(pad(shower.code, 5))\(pad(shower.name, 26)) \(stats)")
        }
    }
    print("")

case "moon":
    let location = requireLocation()
    let jd = AstroTime.julianDate(from: date)
    let moon = SolarSystem.moonState(jd: jd)
    let position = moon.position.horizontal(at: location, date: date)

    print("")
    print("  \(moon.phaseName)  \(bar(moon.illuminatedFraction))  \(Int(moon.illuminatedFraction * 100))% lit")
    print("  \(formatDirection(position))")
    print(String(format: "  %.0f km away", moon.distanceKm))
    print("  \(SolarSystem.twilightPhase(at: location, date: date).rawValue)")
    print("")

default:
    printUsage()
    exit(arguments.count > 1 ? 2 : 0)
}
