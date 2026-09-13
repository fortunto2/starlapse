#import "CameraExceptionBarrier.h"

NSString *const StarlapseCameraExceptionDomain = @"co.superduperai.starlapse.camera";

BOOL StarlapseCatchException(void (NS_NOESCAPE ^block)(void), NSError **error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSString *reason = exception.reason ?: exception.name;
            *error = [NSError errorWithDomain:StarlapseCameraExceptionDomain
                                         code:1
                                     userInfo:@{
                                         NSLocalizedDescriptionKey: reason,
                                         @"exceptionName": exception.name
                                     }];
        }
        return NO;
    }
}
