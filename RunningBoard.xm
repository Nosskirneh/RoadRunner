#import "Common.h"
#import "KPCenter.h"
#import "RunningBoard.h"
#import "SettingsKeys.h"


%hook RBProcessManager

%property (nonatomic, retain) KPCenter *kp_center_in;
%property (nonatomic, retain) NSString *immortalProcessBundleID;
%property (nonatomic, retain) NSString *nowPlayingBundleID;

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

%new
- (void)nowPlayingAppChanged:(NSDictionary *)data {
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


%hook RBSProcessHandle

%property (nonatomic, assign) BOOL partying;
%property (nonatomic, assign) BOOL immortal;

- (id)initWithInstance:(id)arg1 lifePort:(id)arg2 bundleData:(id)arg3 reported:(BOOL)arg4 {
    self = %orig;
    self.partying = NO;
    self.immortal = NO;
    return self;
}

%end


%hook RBProcess

- (BOOL)terminateWithContext:(RBSTerminateContext *)context {
    if (self.handle.partying || (self.hostProcess && self.hostProcess.handle.partying)) {
        self.handle.immortal = YES;
        return YES;
    }
    return %orig;
}

%end


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

    %init;
}
