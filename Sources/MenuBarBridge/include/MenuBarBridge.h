#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Probes the private framework without applying a visibility restriction.
FOUNDATION_EXPORT BOOL OBNativeVisibilityIsAvailable(void);

/// Keeps ownership of the underlying assertion throughout activation and cleanup.
/// Every method must be called on the main thread. Completions use the main queue.
@interface OBNativeVisibilityToken : NSObject

- (void)activateWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
             allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                           completion:(void (^)(NSError * _Nullable error))completion
    NS_SWIFT_NAME(activate(allowedSystemItems:allowedBundleIdentifiers:completion:));

/// Invalidates pending as well as active requests. Late activation is invalidated
/// again before its completion is delivered. A returned error means retry is needed.
- (nullable NSError *)invalidate NS_SWIFT_NAME(invalidate());

@end

NS_ASSUME_NONNULL_END
