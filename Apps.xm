#import "Common.h"
#import "CommonApps.h"
#import <Foundation/Foundation.h>
#import <HBLog.h>
#import <UIKit/UIKit.h>
#import "DecodeProcessStateHooks.h"
#import "RunningBoardServices.h"

@interface UIScene : UIResponder
@end

@interface UIWindowScene : UIScene
- (NSArray<UIWindow *> *)_allWindows;
- (void)_attachWindow:(UIWindow *)window;
@end

@interface UISceneSession : NSObject
@property (nonatomic, readonly) NSString *role;
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


%group NoNewWindowFix
static UIWindowScene *oldWindowScene;

%hook SceneDelegate

// We need to create a new FBScene in SpringBoard when opening the app again.
// This is done automatically, but when doing so, some apps create a new window
// scene that does not contain the key window. To solve this, we simply move
// all the windows to the right scene.
- (void)scene:(UIWindowScene *)scene willConnectToSession:(UISceneSession *)session options:(id)connectionOptions {
    if ([session.role isEqualToString:@"UIWindowSceneSessionRoleApplication"]) {
        RBSProcessState *state = [[%c(RBSProcessHandle) currentProcess] currentState];
        if (state.immortal) {
            NSArray *allWindows = [oldWindowScene _allWindows];
            for (UIWindow *window in allWindows) {
                [scene _attachWindow:window];
            }
        }

        oldWindowScene = scene;
    }
    %orig;
}

%end
%end


@interface UISceneConfiguration : NSObject
- (Class)delegateClass;
@end

static inline void tryInitSceneDelegateHooksForClass(Class delegateClass) {
    if (delegateClass) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            %init(NoNewWindowFix, SceneDelegate = delegateClass);
        });
    }
}

%hook UISceneConfiguration

- (id)_initWithConfiguration:(id)arg1 {
    UISceneConfiguration *_self = %orig;
    tryInitSceneDelegateHooksForClass([_self delegateClass]);
    return _self;
}

- (id)initWithName:(id)name sessionRole:(id)sessionRole {
    self = %orig;
    tryInitSceneDelegateHooksForClass([self delegateClass]);
    return self;
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
        %init;
        initDecodeProcessStateHooks();

        addBecomeActiveObserver(^{
            UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;

            // This fixes an issue where the action menus would not appear
            // after the application was excluded
            keyWindow.hidden = YES;
            [keyWindow makeKeyAndVisible];

            // This fixes an issue where some apps (Spotify) would have a black window
            if (!keyWindow.windowScene) {
                [keyWindow setWindowScene:[%c(_UISceneLifecycleMultiplexer) mostActiveScene]];
            }

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
