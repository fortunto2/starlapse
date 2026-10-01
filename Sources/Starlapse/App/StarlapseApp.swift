import SwiftUI

@main
struct StarlapseApp: App {

    init() {
        // Clips and time-lapses are written before anyone decides whether to keep them, and
        // a session that ends by force-quit — or by the battery dying on a tripod at 4am,
        // which is the realistic case — never gets to clean up after itself.
        ScratchStore.purgeLeftovers()
        // Before any camera work: if the last run died holding a sensor format, that format
        // is not offered again on this phone. See FormatQuarantine.
        FormatQuarantine().recoverFromCrash()
        CrashDiagnostics.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            CaptureView()
        }
    }
}
