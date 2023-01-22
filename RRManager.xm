#import "RRManager.h"
#import <UIKit/UIKit.h>
#import <HBLog.h>
#import "Common.h"
#import <MediaRemote/MediaRemote.h>
#import <notify.h>
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "SettingsKeys.h"
#import "DRMValidateOptions.mm"
#import <ptrauth-helpers.h>

#define kSBSpringBoardDidLaunchNotification "SBSpringBoardDidLaunchNotification"
#define kSBMediaNowPlayingAppChangedNotification @"SBMediaNowPlayingAppChangedNotification"
#define kKilledByAppSwitcher 1


static inline FBApplicationProcess *getProcessForPID(int pid) {
    return [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:pid];
}

static inline void sendMessageForMethodAndArguments(SEL method, NSArray *arguments) {
    RBSXPCMessage *message = nil;
    Class xpcMessageClass = %c(RBSXPCMessage);
    SEL messageForMethodSel = @selector(messageForMethod:arguments:);
    if ([xpcMessageClass respondsToSelector:messageForMethodSel]) {
        message = [xpcMessageClass messageForMethod:method arguments:arguments];
    } else {
        RBSXPCMessage *(* messageForMethodAndArguments)(Class, SEL, SEL, NSArray *) =
            (RBSXPCMessage *(*)(Class, SEL, SEL, NSArray *))make_sym_callable(
                MSFindSymbol(NULL, "+[RBSXPCMessage messageForMethod:arguments:]"));
        message = messageForMethodAndArguments(xpcMessageClass, messageForMethodSel, method, arguments);
    }

    RBSConnection *rbsConnection = [%c(RBSConnection) sharedInstance];
    id connection = [rbsConnection respondsToSelector:@selector(_connection)] ?
        [rbsConnection _connection] : MSHookIvar<id>(rbsConnection, "_connection");
    SEL invokeOnConnectionSel = @selector(invokeOnConnection:withReturnClass:error:);
    if ([message respondsToSelector:invokeOnConnectionSel]) {
        [message invokeOnConnection:connection
                    withReturnClass:nil
                              error:nil];
    } else {
        RBSXPCMessage *(* invokeOnConnection)(id, SEL, id, Class, NSError **) =
            (RBSXPCMessage *(*)(id, SEL, id, Class, NSError **))make_sym_callable(
                MSFindSymbol(NULL, "-[RBSXPCMessage invokeOnConnection:withReturnClass:error:]"));
        invokeOnConnection(message, invokeOnConnectionSel, connection, nil, nil);
    }
}

__attribute__((always_inline, visibility("hidden")))
static inline void setRunning(BOOL running) {
    sendMessageForMethodAndArguments(SET_RUNNING, @[@(running)]);
}

@implementation RRManager

extern IInitFunctions *initFunctions;

- (id)init {
    setRunning(NO);

    if (fromUntrustedSource(package$bs())) {
        initFunctions->pirated();
        return nil;
    }
    self = [super init];

    /* License check – if no license found, present message.
       If no valid license found, do not init. */
    switch (check_lic(licensePath$bs(), package$bs())) {
        case CheckNoLicense:
            initFunctions->welcome();
            return self;
        case CheckInvalidTrialLicense:
            initFunctions->trial();
            return self;
        case CheckValidTrialLicense:
            initFunctions->trial();
            break;
        case CheckValidLicense:
            break;
        case CheckInvalidLicense:
        case CheckUDIDsDoNotMatch:
        default:
            // In case the user is running a trial license and then removes it
            [self setTrialEnded];
            return self;
    }
    // ---
    initFunctions->normal();
    setRunning(YES);

    int token;
    notify_register_dispatch(kSBSpringBoardDidLaunchNotification,
        &token,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
        ^(int _) {
            notify_cancel(token);

            // After about 2 seconds, the daemons have been added to the process states
            // allowing us to connect to the TextInput daemon.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSDictionary *states = [self getAllProcessStates];
                RBSProcessIdentity *processIdentity = [%c(RBSProcessIdentity) identityForDaemonJobLabel:@"com.apple.TextInput.kbd"];
                RBSProcessState *state = states[processIdentity];
                RBSProcessHandle *process = state.process;
                [self reattachProcessHandleForPID:process.pid];
                notify_post(kRoadRunnerSpringBoardRestarted);
            });

            // Not having a delay here makes the apps not appear in the app switcher
            // 0.25 was not enough
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l), ^{
                BOOL excludeOtherApps = NO;
                NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kPrefPath];
                if (dict) {
                    NSNumber *otherApps = dict[kExcludeOtherApps];
                    excludeOtherApps = otherApps && [otherApps boolValue];
                }

                /* Go through all existing processes.
                   Reattach any media playing process, reattach any extension
                   (WebKit) process to its host process and kill any immortal
                   app not playing media anymore. */
                NSDictionary *states = [self getAllProcessStates];
                for (RBSProcessIdentity *identity in states) {
                    RBSProcessState *state = states[identity];
                    RBSProcessHandle *process = state.process;

                    // Don't process daemons
                    if (!identity.embeddedApplication && !process.hostProcess.identity.embeddedApplication) {
                        continue;
                    }
                    /* This fixes a rare case when the properties are cleared.
                       The solution is to rely on SpringBoard to propagate the
                       party information to RunningBoard. That's why we can use
                       the party property regardless.

                       This happens when installing the tweak and only killing
                       SpringBoard. For some reason, RunningBoard seems to lose
                       information when this happens. However, when simply executing
                       `killall SpringBoard`, this is not happening. */
                    if (!state.immortal && (state.partying || excludeOtherApps)) {
                        state.immortal = YES;
                    }

                    int pid = process.pid;
                    if (state.immortal) {
                        if (state.partying) {
                            /* We need to wait a small delay, otherwise NextUp might show before
                               the updated LS media widget's preferredContentSize has been used.
                               This could probably be solved better but a small delay isn't noticeable.
                               0.25 was fine for NextUp, but 0.5 was needed for apps to be killable by
                               the app switcher. */
                            dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC);
                            dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{
                                NSString *bundleID = identity.embeddedApplicationIdentifier;
                                FBApplicationProcess *process = getProcessForPID(pid);

                                SBApplication *app = [self reattachImmortalProcess:process
                                                                          bundleID:bundleID
                                                                               PID:pid];

                                [self restoreMediaProcess:process app:app PID:pid];
                                _immortalPartyingBundleID = bundleID;
                            });
                        } else if (process.hostProcess && process.hostProcess.currentState.partying) {
                            [self reattachProcessHandleForPID:pid];
                        } else if (excludeOtherApps) {
                            dispatch_sync(dispatch_get_main_queue(), ^{
                                FBApplicationProcess *process = getProcessForPID(pid);
                                [self reattachImmortalProcess:process
                                                     bundleID:identity.embeddedApplicationIdentifier
                                                          PID:pid];
                            });
                        } else {
                            // Kill any non-partying apps
                            [self killApplicationWithPID:pid];
                        }
                    } else if (process.hostProcess && (process.hostProcess.currentState.immortal ||
                                                       process.hostProcess.currentState.partying)) {
                        /* Reconnect extension processes to their host processes
                           (for example WebKit playing inside of MobileSafari). */
                        [self reattachProcessHandleForPID:pid];
                    }
                }
            });

            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(nowPlayingAppChanged:)
                                                         name:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                                                       object:nil];
        }
    );

    return self;
}

