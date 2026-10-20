import Foundation
import ImageIO
import SkyMeter
import UniformTypeIdentifiers

/// Shots contributed to the sky dataset: the reading, the camera, and the photo.
///
/// Opt-in, asked once after the first saved shot, switchable off in Settings › SKY DATASET.
/// What leaves the phone is listed in PRIVACY.md and nowhere else is anything added:
/// location rounded to 0.1° (~10 km), a random contributor id that is not the usage
/// counter's, and nothing that names the person. Uploads queue on disk, so a shot taken
/// in a field with no signal goes out once there is one.
enum SkyDataset {

    static let endpoint = URL(string: "https://api.starlapse.app")
    static let enabledKey = "skyDataset"
    static let contributorKey = "skyDatasetContributor"

    /// nil until asked.
    static var choice: Bool? {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var isEnabled: Bool { choice == true }

    static var contributor: String {
        if let id = UserDefaults.standard.string(forKey: contributorKey) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: contributorKey)
        return id
    }

    // MARK: - What is sent

    struct Camera: Encodable, Sendable {
        let lens: String
        let iso: Double
        let shutter: Double
        let frames: Int
        let fieldOfView: Double
        let device: String
    }

    struct Contribution: Encodable, Sendable {
        let id: String
        let contributor: String
        let takenAt: Date
        let kind: String
        let latitude: Double
        let longitude: Double
        let sky: SkyReading?
        let camera: Camera
        let meteors: [MeteorObservation]?
        let appVersion: String
    }

    /// ~10 km, done here so the precise fix never reaches the request.
    static func coarse(_ degrees: Double) -> Double { (degrees * 10).rounded() / 10 }

    static func contribution(
        kind: String, start: SkyMeasurement.Start, sky: SkyReading?, camera: Camera,
        meteors: [MeteorObservation]? = nil
    ) -> Contribution {
        Contribution(
            id: UUID().uuidString.lowercased(), contributor: contributor, takenAt: start.date, kind: kind,
            latitude: coarse(start.location.latitude), longitude: coarse(start.location.longitude),
            sky: sky, camera: camera,
            meteors: meteors,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        )
    }

    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }

    /// A 2048-pixel JPEG: enough to check a reading against the sky it came from.
    static func jpeg(from image: RenderedImage, longSide: Int = 2048) -> Data? {
        guard let source = image.makeCGImage() else { return nil }
        let scale = min(1, Double(longSide) / Double(max(source.width, source.height)))
        let width = Int(Double(source.width) * scale)
        let height = Int(Double(source.height) * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImage(destination, scaled, options)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    // MARK: - The queue

    static var queueDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SkyDataset", isDirectory: true)
    }

    /// Write to disk first, then try to send everything waiting.
    static func enqueue(_ contribution: Contribution, photo: Data?) async {
        let directory = queueDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let json = try? encoded(contribution) else { return }
        try? photo?.write(to: directory.appendingPathComponent(contribution.id + ".jpg"))
        try? json.write(to: directory.appendingPathComponent(contribution.id + ".json"))
        await flush()
    }

    static func encoded(_ contribution: Contribution) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(contribution)
    }

    /// Send what is queued. Called after each enqueue and when the app comes forward.
    static func flush() async {
        guard isEnabled, let endpoint else { return }
        let directory = queueDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for json in files where json.pathExtension == "json" {
            guard let body = try? Data(contentsOf: json) else { continue }
            let photoURL = json.deletingPathExtension().appendingPathExtension("jpg")
            let photo = try? Data(contentsOf: photoURL)
            guard await send(body, photo: photo, to: endpoint) else { return }
            try? FileManager.default.removeItem(at: json)
            try? FileManager.default.removeItem(at: photoURL)
        }
    }

    static func send(_ observation: Data, photo: Data?, to endpoint: URL) async -> Bool {
        let boundary = "starlapse-" + UUID().uuidString
        var body = Data()
        func part(_ name: String, filename: String? = nil, type: String, data: Data) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"".utf8))
            if let filename { body.append(Data("; filename=\"\(filename)\"".utf8)) }
            body.append(Data("\r\nContent-Type: \(type)\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        part("observation", type: "application/json", data: observation)
        if let photo { part("photo", filename: "sky.jpg", type: "image/jpeg", data: photo) }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpoint.appendingPathComponent("v1/observations"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        guard let (_, response) = try? await URLSession.shared.upload(for: request, from: body),
              let status = (response as? HTTPURLResponse)?.statusCode else { return false }
        // A 4xx will not get better by retrying; drop it rather than block the queue.
        return status < 500
    }

    /// Erase everything sent from this phone, and start over with a new id.
    static func deleteEverything() async -> Bool {
        try? FileManager.default.removeItem(at: queueDirectory)
        guard let endpoint else { return false }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/contributors/\(contributor)"))
        request.httpMethod = "DELETE"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        UserDefaults.standard.removeObject(forKey: contributorKey)
        return true
    }
}
