#import "Common.h"
#import "KPCenter.h"
#import "RunningBoard.h"
#import <notify.h>


%hook RBProcessManager

%property (nonatomic, retain) NSString *nowPlayingBundleID;
%property (nonatomic, retain) RBProcess *savedProcess;
%property (nonatomic, retain) KPCenter *kp_center_in;
%property (nonatomic, retain) KPCenter *kp_center_out;

- (id)initWithBundlePropertiesManager:(id)bundlePropertiesManager
                   entitlementManager:(id)entitlementManager
                   jetsamBandProvider:(id)jetsamBandProvider
                             delegate:(id)delegate {
    %log;
    self = %orig;
    self.savedProcess = 0;

    KPCenter *center = [KPCenter centerNamed:KP_IDENTIFIER_RB];
    [center addTarget:self action:NOW_PLAYING_APP_CHANGED_SELECTOR];
    [center addTarget:self action:SB_LOADED];
    self.kp_center_in = center;

    // notify_register_dispatch(kSettingsChanged,
    //     &_notifyTokenForSettingsChanged,
    //     dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
    //     ^(int _) {

    //     }
    // );

    return self;
}

%new
- (void)springBoardLoaded:(NSDictionary *)data {
    %log;
    log(@"SB loaded...");
    // Send information about which PID was prevented from closing

    RBProcess *savedProcess = self.savedProcess;
    log(@"self.savedProcess: %lu", (unsigned long)[savedProcess rbs_pid]);
    if (self.savedProcess) {
        NSError *error;
        [%c(RBLaunchdJobRegistry) _submitJob:savedProcess.job error:&error];
        log(@"error: %@", error);

        NSDictionary *data = @{
            kPID : @([savedProcess rbs_pid]),
            kBundleID : savedProcess.bundleProperties.bundleIdentifier
        };
        log(@"calling PREVENTED_APP_SHUTDOWN_PID_SELECTOR");

        KPCenter *center = [KPCenter centerNamed:KP_IDENTIFIER_SB];
        [center callExternalMethod:PREVENTED_APP_SHUTDOWN_PID_SELECTOR
                     withArguments:data
                        completion:nil];
        // self.savedProcess = nil;
    }
}

%new
- (void)nowPlayingAppChanged:(NSDictionary *)data {
    %log;
    if (data)
        self.nowPlayingBundleID = data[kApp];
}

- (BOOL)executeTerminateRequest:(RBSTerminateRequest *)request withError:(id *)arg2 {
    %log;
    RBSProcessIdentity *identity = request.processIdentity;
    if ([identity.embeddedApplicationIdentifier isEqualToString:self.nowPlayingBundleID]) {
        RBProcess *process = [self processForIdentity:identity];
        log(@"saving savedProcess: %@", process);
        self.savedProcess = process;
        return NO;
    }

    return %orig;
}

%end


%ctor {
    if (%c(RBProcessManager) != nil)
        %init;
}