- (void)reattachProcessHandleForPID:(int)pid {
    BSProcessHandle *handle = [%c(BSProcessHandle) processHandleForPID:pid];
    [[%c(FBProcessManager) sharedInstance] registerProcessForHandle:handle];
}

/* Unsubscribe to notifications and tell RunningBoard to
   mark the any current now playing process as not playing. */
- (void)setTrialEnded {
    _trialEnded = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [self sendNowPlayingPIDInfo:nil];
    setRunning(NO);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleDaemonDidStart {
    switch (check_lic(licensePath$bs(), package$bs())) {
        case CheckValidLicense:
        case CheckValidTrialLicense:
            setRunning(YES);
            break;
        default:
            break;
    }

    MRMediaRemoteGetNowPlayingApplicationPID(dispatch_get_main_queue(), ^(int pid) {
        if (pid > 0)
            [self sendNowPlayingPIDInfo:@(pid)];
    });
}

- (void)nowPlayingAppChanged:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSNumber *pid = info[(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    [self sendNowPlayingPIDInfo:pid];
}

- (void)sendNowPlayingPIDInfo:(NSNumber *)pid {
    NSString *bundleID;

    if (pid) {
        int p = [pid intValue];
        RBSProcessHandle *process = [%c(RBSProcessHandle) handleForKey:p fetchIfNeeded:YES];
        if (process.hostProcess)
            process = process.hostProcess;

        bundleID = process.identity.embeddedApplicationIdentifier;
    }

    sendMessageForMethodAndArguments(NOW_PLAYING_APP_CHANGED_SELECTOR, bundleID ? @[bundleID] : nil);
}

- (void)restoreMediaProcess:(FBApplicationProcess *)process app:(SBApplication *)app PID:(int)pid {
    [process setNowPlayingWithAudio:YES];
    [app setPlayingAudio:YES];

    // Restore MediaRemote
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center postNotificationName:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                          object:nil
                        userInfo:@{(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey: @(pid)}];

    [center postNotificationName:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification
                          object:nil
                        userInfo:@{(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey: @(YES)}];

    // Restore SBMediaController
    SBMediaController *mediaController = [%c(SBMediaController) sharedInstance];
    MSHookIvar<SBApplication *>(mediaController, "_lastNowPlayingApplication") = app;
    mediaController.nowPlayingProcessPID = pid;

    [center postNotificationName:kSBMediaNowPlayingAppChangedNotification
                          object:mediaController];

    // Force Flow to update the information
    notify_post(kRoadRunnerRestoredMediaProcess);
}

/* Reattach a process with a specific bundleID and PID. */
- (SBApplication *)reattachImmortalProcess:(FBApplicationProcess *)process
                                  bundleID:(NSString *)bundleID
                                       PID:(int)pid {
    if (!process)
        return nil;

    SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:bundleID];
    [app _processWillLaunch:process];
    [app _processDidLaunch:process];

    FBProcessState *processState = process.state;
    [processState setVisibility:VisibilityBackground];
    [processState setTaskState:TaskStateRunning];

    SBApplicationProcessState *sbProcessSate = [[%c(SBApplicationProcessState) alloc] _initWithProcess:process
                                                                                         stateSnapshot:processState];
    [app _setInternalProcessState:sbProcessSate];

    return app;
}

- (void)killApplicationWithPID:(int)pid {
    FBApplicationProcess *process = getProcessForPID(pid);
    [process killForReason:kKilledByAppSwitcher andReport:NO withDescription:nil];
}

- (NSDictionary *)getAllProcessStates {
    RBSConnection *connection = [%c(RBSConnection) sharedInstance];
    return [MSHookIvar<NSDictionary *>(connection, "_stateByIdentity") copy];
}

@end
