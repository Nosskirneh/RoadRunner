#import "Common.h"
#import "KPCenter.h"
#import "RunningBoard.h"


%hook RBProcessManager

%property (retain) NSString *nowPlayingBundleID;
%property (retain) KPCenter *kp_center;

- (id)initWithBundlePropertiesManager:(id)arg1
                   entitlementManager:(id)arg2
                   jetsamBandProvider:(id)arg3
                             delegate:(id)arg4 {
    %log;
    self = %orig;

    KPCenter *center = [KPCenter centerNamed:KP_IDENTIFIER];
    [center addTarget:self action:NOW_PLAYING_APP_CHANGED_SELECTOR];

    self.kp_center = center;

    // notify_register_dispatch(kSettingsChanged,
    //     &_notifyTokenForSettingsChanged,
    //     dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
    //     ^(int _) {
            
    //     }
    // );

    return self;
}

%new
- (void)nowPlayingAppChanged:(NSDictionary *)data {
    if (data)
        self.nowPlayingBundleID = data[kApp];
}

- (BOOL)executeTerminateRequest:(RBSTerminateRequest *)request withError:(id *)arg2 {
    RBSProcessIdentity *identity = request.processIdentity;
    if ([identity.embeddedApplicationIdentifier isEqualToString:self.nowPlayingBundleID])
        return NO;

    return %orig;
}

%end


%ctor {
    if (%c(RBProcessManager) != nil)
        %init;
}
