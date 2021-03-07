#import "Common.h"
#import "CommonApps.h"
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


static BOOL didConnectToScene;

%group NoNewWindowFix
%hook SceneDelegate

// In some apps, a new window is loaded here in this method.
// If that has already been done, ignore this call.
- (void)scene:(UIScene *)scene willConnectToSession:(id)session options:(id)connectionOptions {
    if (!didConnectToScene) {
        didConnectToScene = YES;
        %orig;
    }
}

%end
%end


@interface UISceneConfiguration : NSObject
- (Class)delegateClass;
@end

static inline void tryInitSceneDelegateHooksForClass(Class delegateClass) {
    if (delegateClass) {
        %init(NoNewWindowFix, SceneDelegate = delegateClass);
    }
}

%hook UISceneConfiguration

- (id)initWithName:(id)name sessionRole:(id)sessionRole {
    self = %orig;
    tryInitSceneDelegateHooksForClass([self delegateClass]);
    return self;
}

- (void)setDelegateClass:(Class)delegateClass {
    %orig;
    tryInitSceneDelegateHooksForClass(delegateClass);
}

%end


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
        addBecomeActiveObserver(^{
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
        });
    }
}
