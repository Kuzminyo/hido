#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Boundary to macOS 27's private MenuBarClientCore framework, which can restrict the
// menu bar to an allow-list (it backs the exam "assessment mode"). Approach adapted
// from Hidden Bar by Dwarves Foundation (MIT): https://github.com/dwarvesf/hidden

/// Whether the framework, its classes and selectors are all present on this macOS.
BOOL HidoMenuBarVisibilityIsAvailable(void);

/// Keeps only the given system items and apps visible; macOS hides every other status
/// item and reflows the bar. The completion runs on the main queue with the assertion to
/// hold (hiding lasts until it is invalidated or this process exits) or with an error.
void HidoMenuBarVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                   NSArray<NSString *> *allowedBundleIdentifiers,
                                   void (^completion)(id _Nullable assertion, NSError * _Nullable error));

void HidoMenuBarVisibilityInvalidate(id assertion);

NS_ASSUME_NONNULL_END
