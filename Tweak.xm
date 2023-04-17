#import "Common.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "RRManager.h"
#import <HBLog.h>
#if DRM == 1
#import "DRMValidateOptions.mm"
#endif
#import "DecodeProcessStateHooks.h"


RRManager *manager;

// When runningboardd restarts, this fires
%group RBSBootstrap
%hookf(void, _handleDaemonDidStart, RBSConnection *self, SEL _cmd) {
    %orig;
    [manager handleDaemonDidStart];
}

// When SpringBoard restarts, this fires
%hookf(id, _init, RBSService *self, SEL _cmd) {
    self = %orig;
    [manager handleDaemonDidStart];
    return self;
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


#if DRM == 1
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
#endif


typedef struct : IInitFunctions {
    void normal() {
        %init;
        %init(RBSBootstrap,
            _handleDaemonDidStart = MSFindSymbol(NULL, "-[RBSConnection _handleDaemonDidStart]"),
            _init = MSFindSymbol(NULL, "-[RBSService _init]")
        );

        initDecodeProcessStateHooks();
    };
    #if DRM == 1
    void welcome() {
        %init(Welcome);
    };
    void trial() {
        %init(CheckTrialEnded);
    };
    void pirated() {
        %init(PackagePirated);
    };
    #else
    void welcome() {}
    void trial() {}
    void pirated() {}
    #endif
} InitFunctions;

IInitFunctions *initFunctions;

%ctor {
    if (%c(SpringBoard)) {
        if (!isEnabled())
            return;
        InitFunctions _initFunctions = InitFunctions();
        initFunctions = &_initFunctions;
        manager = [[RRManager alloc] init];
    }
}
