#import "RRManager.h"
#import "Common.h"
#import <MediaRemote/MediaRemote.h>
#import <notify.h>
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "SettingsKeys.h"

#define kSBSpringBoardDidLaunchNotification "SBSpringBoardDidLaunchNotification"
#define kSBMediaNowPlayingAppChangedNotification @"SBMediaNowPlayingAppChangedNotification"
#define kKilledByAppSwitcher 1


static inline FBApplicationProcess *getProcessForPID(int pid) {
    return [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:pid];
}

__attribute__((always_inline, visibility("hidden")))
static inline void setRunning(BOOL running) {
    RBSXPCMessage *message = [%c(RBSXPCMessage) messageForMethod:SET_RUNNING
                                                       arguments:@[@(running)]];
    [message invokeOnConnection:[[%c(RBSConnection) sharedInstance] _connection]
                withReturnClass:nil
                          error:nil];
}

@implementation RRManager

- (void)setup {
    setRunning(YES);

    int token;
    notify_register_dispatch(kSBSpringBoardDidLaunchNotification,
        &token,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
        ^(int _) {
            notify_cancel(token);

            BOOL excludeAllApps = NO;
            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kPrefPath];
            if (dict) {
                NSNumber *allApps = dict[kExcludeAllApps];
                excludeAllApps = allApps && [allApps boolValue];
            }

            /* Go through all existing processes.
               Reattach any media playing process, reattach any extension
               (WebKit) process to its host process and kill any immortal
               app not playing media anymore. */
            [self enumerateAllApplicationProcessesWithBlock:^(RBSProcessIdentity *identity,
                                                              RBSProcessState *state,
                                                              RBSProcessHandle *process) {
                /* This fixes a rare case when the properties are cleared.
                   The solution is to rely on SpringBoard to propagate the
                   party information to RunningBoard. That's why we can use
                   the party property regardless.

                   This happens when installing the tweak and only killing
                   SpringBoard. For some reason, RunningBoard seems to lose
                   information when this happens. However, when simply executing
                   `killall SpringBoard`, this is not happening. */
                if (!state.immortal && (state.partying || excludeAllApps)) {
                    state.immortal = YES;
                }

                int pid = process.pid;
                if (state.immortal) {
                    if (state.partying) {
                        /* We need to wait a small delay, otherwise NextUp might show before
                           the updated LS media widget's preferredContentSize has been used.
                           This could probably be solved better but a small delay isn't noticeable. */
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
                        [self reattachExtensionProcess:pid];
                    } else if (excludeAllApps) {
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
                    [self reattachExtensionProcess:pid];
                }
            }];

            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(nowPlayingAppChanged:)
                                                         name:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                                                       object:nil];
        }
    );

    notify_register_dispatch(kKillAllApps,
        &token,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
        ^(int _) {
            [self enumerateAllApplicationProcessesWithBlock:^(RBSProcessIdentity *identity,
                                                              RBSProcessState *state,
                                                              RBSProcessHandle *process) {
                [self killApplicationWithPID:process.pid];
            }];
        }
    );
}

- (void)reattachExtensionProcess:(int)pid {
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
        FBApplicationProcess *app = [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:p];
        if (app) {
            bundleID = app.bundleIdentifier;
        } else {
            FBProcess *process = [[%c(FBProcessManager) sharedInstance] processForPID:p];
            if ([process isKindOfClass:%c(FBExtensionProcess)]) {
                bundleID = ((FBExtensionProcess *)process).hostProcess.bundleIdentifier;
            }
        }
    }

    RBSXPCMessage *message = [%c(RBSXPCMessage) messageForMethod:NOW_PLAYING_APP_CHANGED_SELECTOR
                                                       arguments:bundleID ? @[bundleID] : nil];
    [message invokeOnConnection:[[%c(RBSConnection) sharedInstance] _connection]
                withReturnClass:nil
                          error:nil];
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
    notify_post("se.nosskirneh.roadrunner.restored-media-process");
}

/* Use this if users start to reach out saying tweaks depending
   on the media artwork doesn't work right away, such as CCArtwork.
   This has to be issued at least 1.5 after SB loaded as the
   MediaRemote callbacks otherwise don't fire. */
// - (void)forceMediaUpdate {
//     MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(BOOL isPlaying) {
//         if (isPlaying) {
//             // This causes a short stutter when listening to Music.app
//             // for example and with other clients the delay isn't long
//             // enough for it to be a complete stop, but the volume is ducking.
//             MRMediaRemoteSendCommand(kMRPause, nil);
//             MRMediaRemoteSendCommand(kMRPlay, nil);
//         } else {
//             MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
//                 NSNumber *elapsedTime = ((__bridge NSDictionary *)info)[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoElapsedTime];
//                 if (elapsedTime) {
//                     MRMediaRemoteSetElapsedTime([elapsedTime floatValue]);
//                 }
//             });
//         }
//     });
// }

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

/* Kills a process as if the user quit it from the app switcher. */
- (void)killApplicationWithPID:(int)pid {
    FBApplicationProcess *process = getProcessForPID(pid);
    [process killForReason:kKilledByAppSwitcher andReport:NO withDescription:nil];
}

- (NSDictionary *)getAllProcessStates {
    RBSConnection *connection = [%c(RBSConnection) sharedInstance];
    return [MSHookIvar<NSDictionary *>(connection, "_stateByIdentity") copy];
}

- (void)enumerateAllApplicationProcessesWithBlock:(void(^)(RBSProcessIdentity *,
                                                           RBSProcessState *,
                                                           RBSProcessHandle *))block {
    NSDictionary *states = [self getAllProcessStates];
    for (RBSProcessIdentity *identity in states) {
        RBSProcessState *state = states[identity];
        RBSProcessHandle *process = state.process;

        // Don't process daemons
        if (!identity.embeddedApplication && !process.hostProcess.identity.embeddedApplication)
            continue;

        block(identity, state, process);
    }
}

@end
