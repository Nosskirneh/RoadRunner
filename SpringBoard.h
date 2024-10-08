#import "FrontBoard.h"
#import <SpringBoard/SBApplication.h>
#import <SpringBoard/SBMediaController.h>
#import "RunningBoardServices.h"



@interface RBSProcessState (SB)
@property (nonatomic, assign) BOOL partying;
@property (nonatomic, assign) BOOL immortal;
@end



@interface SpringBoard : NSObject
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier
                              suspended:(BOOL)suspended;
@end


@interface SBApplicationProcessState : NSObject
- (id)_initWithProcess:(FBApplicationProcess *)process
         stateSnapshot:(FBProcessState *)processState;
@end

@interface SBApplication (Private)
@property (assign, getter=isPlayingAudio, nonatomic) BOOL playingAudio;
- (void)_processWillLaunch:(FBApplicationProcess *)applicationProcess;
- (void)_processDidLaunch:(FBApplicationProcess *)applicationProcess;
- (void)_setInternalProcessState:(SBApplicationProcessState *)processState;
- (NSString *)_baseSceneIdentifier;
@end

@interface SBApplicationController : NSObject
+ (id)sharedInstance;
- (id)applicationWithPid:(int)pid;
- (id)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface SBDisplayItem : NSObject
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@end

@interface SBAppLayout : NSObject
- (BOOL)containsItemWithBundleIdentifier:(NSString *)bundleIdentifier;
- (NSArray<SBDisplayItem *> *)allItems;
@end
