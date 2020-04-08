#import "Common.h"
#import "RRCenter.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "RRManager.h"
#import "DRMValidateOptions.mm"


RRManager *manager;


/* Any previously excluded process needs to be manually
   killed when the user wants to. I suspect this is
   because the process is no longer being tracked. */
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


/* Overriding this solves issues where iOS wouldn't
   consider the reattached process as playing media. */
%hook SBMediaController

+ (BOOL)applicationCanBeConsideredNowPlaying:(SBApplication *)app {
    if ([app.bundleIdentifier isEqualToString:manager.immortalPartyingBundleID]) {
        return YES;
    }

    return %orig;
}

%end


/* Transfer the binary data back to our properties. */
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


%hook RBSConnection

- (void)_handleDaemonDidStart {
    %orig;

    [manager handleDaemonDidStart];
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
    if (%c(SpringBoard)) {
        if (!isEnabled())
            return;

        if (fromUntrustedSource(package$bs()))
            %init(PackagePirated);

        manager = [[RRManager alloc] init];

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
