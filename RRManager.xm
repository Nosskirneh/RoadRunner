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

@implementation RRManager

- (void)setup {
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
                excludeAllApps = !allApps || [allApps boolValue];
            }

            /* Go through all existing processes.
               Reattach any media playing process, reattach any extension
               (WebKit) process to its host process and kill any immortal
               app not playing media anymore. */
            NSDictionary *states = [self getAllProcessStates];
            for (RBSProcessIdentity *identity in states) {
                RBSProcessState *state = states[identity];
                RBSProcessHandle *process = state.process;

                // Don't process deamons
                if (!identity.embeddedApplication && !process.hostProcess.identity.embeddedApplication)
                    continue;

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
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            FBApplicationProcess *process = getProcessForPID(pid);
                            SBApplication *app = [self reattachImmortalProcess:process
                                                                      bundleID:identity.embeddedApplicationIdentifier
                                                                           PID:pid];

                            [self restoreMediaProcess:process app:app PID:pid];
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
                        [self killImmortalPID:pid];
                    }
                } else if (process.hostProcess && (process.hostProcess.currentState.immortal ||
                                                   process.hostProcess.currentState.partying)) {
                    /* Reconnect extension processes to their host processes
                       (for example WebKit playing inside of MobileSafari). */
                    [self reattachExtensionProcess:pid];
                }
            }

            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(nowPlayingAppChanged:)
                                                         name:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                                                       object:nil];
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

    FBProcessState *processState = process.state;
    [processState setVisibility:VisibilityBackground];
    [processState setTaskState:TaskStateRunning];

    SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:bundleID];
    [app _processWillLaunch:process];
    [app _processDidLaunch:process];

    SBApplicationProcessState *sbProcessSate = [[%c(SBApplicationProcessState) alloc] _initWithProcess:process
                                                                                         stateSnapshot:processState];
    [app _setInternalProcessState:sbProcessSate];

    SpringBoard *springBoard = (SpringBoard *)[UIApplication sharedApplication];
    [springBoard launchApplicationWithIdentifier:bundleID suspended:YES];

    FBSceneManager *sceneManager = [%c(FBSceneManager) sharedInstance];
    FBScene *scene = [sceneManager sceneWithIdentifier:[app _baseSceneIdentifier]];

    FBSMutableSceneSettings *sceneSettings = [scene mutableSettings];
    sceneSettings.foreground = YES;
    sceneSettings.backgrounded = NO;
    [sceneManager _applyMutableSettings:sceneSettings
                                toScene:scene
                  withTransitionContext:nil
                             completion:nil];

    FBSMutableSceneSettings *newSceneSettings = [scene mutableSettings];
    newSceneSettings.foreground = NO;
    newSceneSettings.backgrounded = YES;
    [sceneManager _applyMutableSettings:newSceneSettings
                                toScene:scene
                  withTransitionContext:nil
                             completion:nil];

    return app;
}

/* Kills a process as if the user quit it from the app switcher. */
- (void)killImmortalPID:(int)pid {
    FBApplicationProcess *process = getProcessForPID(pid);
    [process killForReason:kKilledByAppSwitcher andReport:NO withDescription:nil];
}

- (NSDictionary *)getAllProcessStates {
    RBSConnection *connection = [%c(RBSConnection) sharedInstance];
    return [MSHookIvar<NSDictionary *>(connection, "_stateByIdentity") copy];
}

@end
