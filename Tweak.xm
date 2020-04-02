#import "Common.h"
#import "KPCenter.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "KPManager.h"
#import "DRMValidateOptions.mm"


KPManager *manager;


%hook SBFluidSwitcherViewController

- (void)killContainer:(SBReusableSnapshotItemContainer *)container
            forReason:(long long)reason {
    SBAppLayout *appLayout = container.snapshotAppLayout;
    NSString *bundleID = [appLayout allItems][0].bundleIdentifier;
    RBSProcessIdentity *identity = [%c(RBSProcessIdentity) identityForEmbeddedApplicationIdentifier:bundleID];

    NSDictionary *states = [manager getAllProcessStates];
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



%group PackagePirated
%hook SBCoverSheetPresentationManager

- (void)_cleanupDismissalTransition {
    %orig;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        showPiracyAlert(packageShown$bs());
    });
}

%end
%end


%group Welcome
%hook SBCoverSheetPresentationManager

- (void)_cleanupDismissalTransition {
    %orig;
    showSpringBoardDismissAlert(packageShown$bs(), WelcomeMsg$bs());
}

%end
%end


%group CheckTrialEnded
%hook SBCoverSheetPresentationManager

- (void)_cleanupDismissalTransition {
    %orig;

    if (!manager.trialEnded && check_lic(licensePath$bs(), package$bs()) == CheckInvalidTrialLicense) {
        [manager setTrialEnded];
        showSpringBoardDismissAlert(packageShown$bs(), TrialEndedMsg$bs());
    }
}

%end
%end

__attribute__((always_inline, visibility("hidden")))
static inline void initTrial() {
    %init(CheckTrialEnded);
}


%ctor {
    if (%c(SpringBoard) || %c(FBProcessManager)) {
        if (!isEnabled())
            return;

        if (fromUntrustedSource(package$bs()))
            %init(PackagePirated);

        manager = [[KPManager alloc] init];

        /* License check – if no license found, present message.
           If no valid license found, do not init. */
        switch (check_lic(licensePath$bs(), package$bs())) {
            case CheckNoLicense:
                %init(Welcome);
                return;
            case CheckInvalidTrialLicense:
                initTrial();
                return;
            case CheckValidTrialLicense:
                initTrial();
                break;
            case CheckValidLicense:
                break;
            case CheckInvalidLicense:
            case CheckUDIDsDoNotMatch:
            default:
                return;
        }
        // ---

        [manager setup];
        %init;
    }
}
