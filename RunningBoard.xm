#import "Common.h"
#import "KPCenter.h"
#import "RunningBoard.h"
#import <notify.h>

static inline NSString *getBundleIDForProcess(RBProcess *process) {
    return process.bundleProperties.bundleIdentifier;
}

static inline int getPIDForProcess(RBProcess *process) {
    return [process rbs_pid];
}


%hook RBProcessManager

%property (nonatomic, retain) NSString *nowPlayingBundleID;
%property (nonatomic, retain) RBProcess *immortalProcess;
%property (nonatomic, retain) KPCenter *kp_center_in;

- (id)initWithBundlePropertiesManager:(id)bundlePropertiesManager
                   entitlementManager:(id)entitlementManager
                   jetsamBandProvider:(id)jetsamBandProvider
                             delegate:(id)delegate {
    self = %orig;

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
    // Send information about which PID was prevented from closing
    RBProcess *process = self.immortalProcess;
    if (!process)
        return;

    NSDictionary *processData = @{
        kBundleID : getBundleIDForProcess(process),
        kPID : @(getPIDForProcess(process))
    };

    KPCenter *center = [KPCenter centerNamed:KP_IDENTIFIER_SB];
    [center callExternalMethod:PREVENTED_APP_SHUTDOWN_PID_SELECTOR
                 withArguments:processData
                    completion:nil];
}

%new
- (void)nowPlayingAppChanged:(NSDictionary *)data {
    if (data) {
        self.nowPlayingBundleID = data[kApp];
    } else {
        self.nowPlayingBundleID = nil;
    }
}

- (BOOL)executeTerminateRequest:(RBSTerminateRequest *)request withError:(id *)arg2 {
    // Close any previous immortal app
    if (self.immortalProcess) {
        [self _removeProcess:self.immortalProcess];
    }

    RBSProcessIdentity *identity = request.processIdentity;
    if ([identity.embeddedApplicationIdentifier isEqualToString:self.nowPlayingBundleID]) {
        RBProcess *process = [self processForIdentity:identity];
        self.immortalProcess = process;
        return NO;
    }

    return %orig;
}

%end


%ctor {
    if (%c(RBProcessManager) != nil) {
        %init;
    }
}
