import Foundation

/// A star with a catalogue magnitude: the reference every sky measurement is made against.
public struct CatalogStar: Sendable, Hashable {
    /// J2000. Precession since then is a third of a degree, well inside what matching
    /// a phone frame against the catalogue tolerates.
    public let position: EquatorialCoordinates
    /// Johnson V.
    public let magnitude: Double
    /// B−V, when the catalogue has one. A phone's luminance sits between B and V, so the
    /// colour term is what a calibration would add next.
    public let colorIndex: Double?
}

/// Every star to V 6.5: the Yale Bright Star Catalogue, 9096 entries.
///
/// `SkyCatalog.brightStars` is twenty names for orientation; this is the photometric
/// reference. A frame from a phone shows a few dozen to a few hundred of these, and their
/// known magnitudes turn pixel values into magnitudes per square arcsecond.
public enum StarCatalog {

    public static let stars: [CatalogStar] = {
        guard let data = Data(base64Encoded: packed, options: .ignoreUnknownCharacters) else { return [] }
        let bytes = [UInt8](data)
        let size = 7
        return stride(from: 0, to: bytes.count - size + 1, by: size).map { offset in
            func word(_ index: Int) -> UInt16 {
                UInt16(bytes[offset + index]) | UInt16(bytes[offset + index + 1]) << 8
            }
            let rightAscension = Double(word(0)) / 65_536 * 360
            let declination = Double(Int16(bitPattern: word(2))) / 32_767 * 90
            let magnitude = Double(Int16(bitPattern: word(4))) / 100
            let color = Int8(bitPattern: bytes[offset + 6])
            return CatalogStar(
                position: EquatorialCoordinates(rightAscension: rightAscension, declination: declination),
                magnitude: magnitude,
                colorIndex: color == 127 ? nil : Double(color) / 50
            )
        }
    }()
}
