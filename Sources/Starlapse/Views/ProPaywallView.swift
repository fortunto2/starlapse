import SuperDuperAnalytics
import SwiftUI

/// What Pro is, what it costs, and what stays free. Shown from the status panel when
/// an event is on tonight and the phone has not bought the events.
struct ProPaywallView: View {

    let entitlements: Entitlements
    @Environment(\.dismiss) private var dismiss

    private static let included: [(String, String)] = [
        ("Tonight's events", "Active meteor showers with the expected rate, every night of the year."),
        ("Where to aim", "The target 40° off the radiant and clear of the Moon, with the arrow to it."),
        ("Peak nights", "When each shower peaks, and the Moon-free window around it."),
        ("Everything coming", "Comets, conjunctions, eclipses, dark frames: added to Pro, never charged again."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("STARLAPSE PRO")
                    .font(NightTheme.mono(16, weight: .bold))
                    .foregroundStyle(NightTheme.primary)
                Text("One purchase. The sky's events, for as long as there is a sky.")
                    .font(NightTheme.mono(11))
                    .foregroundStyle(NightTheme.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Self.included, id: \.0) { title, detail in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title.uppercased())
                                .font(NightTheme.mono(11, weight: .bold))
                                .foregroundStyle(NightTheme.accent)
                            Text(detail)
                                .font(NightTheme.mono(10))
                                .foregroundStyle(NightTheme.dim)
                        }
                    }
                }
                .nightPanel()

                Text("""
                    Free, and staying free: the manual camera, stacking, star trails, \
                    time-lapse, the meteor detector, and the overlay with planets, bright \
                    stars and the Moon.
                    """)
                    .font(NightTheme.mono(10))
                    .foregroundStyle(NightTheme.dim)

                if entitlements.isPro {
                    Text("UNLOCKED. CLEAR SKIES.")
                        .font(NightTheme.mono(12, weight: .bold))
                        .foregroundStyle(NightTheme.accent)
                } else {
                    Button {
                        Task {
                            await entitlements.purchase()
                            if entitlements.isPro { dismiss() }
                        }
                    } label: {
                        Text(buyTitle)
                            .font(NightTheme.mono(13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(NightTheme.accent)
                    .disabled(entitlements.isPurchasing)

                    Button("Restore purchase") {
                        Task {
                            await entitlements.restore()
                            if entitlements.isPro { dismiss() }
                        }
                    }
                    .font(NightTheme.mono(11))
                    .foregroundStyle(NightTheme.secondary)
                }

                if let error = entitlements.lastError {
                    Text(error)
                        .font(NightTheme.mono(10))
                        .foregroundStyle(NightTheme.accent)
                }

                Text("""
                    The purchase goes to Apple. Starlapse sends nothing else, except a usage \
                    counter you can switch off.
                    """)
                    .font(NightTheme.mono(9))
                    .foregroundStyle(NightTheme.dim)
            }
            .padding(16)
        }
        .background(NightTheme.background)
        .task {
            Analytics.track("paywall_shown")
            if entitlements.product == nil { await entitlements.refresh() }
        }
    }

    private var buyTitle: String {
        if let price = entitlements.product?.displayPrice { return "UNLOCK FOR \(price)" }
        return "UNLOCK"
    }
}
