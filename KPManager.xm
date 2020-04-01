#import "KPManager.h"
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

@implementation KPManager {
    KPCenter *_center_in;
    KPCenter *_center_out;
    NSMutableSet *_immortalApps;
}

- (id)init {
    self = [super init];

    int token;
    notify_register_dispatch(kSBSpringBoardDidLaunchNotification,
        &token,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
        ^(int _) {
            notify_cancel(token);

            _immortalApps = [NSMutableSet new];

            RBSConnection *connection = [%c(RBSConnection) sharedInstance];
            NSMutableDictionary *states = MSHookIvar<NSMutableDictionary *>(connection, "_stateByIdentity");
            for (RBSProcessIdentity *identity in states) {
                RBSProcessState *state = states[identity];

                if (state.immortal) {
                    NSString *bundleID = identity.embeddedApplicationIdentifier;
                    int pid = state.process.pid;

                    [_immortalApps addObject:bundleID];

                    dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC);
                    dispatch_after(dispatchTime, dispatch_get_main_queue(), ^{
                        SBApplication *app = [self reattachImmortalProcess:bundleID
                                                                       PID:pid];

                        if (state.partying) {
                            [self restoreMediaApp:app PID:pid];
                            _immortalPartyingBundleID = bundleID;
                        }
                    });
                }
            }

            _center_in = [KPCenter centerNamed:KP_IDENTIFIER_SB];
            [_center_in addTarget:self action:PREVENTED_APP_SHUTDOWN_PID_SELECTOR];

            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(nowPlayingAppChanged:)
                                                         name:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                                                       object:nil];

            _center_out = [KPCenter centerNamed:KP_IDENTIFIER_RB];
        }
    );

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)nowPlayingAppChanged:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSNumber *pid = info[(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    NSDictionary *data;

    if (pid) {
        int p = [pid intValue];
        FBApplicationProcess *app = [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:p];
        data = @{
            kApp : app.bundleIdentifier
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


        // Restore SBMediaController
        SBMediaController *mediaController = [%c(SBMediaController) sharedInstance];
        MSHookIvar<SBApplication *>(mediaController, "_lastNowPlayingApplication") = app;
        mediaController.nowPlayingProcessPID = pid;

        [center postNotificationName:kSBMediaNowPlayingAppChangedNotification
                              object:mediaController];
    });
}

/* Reattach a process with a specific bundleID and pid */
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

- (void)killImmortalPID:(int)pid {
    FBApplicationProcess *process = getProcessForPID(pid);
    [process killForReason:kKilledByAppSwitcher andReport:NO withDescription:nil];

    NSString *bundleID = process.bundleIdentifier;
    [_immortalApps removeObject:bundleID];
    if ([bundleID isEqualToString:_immortalPartyingBundleID]) {
        _immortalPartyingBundleID = nil;
    }
}

@end