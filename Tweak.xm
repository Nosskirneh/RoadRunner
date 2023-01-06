#import "Common.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "RRManager.h"
#import <HBLog.h>
#import "DRMValidateOptions.mm"


RRManager *manager;


/* Transfer the binary data back to our properties. */
%hook RBSProcessState

%property (nonatomic, assign) BOOL partying;
%property (nonatomic, assign) BOOL immortal;

static RBSProcessState *initProcessStateWithCoder(RBSProcessState *self, BSXPCCoder *coder) {
    self.partying = [coder decodeBoolForKey:kPartyingProcess];
    self.immortal = [coder decodeBoolForKey:kImmortalProcess];
    return self;
}

%group RBSProcessState_iOS13
- (id)initWithBSXPCCoder:(BSXPCCoder *)coder {
    return initProcessStateWithCoder(%orig, coder);
}
%end

%group RBSProcessState_iOS14
- (id)initWithRBSXPCCoder:(BSXPCCoder *)coder {
    return initProcessStateWithCoder(%orig, coder);
}
%end

%end


%group iOS14
%hookf(void, _handleDaemonDidStart, RBSConnection *self, SEL _cmd) {
    %orig;

    [manager handleDaemonDidStart];
}
%end

%group iOS13
%hook RBSConnection

- (void)_handleDaemonDidStart {
    %orig;

    [manager handleDaemonDidStart];
}

%end
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


typedef struct : IInitFunctions {
    void normal() {
        %init;

        if ([%c(RBSConnection) instancesRespondToSelector:@selector(_handleDaemonDidStart)]) {
            %init(iOS13);
        } else {
            %init(iOS14, _handleDaemonDidStart = MSFindSymbol(NULL, "-[RBSConnection _handleDaemonDidStart]"));
        }

        if ([%c(RBSProcessState) instancesRespondToSelector:@selector(encodeWithBSXPCCoder:)]) {
            %init(RBSProcessState_iOS13);
        } else {
            %init(RBSProcessState_iOS14);
        }
    };
    void welcome() {
        %init(Welcome);
    };
    void trial() {
        %init(CheckTrialEnded);
    };
    void pirated() {
        %init(PackagePirated);
    };
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
