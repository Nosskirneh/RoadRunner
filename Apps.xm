#import "Common.h"
#import <notify.h>
#import <Foundation/Foundation.h>
#import <HBLog.h>
#import <UIKit/UIKit.h>

@interface UIScene : UIResponder
@end

@interface UIWindowScene : UIScene
@end

@interface UIWindow (Private)
- (UIResponder *)firstResponder;
@property (assign, nonatomic) UIWindowScene *windowScene;
@end

@interface UIKeyboard : UIView
@property (assign, getter=isMinimized, nonatomic) BOOL minimized;
+ (id)activeKeyboard;
@end

@interface _UISceneLifecycleMultiplexer : NSObject
+ (UIWindowScene *)mostActiveScene;
@end

static void addBecomeActiveObserver() {
    __block void (^becomeActiveCompletion)() = ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;

        // This fixes an issue where the action menus would not appear
        // after the application was excluded
        keyWindow.hidden = YES;
        [keyWindow makeKeyAndVisible];

        // This fixes an issue where some apps (Spotify) would have a black window
        [keyWindow setWindowScene:[%c(_UISceneLifecycleMultiplexer) mostActiveScene]];

        // This fixes an issue where the keyboard would not get visible
        UIResponder *responder = [keyWindow firstResponder];
        if (responder) {
            [responder resignFirstResponder];
            ((UIKeyboard *)[%c(UIKeyboard) activeKeyboard]).minimized = YES;

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [responder becomeFirstResponder];
            });
        }
    };

    __weak NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    __weak __block id observer = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                                     object:nil
                                                      queue:nil
                                                 usingBlock:^(NSNotification *notification) {
        if (becomeActiveCompletion) {
            becomeActiveCompletion();
            becomeActiveCompletion = nil;

            [center removeObserver:observer];
        }
    }];
}

%ctor {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *bundleID = [bundle bundleIdentifier];
    if (!bundleID) // nfcd and tursd are two deamons that loads TextInput
        return;

    NSDictionary *infoDictionary = [bundle infoDictionary];
    NSString *bundleType = infoDictionary[@"CFBundlePackageType"];
    /* Ignore those bundles that don't specify the type.
       Also ignore bundles that don't have the type APPL (Apps). */
    if (!bundleType || ![bundleType isEqualToString:@"APPL"]) {
        return;
    }

    NSSet *blacklistedBundleIDs = [NSSet setWithArray:@[@"com.apple.springboard",
                                                        @"com.apple.Spotlight",
                                                        @"com.apple.iMessageAppsViewService"]];

    if (![blacklistedBundleIDs containsObject:bundleID]) {
        int token;
        notify_register_dispatch(kRoadRunnerSpringBoardRestarted,
            &token,
            dispatch_get_main_queue(),
            ^(int _) {
                addBecomeActiveObserver();
            }
        );
    }
}
