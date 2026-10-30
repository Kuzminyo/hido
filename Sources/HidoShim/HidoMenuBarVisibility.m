#import "HidoMenuBarVisibility.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSString *const kFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const kConfigurationClass = @"MBAssessmentModeConfiguration";
static NSString *const kAssertionClass = @"MBAssessmentModeAssertion";

static NSError *HidoError(NSString *reason) {
    return [NSError errorWithDomain:@"HidoMenuBarVisibility" code:1 userInfo:@{NSLocalizedDescriptionKey: reason}];
}

BOOL HidoMenuBarVisibilityIsAvailable(void) {
    // Resolved at runtime, so a macOS that changes or drops it means "unavailable", not a crash.
    if (!dlopen(kFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
        return NO;
    }
    Class configuration = NSClassFromString(kConfigurationClass);
    Class assertion = NSClassFromString(kAssertionClass);
    return configuration && assertion
        && [configuration instancesRespondToSelector:@selector(initWithAllowedSystemItems:allowedBundleIdentifiers:)]
        && [assertion instancesRespondToSelector:@selector(activateWithConfiguration:completionHandler:)]
        && [assertion instancesRespondToSelector:@selector(invalidate)];
}

void HidoMenuBarVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                   NSArray<NSString *> *allowedBundleIdentifiers,
                                   void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!HidoMenuBarVisibilityIsAvailable()) {
        finish(nil, HidoError(@"MenuBarClientCore is unavailable on this macOS"));
        return;
    }
    @try {
        // The framework indexes into these, so they must be arrays.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(kConfigurationClass) alloc],
            @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(kAssertionClass) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, HidoError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, @selector(activateWithConfiguration:completionHandler:), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, HidoError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void HidoMenuBarVisibilityInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:@selector(invalidate)]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, @selector(invalidate));
        }
    } @catch (NSException *exception) {
        NSLog(@"Hido: invalidate raised %@: %@", exception.name, exception.reason);
    }
}
