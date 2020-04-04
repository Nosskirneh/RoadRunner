#import "Common.h"
#import "KPCenter.h"
#import "RunningBoard.h"
#import "SettingsKeys.h"


%hook RBProcessManager

%property (nonatomic, retain) KPCenter *kp_center_in;
%property (nonatomic, retain) NSString *nowPlayingBundleID;

/* Setup communication channels from and to SpringBoard */
- (id)initWithBundlePropertiesManager:(id)bundlePropertiesManager
                   entitlementManager:(id)entitlementManager
                   jetsamBandProvider:(id)jetsamBandProvider
                             delegate:(id)delegate {
    self = %orig;

    KPCenter *center = [KPCenter centerNamed:KP_IDENTIFIER_RB];
    [center addTarget:self action:NOW_PLAYING_APP_CHANGED_SELECTOR];
    self.kp_center_in = center;

    return self;
}

%new
- (RBProcess *)processForBundleID:(NSString *)bundleID {
    RBSProcessIdentity *identity = [%c(RBSProcessIdentity) identityForEmbeddedApplicationIdentifier:bundleID];
    return [self processForIdentity:identity];
}

/* Receive information about now playing app changes. */
%new
- (void)nowPlayingAppChanged:(NSDictionary *)data {
    // Clear any previous playing process as not playing
    if (self.nowPlayingBundleID) {
        RBProcess *previousPartyProcess = [self processForBundleID:self.nowPlayingBundleID];
        previousPartyProcess.handle.partying = NO;
        self.nowPlayingBundleID = nil;
    }

    if (data) {
        self.nowPlayingBundleID = data[kApp];
        RBProcess *partyProcess = [self processForBundleID:self.nowPlayingBundleID];
        partyProcess.handle.partying = YES;
    }
}

%end


/* Exclude the now playing process from being killed. */
%hook RBProcess

- (BOOL)terminateWithContext:(RBSTerminateContext *)context {
    RBSProcessHandle *handle = self.handle;

    if (handle.partying || (self.hostProcess && self.hostProcess.handle.partying)) {
        handle.immortal = YES;
        return YES;
    }
    return %orig;
}

%end


/* Used to store properties within RunningBoard. */
%hook RBSProcessHandle

%property (nonatomic, assign) BOOL partying;
%property (nonatomic, assign) BOOL immortal;

- (id)initWithInstance:(id)instance
              lifePort:(id)lifePort
            bundleData:(id)bundleData
              reported:(BOOL)reported {
    self = %orig;
    // These have to be initialized to NO for some reason
    self.partying = NO;
    self.immortal = NO;
    return self;
}

- (id)initWithBSXPCCoder:(BSXPCCoder *)coder {
    self = %orig;

    self.partying = [coder decodeBoolForKey:kPartyingProcess];
    self.immortal = [coder decodeBoolForKey:kImmortalProcess];

    return self;
}

%end


/* Used to transfer information to SpringBoard as binary data.
   Why SpringBoard uses the RBSProcessState and not RunningBoard is
   because updated states are always sent to SpringBoard whereas the
   process handle is not. The required information doesn't get
   propagated if using the latter. */
%hook RBSProcessState

- (void)encodeWithBSXPCCoder:(BSXPCCoder *)coder {
    %orig;

    RBSProcessHandle *handle = self.process;
    [coder encodeBool:handle.partying forKey:kPartyingProcess];
    [coder encodeBool:handle.immortal forKey:kImmortalProcess];
}

%end



%ctor {
    if (%c(RBProcessManager) == nil || !isEnabled())
        return;

    // No need to check license here as SpringBoard checks that
    %init;
}
