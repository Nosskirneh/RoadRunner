#import <MediaRemote/MediaRemote.h>
#import "Common.h"
#import "KPCenter.h"
#import "FrontBoard.h"


%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)arg1 {
    %orig;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidChange:)
                                                 name:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                                               object:nil];
}

%new
- (void)appDidChange:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSNumber *pid = info[(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    NSDictionary *data = nil;

    if (pid) {
        int p = [pid intValue];
        FBApplicationProcess *app = [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:p];
        data = @{
            kApp : app.bundleIdentifier
        };
    }
    KPCenter *center = [KPCenter centerNamed:KP_IDENTIFIER];
    [center callExternalMethod:NOW_PLAYING_APP_CHANGED_SELECTOR
                 withArguments:data
                    completion:nil];
}

%end


%ctor {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if ([bundleID isEqualToString:kSpringBoardBundleID])
        %init;
}
