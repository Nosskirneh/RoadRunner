#import <notify.h>
#import "Common.h"
#import "CommonApps.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


int addBecomeActiveObserver(void (^becomeActiveCompletion)()) {
    int token;
    notify_register_dispatch(kRoadRunnerSpringBoardRestarted,
        &token,
        dispatch_get_main_queue(),
        ^(int _) {
            __weak NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            __weak __block id observer = [center addObserverForName:UIApplicationDidBecomeActiveNotification
                                                             object:nil
                                                              queue:nil
                                                         usingBlock:^(NSNotification *notification) {
                becomeActiveCompletion();
                [center removeObserver:observer];
            }];
        }
    );
    return token;
}
