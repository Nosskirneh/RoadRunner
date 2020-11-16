#import "CommonApps.h"
#import <UIKit/UIKit.h>

/* This is an ugly quick-fix for MobileTerminal launching with a black
   screen when being excluded termination. */

@interface MTATabBarController : UIViewController
@end

static MTATabBarController *tabBarController;

%hook MTATabBarController

- (id)initWithAlarmManager:(id)alarmManager alarmDataSource:(id)alarmDataSource timerManager:(id)timerManager {
    return tabBarController ? tabBarController : (tabBarController = %orig);
}

%end


%ctor {
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.mobiletimer"]) {
        %init;
        addBecomeActiveObserver(^{
            UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;

            if (tabBarController) {
                keyWindow.rootViewController = tabBarController;
            }
        });
    }
}
