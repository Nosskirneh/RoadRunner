@interface FBApplicationProcess : NSObject
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (assign, getter=isNowPlayingWithAudio, nonatomic) BOOL nowPlayingWithAudio;
- (void)killForReason:(long long)reason
            andReport:(BOOL)report
      withDescription:(id)description;
@end

@interface FBProcessManager : NSObject
+ (id)sharedInstance;
- (id)applicationProcessForPID:(int)pid;
@end


typedef enum ProcessVisiblity {
    Unknown = 0,
    Background = 1,
    Foreground = 2,
    ForegroundObscured = 3
} ProcessVisiblity;

@interface FBProcessState : NSObject
@property (assign, getter=isForeground, nonatomic) BOOL foreground;
@property (assign, nonatomic) ProcessVisiblity visibility;
@property (assign, nonatomic) ProcessVisiblity taskState;
- (id)initWithPid:(int)pid;
@end


@interface FBSMutableSceneSettings : NSObject
@property (assign, getter=isForeground, nonatomic) BOOL foreground;
@property (assign, getter=isBackgrounded, nonatomic) BOOL backgrounded;
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
