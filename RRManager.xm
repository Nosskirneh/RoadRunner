#import "RRManager.h"
#import "Common.h"
#import <MediaRemote/MediaRemote.h>
#import <notify.h>
#import "FrontBoard.h"
#import "SpringBoard.h"

#define kSBSpringBoardDidLaunchNotification "SBSpringBoardDidLaunchNotification"
#define kSBMediaNowPlayingAppChangedNotification @"SBMediaNowPlayingAppChangedNotification"
#define kKilledByAppSwitcher 1


static inline FBApplicationProcess *getProcessForPID(int pid) {
    return [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:pid];
}

@implementation RRManager {
    RRCenter *_center_in;
    RRCenter *_center_out;
}

- (void)setup {
    int token;
    notify_register_dispatch(kSBSpringBoardDidLaunchNotification,
        &token,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
        ^(int _) {
            notify_cancel(token);

            /* Go through all existing processes.
               Reattach any media playing process, reattach any extension
               (WebKit) process to its host process and kill any immortal
               app not playing media anymore. */
            NSDictionary *states = [self getAllProcessStates];
            for (RBSProcessIdentity *identity in states) {
                RBSProcessState *state = states[identity];
                RBSProcessHandle *process = state.process;
                int pid = process.pid;

                if (state.immortal) {

                    if (state.partying) {
                        dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC);
                        dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{
                            NSString *bundleID = identity.embeddedApplicationIdentifier;
                            SBApplication *app = [self reattachImmortalProcess:bundleID
                                                                           PID:pid];

                            [self restoreMediaApp:app PID:pid];
                            _immortalPartyingBundleID = bundleID;
                        });
                    } else if (process.hostProcess && process.hostProcess.currentState.partying) {
                        [self reattachExtensionProcess:pid];
                    } else {
                        // Kill any non-partying apps
                        [self killImmortalPID:pid];
                    }
                } else if (process.hostProcess && process.hostProcess.currentState.immortal) {
                    /* Reconnect extension processes to their host processes
                       (for example WebKit playing inside of MobileSafari). */
                    [self reattachExtensionProcess:pid];
                }
            }

            /* Setup communication channels to RunningBoard and
               subscribe to now playing app changes. */
            _center_in = [RRCenter centerNamed:KP_IDENTIFIER_SB];
            _center_out = [RRCenter centerNamed:KP_IDENTIFIER_RB];

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

    [_center_out callExternalMethod:NOW_PLAYING_APP_CHANGED_SELECTOR
                      withArguments:nil
                         completion:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)nowPlayingAppChanged:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSNumber *pid = info[(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
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

    NSDictionary *data;
    if (bundleID) {
        data = @{
            kApp : bundleID
        };
    }

    [_center_out callExternalMethod:NOW_PLAYING_APP_CHANGED_SELECTOR
                      withArguments:data
                         completion:nil];
}

- (void)restoreMediaApp:(SBApplication *)app PID:(int)pid {
    FBApplicationProcess *process = getProcessForPID(pid);
    [process setNowPlayingWithAudio:YES];

    dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC);
    dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{
        // Restore MediaRemote
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center postNotificationName:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                              object:nil
                            userInfo:@{(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey: @(pid)}];
        [center postNotificationName:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification
                              object:nil
                            userInfo:@{(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey: @(YES)}];

        MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
            [center postNotificationName:(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDidChangeNotification
                                  object:nil
                                userInfo:(__bridge NSDictionary *)info];
        });

        // Restore SBMediaController
        SBMediaController *mediaController = [%c(SBMediaController) sharedInstance];
        MSHookIvar<SBApplication *>(mediaController, "_lastNowPlayingApplication") = app;
        mediaController.nowPlayingProcessPID = pid;

        [center postNotificationName:kSBMediaNowPlayingAppChangedNotification
                              object:mediaController];
    });
}

/* Reattach a process with a specific bundleID and PID. */
- (SBApplication *)reattachImmortalProcess:(NSString *)bundleID PID:(int)pid {
    FBApplicationProcess *process = getProcessForPID(pid);
    if (!process)
        return nil;

    SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:bundleID];
    [app _processWillLaunch:process];
    [app _processDidLaunch:process];

    FBProcessState *processState = [[%c(FBProcessState) alloc] initWithPid:pid];
    [processState setVisibility:Background];
    [processState setTaskState:Background];

    SBApplicationProcessState *sbProcessSate = [[%c(SBApplicationProcessState) alloc] _initWithProcess:process
                                                                                         stateSnapshot:processState];
    [app _setInternalProcessState:sbProcessSate];


    [processState setVisibility:Foreground];
    sbProcessSate = [[%c(SBApplicationProcessState) alloc] _initWithProcess:process
                                                              stateSnapshot:processState];
    [app _setInternalProcessState:sbProcessSate];

    SpringBoard *springBoard = (SpringBoard *)[UIApplication sharedApplication];
    [springBoard launchApplicationWithIdentifier:bundleID suspended:YES];

    dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC);
    dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{
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
    });

    return app;
}

/* Kills a process as if the user quit it from the app switcher. */
- (void)killImmortalPID:(int)pid {
    FBApplicationProcess *process = getProcessForPID(pid);
    [process killForReason:kKilledByAppSwitcher andReport:NO withDescription:nil];

    NSString *bundleID = process.bundleIdentifier;
    if ([bundleID isEqualToString:_immortalPartyingBundleID]) {
        _immortalPartyingBundleID = nil;
    }
}


- (NSDictionary *)getAllProcessStates {
    RBSConnection *connection = [%c(RBSConnection) sharedInstance];
    return [MSHookIvar<NSDictionary *>(connection, "_stateByIdentity") copy];
}

@end
