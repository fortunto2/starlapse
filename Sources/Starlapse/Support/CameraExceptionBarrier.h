#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Run a block, turning an Objective-C exception into an `NSError`.
///
/// `AVCaptureDevice` validates its arguments by raising `NSException` — zoom factors,
/// frame durations and lens positions outside what the *current* format allows. Swift
/// cannot catch those: the runtime kills the process instead, and the user sees the app
/// close the moment it touches the camera. Every hardware setter in `CaptureEngine` goes
/// through here, so an unsupported value costs a log line rather than a session.
///
/// Deliberately fine-grained: the block wraps one call, so the exception never unwinds
/// past a Swift frame that owns a `lockForConfiguration`.
BOOL StarlapseCatchException(void (NS_NOESCAPE ^ _Nonnull block)(void),
                             NSError *_Nullable *_Nullable error);

extern NSString *const StarlapseCameraExceptionDomain;

NS_ASSUME_NONNULL_END
