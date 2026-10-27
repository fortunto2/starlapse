/// What a star-aligned stack does with one frame, given how many stars it holds.
///
/// "Drop a frame whose alignment failed" protects a stack that is tracking the sky. It
/// must not fire before tracking has started: a city sky, cloud or a room never shows six
/// stars, so every frame was dropped, nothing was stacked, and Save wrote the framing
/// frame instead (1.1.0: 10 of 28 saved stills reported zero frames). With nothing to
/// align on, the phone is the reference, as it is for the smooth stack.
public enum StarTracking: Equatable, Sendable {
    /// No star seen yet this session: accumulate without a transform.
    case stackInPlace
    /// The first frame with enough stars: it defines the reference.
    case reference
    /// Solve against the previous frame.
    case align
    /// Stars were tracked and are gone (cloud, a bumped tripod): drop it.
    case drop

    /// Fewest stars a frame needs to define or follow the reference.
    public static let minimumStars = 6

    public static func decide(starCount: Int, hasReference: Bool) -> Self {
        switch (starCount >= minimumStars, hasReference) {
        case (true, false): .reference
        case (true, true): .align
        case (false, false): .stackInPlace
        case (false, true): .drop
        }
    }
}
