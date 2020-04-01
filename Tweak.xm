#import "Common.h"
#import "KPCenter.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "KPManager.h"


KPManager *manager;


%hook SBFluidSwitcherViewController

- (void)killContainer:(SBReusableSnapshotItemContainer *)container
            forReason:(long long)reason {
    SBAppLayout *appLayout = container.snapshotAppLayout;
    NSString *bundleID = [appLayout allItems][0].bundleIdentifier;
    RBSProcessIdentity *identity = [%c(RBSProcessIdentity) identityForEmbeddedApplicationIdentifier:bundleID];

    RBSConnection *connection = [%c(RBSConnection) sharedInstance];
    NSMutableDictionary *states = MSHookIvar<NSMutableDictionary *>(connection, "_stateByIdentity");
    RBSProcessState *state = states[identity];

    if (state.immortal) {
        [manager killImmortalPID:state.process.pid];
    }

    %orig;
}

%end



%hook SBMediaController

+ (BOOL)applicationCanBeConsideredNowPlaying:(SBApplication *)app {
    if ([app.bundleIdentifier isEqualToString:manager.immortalPartyingBundleID]) {
        return YES;
    }

    return %orig;
}

%end


%hook RBSProcessState

%property (nonatomic, assign) BOOL partying;
%property (nonatomic, assign) BOOL immortal;

- (id)initWithBSXPCCoder:(BSXPCCoder *)coder {
    self = %orig;

    self.partying = [coder decodeBoolForKey:kPartyingProcess];
    self.immortal = [coder decodeBoolForKey:kImmortalProcess];

    return self;
}

%end


%ctor {
    if (%c(SpringBoard) || %c(FBProcessManager)) {
        if (!isEnabled())
            return;

        manager = [[KPManager alloc] init];
        %init;
    }
}
