import Foundation
import ImageIO
import Security
import SkyMeter
import UniformTypeIdentifiers

/// Shots contributed to the sky dataset: the reading, the camera, and the photo.
///
/// Opt-in, asked once after the first saved shot, switchable off in Settings › SKY DATASET.
/// What leaves the phone is listed in PRIVACY.md and nowhere else is anything added:
/// location rounded to 0.1° (~10 km), a random contributor id that is not the usage
/// counter's, and nothing that names the person. Uploads queue on disk, so a shot taken
/// in a field with no signal goes out once there is one.
///
/// Main-actor isolated so the queue has one owner: a delete waits for the upload in flight
/// instead of racing it, and switching off stops the queue between two files.
@MainActor
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

    /// In the Keychain, not UserDefaults: it survives a reinstall, so "Delete everything I
    /// contributed" still reaches what an earlier install sent.
    /// UserDefaults is the fallback where the Keychain refuses (an unsigned test host).
    static var contributor: String {
        if let id = Keychain.read(contributorKey) { return id }
        let id = UserDefaults.standard.string(forKey: contributorKey) ?? UUID().uuidString.lowercased()
        if Keychain.write(id, for: contributorKey) {
            UserDefaults.standard.removeObject(forKey: contributorKey)
        } else {
            UserDefaults.standard.set(id, forKey: contributorKey)
        }
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
    nonisolated static func coarse(_ degrees: Double) -> Double { (degrees * 10).rounded() / 10 }

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

    nonisolated static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }

    /// A 2048-pixel JPEG: enough to check a reading against the sky it came from.
    nonisolated static func jpeg(from image: RenderedImage, longSide: Int = 2048) -> Data? {
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

    nonisolated static var queueDirectory: URL {
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
        flush()
    }

    static func encoded(_ contribution: Contribution) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(contribution)
    }

    private static var draining: Task<Void, Never>?
    private static var isDeleting = false

    /// Send what is queued, one file at a time. Called after each enqueue and when the app
    /// comes forward; a call while a drain is running joins it.
    static func flush() {
        guard draining == nil else { return }
        draining = Task {
            await drain()
            draining = nil
        }
    }

    private static func drain() async {
        guard let endpoint else { return }
        let directory = queueDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for json in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where json.pathExtension == "json" {
            // Checked before every file: switching off or deleting stops the queue here.
            guard isEnabled, !isDeleting, !Task.isCancelled else { return }
            guard let body = try? Data(contentsOf: json) else { continue }
            let photoURL = json.deletingPathExtension().appendingPathExtension("jpg")
            let photo = try? Data(contentsOf: photoURL)
            switch await send(body, photo: photo, to: endpoint) {
            case .stored, .refused:
                try? FileManager.default.removeItem(at: json)
                try? FileManager.default.removeItem(at: photoURL)
            case .later:
                return
            }
        }
    }

    enum Outcome { case stored, refused, later }

    /// `refused` is the server saying this file will never be accepted (400, 413, 415):
    /// keeping it would block the queue. Everything else, rate limits and timeouts
    /// included, is worth another try.
    nonisolated static func outcome(status: Int?) -> Outcome {
        guard let status else { return .later }
        if (200..<300).contains(status) { return .stored }
        return [400, 413, 415, 422].contains(status) ? .refused : .later
    }

    static func send(_ observation: Data, photo: Data?, to endpoint: URL) async -> Outcome {
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
        let response = try? await URLSession.shared.upload(for: request, from: body).1
        return outcome(status: (response as? HTTPURLResponse)?.statusCode)
    }

    /// Erase everything sent from this phone, and start over with a new id.
    ///
    /// The upload in flight is cancelled and waited for first, so nothing lands on the
    /// server after the delete that was meant to cover it.
    static func deleteEverything() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        draining?.cancel()
        await draining?.value
        try? FileManager.default.removeItem(at: queueDirectory)
        guard let endpoint else { return false }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/contributors/\(contributor)"))
        request.httpMethod = "DELETE"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        Keychain.delete(contributorKey)
        UserDefaults.standard.removeObject(forKey: contributorKey)
        return true
    }
}

/// One string per key, this app only, readable after the first unlock.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "co.superduperai.starlapse",
         kSecAttrAccount as String: key]
    }

    static func read(_ key: String) -> String? {
        var query = query(key)
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, for key: String) -> Bool {
        delete(key)
        var item = query(key)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
