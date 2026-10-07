import SuperDuperAnalytics
import SwiftUI

@main
struct StarlapseApp: App {

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Clips and time-lapses are written before anyone decides whether to keep them, and
        // a session that ends by force-quit — or by the battery dying on a tripod at 4am,
        // which is the realistic case — never gets to clean up after itself.
        ScratchStore.purgeLeftovers()
        // Before any camera work: if the last run died holding a sensor format, that format
        // is not offered again on this phone. See FormatQuarantine.
        FormatQuarantine().recoverFromCrash()
        CrashDiagnostics.shared.start()
        // App Store Connect counts downloads; nobody counts the second launch. Five events,
        // an id made on this phone, switchable off in the controls panel. A debug build is
        // marked as a machine so simulator runs do not count as people.
        #if DEBUG
        Analytics.configure(source: "starlapse", automated: true)
        #else
        Analytics.configure(source: "starlapse")
        #endif
        Analytics.track("app_launched")
    }

    var body: some Scene {
        WindowGroup {
            CaptureView()
        }
        .onChange(of: scenePhase) { _, phase in
            // The buffer dies with the process, and a night session ends by force-quit as
            // often as by any button.
            if phase == .background { Analytics.flush() }
        }
    }
}
