#import "Common.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "RRManager.h"
#import "DRMValidateOptions.mm"


RRManager *manager;


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
                // In case the user is running a trial license and then removes it
                [manager setTrialEnded];
                return;
        }
        // ---

        [manager setup];
        %init;
    }
}
