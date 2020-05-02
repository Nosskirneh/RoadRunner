#import "BaseBoard.h"
#import "RunningBoardServices.h"


typedef enum ProcessVisibility {
    VisibilityUnknown = 0,
    VisibilityBackground = 1,
    VisibilityForeground = 2,
    VisibilityForegroundObscured = 3
} ProcessVisibility;

typedef enum ProcessTaskState {
    TaskStateUnknown = 0,
    TaskStateNotRunning = 1,
    TaskStateRunning = 2,
    TaskStateSuspended = 3
} ProcessTaskState;

@interface FBProcessState : NSObject
@property (assign, getter=isForeground, nonatomic) BOOL foreground;
@property (assign, nonatomic) ProcessVisibility visibility;
@property (assign, nonatomic) ProcessTaskState taskState;
- (id)initWithPid:(int)pid;
@end

@interface FBProcess : NSObject
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) FBProcessState *state;
@end

@interface FBExtensionProcess : FBProcess
@property (nonatomic, readonly) FBProcess *hostProcess;
@end

@interface FBApplicationProcess : FBProcess
@property (assign, getter=isNowPlayingWithAudio, nonatomic) BOOL nowPlayingWithAudio;
- (void)killForReason:(long long)reason
            andReport:(BOOL)report
      withDescription:(id)description;
@end

@interface FBProcessManager : NSObject
+ (id)sharedInstance;
- (id)applicationProcessForPID:(int)pid;
- (id)processForPID:(int)pid;
- (id)registerProcessForHandle:(BSProcessHandle *)handle;
@end


@interface FBSMutableSceneSettings : NSObject
@property (assign, getter=isForeground, nonatomic) BOOL foreground;
@property (assign, getter=isBackgrounded, nonatomic) BOOL backgrounded;
@end


@interface FBSProcessHandle : NSObject
@property (nonatomic, readonly) int pid;
@property (nonatomic, copy,readonly) NSString *bundleIdentifier;
@end

@interface FBScene : NSObject
- (FBSMutableSceneSettings *)mutableSettings;
@end

@interface FBSceneManager : NSObject
+ (id)sharedInstance;
- (FBScene *)sceneWithIdentifier:(NSString *)sceneIdentifier;
- (void)_applyMutableSettings:(FBSMutableSceneSettings *)settings
                      toScene:(FBScene *)scene
        withTransitionContext:(id)context
                   completion:(id)completion;
@end
