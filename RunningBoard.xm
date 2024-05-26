#import <Foundation/Foundation.h>
#import <HBLog.h>
#import "Common.h"
#import "RunningBoard.h"
#import "SettingsKeys.h"
#import <notify.h>

#import <xpc/xpc.h>
typedef NSObject<OS_xpc_object> *xpc_object_t;

static BOOL running;
static BOOL excludeOtherApps;
static BOOL isWhitelist;
static NSSet *listedApps;

static void loadPreferences() {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kPrefPath];
    if (dict) {
        NSNumber *current = dict[kExcludeOtherApps];
        excludeOtherApps = current && [current boolValue];

        current = dict[kIsWhitelist];
        isWhitelist = !current || [current boolValue];

        NSArray *listedAppsList = dict[kListedApps] ? : @[];
        listedApps = [NSSet setWithArray:listedAppsList];
    }
}

static BOOL inline shouldExcludeAppForIdentity(RBSProcessIdentity *identity) {
    if (!excludeOtherApps || !identity.embeddedApplication ||
        [identity.embeddedApplicationIdentifier isEqualToString:@"com.apple.Spotlight"]) {
        return NO;
    }

    if (!isWhitelist ^ [listedApps containsObject:identity.embeddedApplicationIdentifier]) {
        return YES;
    }
    return NO;
}

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

%end


/* Exclude the now playing process from being killed.
   If excludeOtherApps is set, exclude all/some embedded
   applications from termination, depending on settings. */
%hook RBProcess

- (BOOL)terminateWithContext:(RBSTerminateContext *)context {
    if (!running) {
        return %orig;
    }

    BOOL validReason = [context.explanation isEqualToString:@"/usr/libexec/backboardd respawn"] ||
                       [context.explanation isEqualToString:@"SBRestartManager"] ||
                       context.exceptionCode == kParentProcessDied ||
                       context.exceptionCode == kSpringBoardLegacyClearTheBoard;
    if (!validReason) {
        return %orig;
    }

    RBSProcessHandle *handle = self.handle;
    BOOL isPartying = handle.partying || (self.hostProcess && self.hostProcess.handle.partying);
    if (isPartying || shouldExcludeAppForIdentity(self.identity)) {
        handle.immortal = YES;
        return YES;
    }

    return %orig;
}

%end


/* Used to store properties within RunningBoard. */
%hook RBSProcessHandle

static RBSProcessHandle *initProcessHandle(RBSProcessHandle *self) {
    // These have to be initialized to NO for some reason
    self.partying = NO;
    self.immortal = NO;

    return self;
}

static RBSProcessHandle *initProcessHandleWithCoder(RBSProcessHandle *self, BSXPCCoder *coder) {
    self.partying = [coder decodeBoolForKey:kPartyingProcess];
    self.immortal = [coder decodeBoolForKey:kImmortalProcess];

    return self;
}

static void encodeProcessHandle(RBSProcessHandle *self, BSXPCCoder *coder) {
    [coder encodeBool:self.partying forKey:kPartyingProcess];
    [coder encodeBool:self.immortal forKey:kImmortalProcess];
}

%property (nonatomic, assign) BOOL partying;
%property (nonatomic, assign) BOOL immortal;

%group RBSProcessHandle_iOS13
- (id)initWithInstance:(id)instance
              lifePort:(id)lifePort
            bundleData:(id)bundleData
              reported:(BOOL)reported {
    return initProcessHandle(%orig);
}

- (id)initWithBSXPCCoder:(BSXPCCoder *)coder {
    return initProcessHandleWithCoder(%orig, coder);
}

- (void)encodeWithBSXPCCoder:(BSXPCCoder *)coder {
    %orig;
    encodeProcessHandle(self, coder);
}
%end

%group RBSProcessHandle_iOS14
- (id)initWithInstance:(id)instance
            auditToken:(id)auditToken
            bundleData:(id)bundleData
           manageFlags:(unsigned char)manageFlags
beforeTranslocationBundlePath:(id)beforeTranslocationBundlePath {
    return initProcessHandle(%orig);
}

- (id)initWithRBSXPCCoder:(BSXPCCoder *)coder {
    return initProcessHandleWithCoder(%orig, coder);
}

- (void)encodeWithRBSXPCCoder:(BSXPCCoder *)coder {
    %orig;
    encodeProcessHandle(self, coder);
}
%end

%end




/* Used to transfer information to SpringBoard as binary data.
   Why SpringBoard uses the RBSProcessState and not RunningBoard is
   because updated states are always sent to SpringBoard whereas the
   process handle is not. The required information doesn't get
   propagated if using the latter. */
%hook RBSProcessState

static void encodeProcessStateWithCoder(RBSProcessState *self, BSXPCCoder *coder) {
    RBSProcessHandle *handle = self.process;
    [coder encodeBool:handle.partying forKey:kPartyingProcess];
    [coder encodeBool:handle.immortal forKey:kImmortalProcess];
}

%group RBSProcessState_iOS13
- (void)encodeWithBSXPCCoder:(BSXPCCoder *)coder {
    %orig;
    encodeProcessStateWithCoder(self, coder);
}
%end

%group RBSProcessState_iOS14
- (void)encodeWithRBSXPCCoder:(BSXPCCoder *)coder {
    %orig;
    encodeProcessStateWithCoder(self, coder);
}
%end

%end


// Returns YES if the message is handled.
static BOOL handleMessage(RBConnectionClient *self, xpc_object_t xpc_dictionary) {
    const char *selName = xpc_dictionary_get_string(xpc_dictionary, "rbs_selector");
    if (selName != NULL) {
        if (strcmp(selName, sel_getName(NOW_PLAYING_APP_CHANGED_SELECTOR)) == 0) {
            const char *identifier = xpc_dictionary_get_string(xpc_dictionary, "rbs_argument_0");
            NSString *bundleID = identifier ? [NSString stringWithUTF8String:identifier] : nil;
            RBProcessManager *processManager = MSHookIvar<RBProcessManager *>(self, "_processManager");
            [processManager nowPlayingAppChanged:bundleID];
            return YES;
        }
    }
    return NO;
}

/* Messages for change of media app are sent using the stock
   iOS XPC communication channel. Controlling the running state
   from SpringBoard is also carried out through these messages. */
%group iOS13
%hook RBConnectionClient

- (void)handleMessage:(xpc_object_t)xpc_dictionary {
    if (handleMessage(self, xpc_dictionary)) {
        return;
    }
    %orig;
}

%end
%end

%group iOS14
%hookf(void, handleMessage, RBConnectionClient *self, SEL _cmd, xpc_object_t xpc_dictionary) {
    if (handleMessage(self, xpc_dictionary)) {
        return;
    }
    %orig;
}
%end


%ctor {
    if (%c(RBProcessManager) == nil || !isEnabled())
        return;

    int _;
    notify_register_dispatch(kSettingsChanged,
        &_,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
        ^(int _) {
            loadPreferences();
        }
    );
    loadPreferences();

    %init;
    if ([%c(RBConnectionClient) instancesRespondToSelector:@selector(handleMessage:)]) {
        %init(iOS13);
    } else {
        %init(iOS14, handleMessage = MSFindSymbol(NULL, "-[RBConnectionClient handleMessage:]"));
    }

    if ([%c(RBSProcessHandle) instancesRespondToSelector:@selector(encodeWithBSXPCCoder:)]) {
        %init(RBSProcessHandle_iOS13);
        %init(RBSProcessState_iOS13);
    } else {
        %init(RBSProcessHandle_iOS14);
        %init(RBSProcessState_iOS14);
    }
}
