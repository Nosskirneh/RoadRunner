#import "KPManager.h"
#import "Common.h"
#import <MediaRemote/MediaRemote.h>
#import <notify.h>
#import "FrontBoard.h"
#import "SpringBoard.h"

#define kSBSpringBoardDidLaunchNotification "SBSpringBoardDidLaunchNotification"
#define kKilledByAppSwitcher 1

FBApplicationProcess *getProcessForPID(int pid) {
    return [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:pid];
}

@implementation KPManager {
    KPCenter *_center_in;
    KPCenter *_center_out;
    NSString *_nowPlayingBundleID;
}

- (id)init {
    self = [super init];

    int token;
    notify_register_dispatch(kSBSpringBoardDidLaunchNotification,
        &token,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
        ^(int _) {
            notify_cancel(token);

            _center_in = [KPCenter centerNamed:KP_IDENTIFIER_SB];
            [_center_in addTarget:self action:PREVENTED_APP_SHUTDOWN_PID_SELECTOR];

            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(nowPlayingAppChanged:)
                                                         name:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                                                       object:nil];

            _center_out = [KPCenter centerNamed:KP_IDENTIFIER_RB];
            [_center_out callExternalMethod:SB_LOADED
                              withArguments:nil
                                 completion:nil];
        }
    );

    return self;
}

- (void)nowPlayingAppChanged:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSNumber *pid = info[(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    NSDictionary *data;

    if (pid) {
        int p = [pid intValue];
        FBApplicationProcess *app = [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:p];
        _nowPlayingBundleID = app.bundleIdentifier;
        data = @{
            kApp : _nowPlayingBundleID
        };
    } else {
        _nowPlayingBundleID = nil;
    }

    [_center_out callExternalMethod:NOW_PLAYING_APP_CHANGED_SELECTOR
                      withArguments:data
                         completion:nil];
}

/* This is called from RunningBoard when SpringBoard loads
   if at least one app has been immortal. */
- (void)preventedAppShutdown:(NSDictionary *)data {
    _immortalBundleID = data[kBundleID];
    _immortalPID = [data[kPID] intValue];
    [self reattachImmortalProcess];

    // SBMediaController *mediaController = [%c(SBMediaController) sharedInstance];
    // id aa = mediaController.nowPlayingApplication;
    // int pid = mediaController.nowPlayingProcessPID;
    // log(@"sb loaded: %@, pid: %d", aa, pid);
}

/* Reattach a process with a specific bundleID and pid */
- (void)reattachImmortalProcess {
    FBApplicationProcess *process = getProcessForPID(_immortalPID);
    if (!process)
        return;

    [process setNowPlayingWithAudio:YES];

    SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:_immortalBundleID];
    [app _processWillLaunch:process];
    [app _processDidLaunch:process];

    FBProcessState *processState = [[%c(FBProcessState) alloc] initWithPid:_immortalPID];
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
    [springBoard launchApplicationWithIdentifier:_immortalBundleID suspended:YES];

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
}

- (void)killImmortalApp {
    FBApplicationProcess *process = getProcessForPID(_immortalPID);
    [process killForReason:kKilledByAppSwitcher andReport:NO withDescription:nil];

    _immortalBundleID = nil;
    _immortalPID = 0;
}

@end
