import SwiftUI

@main
struct StarlapseApp: App {

    init() {
        // Clips and time-lapses are written before anyone decides whether to keep them, and
        // a session that ends by force-quit — or by the battery dying on a tripod at 4am,
        // which is the realistic case — never gets to clean up after itself.
        ScratchStore.purgeLeftovers()
    }

    var body: some Scene {
        WindowGroup {
            CaptureView()
        }
    }
}
