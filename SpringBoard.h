#import "KPCenter.h"
#import "FrontBoard.h"
#import <SpringBoard/SBApplication.h>

@interface SpringBoard : NSObject
@property (nonatomic, retain) KPCenter *kp_center_in;
@property (nonatomic, retain) KPCenter *kp_center_out;
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier
                              suspended:(BOOL)suspended;
@end


@interface SBApplicationProcessState : NSObject
- (id)_initWithProcess:(FBApplicationProcess *)process
         stateSnapshot:(FBProcessState *)processState;
@end

@interface SBApplication (Private)
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

@interface SBAppLayout : NSObject
- (BOOL)containsItemWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface SBReusableSnapshotItemContainer : NSObject
@property (nonatomic, retain) SBAppLayout *snapshotAppLayout;
@end
