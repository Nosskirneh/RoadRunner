#import "Common.h"
#import "RunningBoard.h"
#import "SettingsKeys.h"

#import <xpc/xpc.h>
typedef NSObject<OS_xpc_object> *xpc_object_t;


%hook RBProcessManager

%property (nonatomic, retain) NSString *nowPlayingBundleID;

%new
- (RBProcess *)processForBundleID:(NSString *)bundleID {
    RBSProcessIdentity *identity = [%c(RBSProcessIdentity) identityForEmbeddedApplicationIdentifier:bundleID];
    return [self processForIdentity:identity];
}

/* Receive information about now playing app changes. */
%new
- (void)nowPlayingAppChanged:(NSString *)bundleID {
    // Clear any previous playing process as not playing
    if (self.nowPlayingBundleID) {
        RBProcess *previousPartyProcess = [self processForBundleID:self.nowPlayingBundleID];
        previousPartyProcess.handle.partying = NO;
        self.nowPlayingBundleID = nil;
    }

    if (bundleID) {
        self.nowPlayingBundleID = bundleID;
        RBProcess *partyProcess = [self processForBundleID:self.nowPlayingBundleID];
        partyProcess.handle.partying = YES;
    }
}

- (BOOL)executeTerminateRequest:(RBSTerminateRequest *)request withError:(id *)error {
    // In case the partying app is updated by the user, allow it to get killed
    if (request.context.exceptionCode == kInstallUpdateCode) {
        RBProcess *process = [self processForIdentity:request.processIdentity];
        process.handle.partying = NO;

        // For some reason, this was necessary
        [process terminateWithContext:request.context];
    }

    return %orig;
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

- (void)encodeWithBSXPCCoder:(BSXPCCoder *)coder {
    %orig;

    [coder encodeBool:self.partying forKey:kPartyingProcess];
    [coder encodeBool:self.immortal forKey:kImmortalProcess];
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


/* Messages for change of media app is sent using the stock
   iOS XPC communication channel. */
%hook RBConnectionClient

- (void)handleMessage:(xpc_object_t)xpc_dictionary {
    const char *selector = xpc_dictionary_get_string(xpc_dictionary, "rbs_selector");
    if (selector != NULL) {
        const char *desiredSelector = sel_getName(NOW_PLAYING_APP_CHANGED_SELECTOR);
        if (strcmp(selector, desiredSelector) == 0) {
            const char *identifier = xpc_dictionary_get_string(xpc_dictionary, "rbs_argument_0");
            RBProcessManager *processManager = MSHookIvar<RBProcessManager *>(self, "_processManager");
            NSString *bundleID = identifier ? [NSString stringWithUTF8String:identifier] : nil;
            [processManager nowPlayingAppChanged:bundleID];

            return;
        }
    }

    %orig;
}

%end


%ctor {
    if (%c(RBProcessManager) == nil || !isEnabled())
        return;

    // No need to check license here as SpringBoard checks that
    %init;
}
