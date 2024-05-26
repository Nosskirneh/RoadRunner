#import "Common.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "RRManager.h"
#import <HBLog.h>
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

%ctor {
    if (%c(SpringBoard)) {
        if (!isEnabled())
            return;
        %init;
        %init(RBSBootstrap,
            _handleDaemonDidStart = MSFindSymbol(NULL, "-[RBSConnection _handleDaemonDidStart]"),
            _init = MSFindSymbol(NULL, "-[RBSService _init]")
        );
        manager = [[RRManager alloc] init];
    }
}
