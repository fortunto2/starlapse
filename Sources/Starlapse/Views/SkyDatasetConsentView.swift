import SwiftUI

/// Asked once, after the first saved shot: whether this phone contributes to the dataset.
struct SkyDatasetConsentView: View {

    let model: CaptureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HELP MAP THE NIGHT SKY")
                .font(NightTheme.mono(14, weight: .bold))
                .foregroundStyle(NightTheme.primary)
            Text("Every stack measures how dark your sky is, from the stars in it. Shared, these readings map light pollution the way Globe at Night does, but from real photos instead of guesses.") // swiftlint:disable:this line_length
                .font(NightTheme.mono(11))
                .foregroundStyle(NightTheme.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Sent: the sky reading, the camera settings, the photo, and where to about 10 km.")
                Text("Never: your name, your exact location, or anything to identify you.")
                Text("Published as open data under CC BY 4.0, so anyone can study it.")
                Text("Change it or delete everything sent in Settings › SKY DATASET.")
            }
            .font(NightTheme.mono(10))
            .foregroundStyle(NightTheme.dim)
            Spacer(minLength: 0)
            Button {
                model.answerConsent(true)
            } label: {
                Text("Contribute")
                    .font(NightTheme.mono(13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(NightTheme.accent)
            Button {
                model.answerConsent(false)
            } label: {
                Text("No thanks")
                    .font(NightTheme.mono(12))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .foregroundStyle(NightTheme.secondary)
        }
        .padding(24)
        .background(NightTheme.background)
        .interactiveDismissDisabled()
    }
}
