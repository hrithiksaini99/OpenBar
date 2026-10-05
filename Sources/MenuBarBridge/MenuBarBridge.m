#import "MenuBarBridge.h"
#import <dlfcn.h>
#import <objc/runtime.h>

// This deliberately resolves private symbols only at runtime. There is no
// framework link dependency, so a changed OS leaves the unrestricted bar usable.
static NSString *const OBFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const OBErrorDomain = @"OpenBar.NativeVisibility";

@protocol OBMenuBarPrivateMessages
- (id)initWithAllowedSystemItems:(NSArray<NSNumber *> *)items
       allowedBundleIdentifiers:(NSArray<NSString *> *)bundles;
- (void)activateWithConfiguration:(id)configuration
               completionHandler:(void (^)(NSError * _Nullable error))completion;
- (void)invalidate;
@end

static NSError *OBError(NSInteger code, NSString *reason) {
    return [NSError errorWithDomain:OBErrorDomain code:code
                          userInfo:@{NSLocalizedDescriptionKey: reason}];
}

static BOOL OBHasSignature(Class cls, SEL selector, unsigned int argumentCount, char returnType) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != argumentCount) return NO;
    char result[16] = {0};
    method_getReturnType(method, result, sizeof(result));
    if (result[0] != returnType) return NO;
    for (unsigned int index = 2; index < argumentCount; index++) {
        char argument[16] = {0};
        method_getArgumentType(method, index, argument, sizeof(argument));
        if (argument[0] != '@') return NO;
    }
    return YES;
}

BOOL OBNativeVisibilityIsAvailable(void) {
    static BOOL available = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Keep the framework loaded for the process lifetime: its objects and
        // asynchronous callbacks can outlive any one visibility request.
        void *framework = dlopen(OBFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!framework) return;
        Class configuration = NSClassFromString(@"MBAssessmentModeConfiguration");
        Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
        available = configuration && assertion
            && OBHasSignature(configuration, @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:), 4, '@')
            && OBHasSignature(assertion, @selector(activateWithConfiguration:completionHandler:), 4, 'v')
            && OBHasSignature(assertion, @selector(invalidate), 2, 'v');
    });
    return available;
}

static NSError * _Nullable OBInvalidateAssertion(id<OBMenuBarPrivateMessages> assertion) {
    if (!assertion) return nil;
    @try {
        [assertion invalidate];
        return nil;
    } @catch (NSException *exception) {
        return OBError(4, [NSString stringWithFormat:@"Could not restore menu bar: %@: %@", exception.name, exception.reason]);
    }
}

@implementation OBNativeVisibilityToken {
    id<OBMenuBarPrivateMessages> _assertion;
    BOOL _invalidated;
    BOOL _started;
    BOOL _completed;
}

- (void)activateWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
             allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                           completion:(void (^)(NSError * _Nullable))completion {
    NSAssert(NSThread.isMainThread, @"Visibility activation must run on the main thread");
    if (_started || _invalidated || !OBNativeVisibilityIsAvailable()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(OBError(1, @"Native menu bar visibility is unavailable or this request has been cancelled."));
        });
        return;
    }
    _started = YES;
    @try {
        id configuration = [(id<OBMenuBarPrivateMessages>)[NSClassFromString(@"MBAssessmentModeConfiguration") alloc]
            initWithAllowedSystemItems:[systemItems copy]
            allowedBundleIdentifiers:[bundleIdentifiers copy]];
        _assertion = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!configuration || !_assertion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(OBError(2, @"macOS could not create a menu bar visibility assertion."));
            });
            return;
        }
        // Retain the token and raw assertion until the framework answers, even
        // after Swift cancels or times out. This is essential: the callback can
        // report successful activation after an earlier invalidate().
        id<OBMenuBarPrivateMessages> rawAssertion = _assertion;
        [_assertion activateWithConfiguration:configuration completionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_completed) return;
                self->_completed = YES;
                if (self->_invalidated || error) {
                    NSError *restoreError = OBInvalidateAssertion(rawAssertion);
                    completion(restoreError ?: error ?: OBError(3, @"Menu bar visibility request was cancelled."));
                } else {
                    completion(nil);
                }
            });
        }];
    } @catch (NSException *exception) {
        NSError *restoreError = [self invalidate];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_completed) return;
            self->_completed = YES;
            completion(restoreError ?: OBError(2, [NSString stringWithFormat:@"Menu bar visibility failed: %@: %@", exception.name, exception.reason]));
        });
    }
}

- (NSError *)invalidate {
    NSAssert(NSThread.isMainThread, @"Visibility invalidation must run on the main thread");
    _invalidated = YES;
    // Do not discard the raw handle on failure or while activation is pending.
    // Calling this again is intentional and enables recovery after a late success.
    return OBInvalidateAssertion(_assertion);
}

- (void)dealloc {
    id<OBMenuBarPrivateMessages> assertion = _assertion;
    if (!assertion) return;
    if (NSThread.isMainThread) {
        NSError *error = OBInvalidateAssertion(assertion);
        if (error) NSLog(@"OpenBar: %@", error.localizedDescription);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error = OBInvalidateAssertion(assertion);
            if (error) NSLog(@"OpenBar: %@", error.localizedDescription);
        });
    }
}

@end
