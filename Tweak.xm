#import <MediaRemote/MediaRemote.h>
#import "Common.h"
#import "KPCenter.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import <SpringBoard/SBMediaController.h>
#import <notify.h>


#define kSBSpringBoardDidLaunchNotification "SBSpringBoardDidLaunchNotification"
#define kApplicationStateForegroundRunning 4
#define kKilledByAppSwitcher 1

%hook SpringBoard

int __pid;

%property (nonatomic, retain) KPCenter *kp_center_in;
%property (nonatomic, retain) KPCenter *kp_center_out;

FBApplicationProcess *getProcessForPID(int p) {
    return [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:p];
}

- (id)init {
    self = %orig;

    int token;
    notify_register_dispatch(kSBSpringBoardDidLaunchNotification,
        &token,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0l),
        ^(int _) {
            self.kp_center_in = [KPCenter centerNamed:KP_IDENTIFIER_SB];
            [self.kp_center_in addTarget:self action:PREVENTED_APP_SHUTDOWN_PID_SELECTOR];

            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(appDidChange:)
                                                         name:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationDidChangeNotification
                                                       object:nil];

            self.kp_center_out = [KPCenter centerNamed:KP_IDENTIFIER_RB];
            [self.kp_center_out callExternalMethod:SB_LOADED
                                     withArguments:nil
                                        completion:nil];
        }
    );

    return self;
}

%new
- (void)appDidChange:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    NSNumber *pid = info[(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey];
    NSDictionary *data = nil;

    if (pid) {
        int p = [pid intValue];
        FBApplicationProcess *app = [[%c(FBProcessManager) sharedInstance] applicationProcessForPID:p];
        data = @{
            kApp : app.bundleIdentifier
        };
    }

    [self.kp_center_out callExternalMethod:NOW_PLAYING_APP_CHANGED_SELECTOR
                             withArguments:data
                                completion:nil];
}

/* Reattach the process */
%new
- (void)preventedAppShutdown:(NSDictionary *)data {
    %log;

    NSNumber *pid = data[kPID];
    NSString *bundleID = data[kBundleID];
    int p = [pid intValue];
    __pid = p; // TODO fix this

    FBApplicationProcess *process = getProcessForPID(p);
    if (!process)
        return;

    log(@"process: %@ (%@), %d", process, bundleID, process.nowPlayingWithAudio);
    [process setNowPlayingWithAudio:YES];

    SBApplication *app = [[%c(SBApplicationController) sharedInstance] applicationWithBundleIdentifier:bundleID];
    [app _processWillLaunch:process];
    [app _processDidLaunch:process];

    FBProcessState *processState = [[%c(FBProcessState) alloc] initWithPid:p];
    [processState setVisibility:Background];
    [processState setTaskState:Background];

    SBApplicationProcessState *sbProcessSate = [[%c(SBApplicationProcessState) alloc] _initWithProcess:process
                                                                                         stateSnapshot:processState];
    [app _setInternalProcessState:sbProcessSate];


    [processState setVisibility:Foreground];
    sbProcessSate = [[%c(SBApplicationProcessState) alloc] _initWithProcess:process
                                                              stateSnapshot:processState];
    [app _setInternalProcessState:sbProcessSate];

    [self launchApplicationWithIdentifier:bundleID suspended:YES];

    dispatch_time_t timedis = dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC);
    dispatch_after(timedis, dispatch_get_main_queue(), ^(void) {
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

    // SBMediaController *mediaController = [%c(SBMediaController) sharedInstance];
    // id aa = mediaController.nowPlayingApplication;
    // int pid = mediaController.nowPlayingProcessPID;
    // log(@"sb loaded: %@, pid: %d", aa, pid);
}

%end


%hook SBFluidSwitcherViewController

- (void)killContainer:(SBReusableSnapshotItemContainer *)container forReason:(long long)reason {
    %log;

    SBAppLayout *appLayout = container.snapshotAppLayout;
    NSSet *set = [NSSet setWithArray:@[@"com.spotify.client"]];
    if ([appLayout containsAny:set]) {
        FBApplicationProcess *process = getProcessForPID(__pid);
        [process killForReason:kKilledByAppSwitcher andReport:NO withDescription:nil];
    }

    %orig;
}

%end


%hook SBAppLayout

%new
- (BOOL)containsAny:(NSSet<NSString *> *)bundleIdentifiers {
    NSString *primaryBundleID = [self allItems][0].bundleIdentifier;
    return [bundleIdentifiers containsObject:primaryBundleID];
}

%end


%ctor {
    if (%c(SpringBoard) || %c(FBProcessManager)) {
        NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
        log(@"loading into bundleID: %@", bundleID);
        %init;
    }
}
