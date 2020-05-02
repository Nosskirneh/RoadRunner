#import "RunningBoardServices.h"

#define kParentProcessDied 0xB111B111


@interface RBSProcessHandle (RB)
@property (nonatomic, assign) BOOL partying;
@property (nonatomic, assign) BOOL immortal;
@end


@class RBProcess;

@interface RBProcess : NSObject
@property (nonatomic, readonly) RBProcess *hostProcess;
@property (nonatomic, copy, readonly) RBSProcessIdentity *identity;
@property (nonatomic, copy, readonly) RBSProcessHandle *handle;

- (int)rbs_pid;
- (BOOL)terminateWithContext:(RBSTerminateContext *)context;
@end

@interface RBProcessManager : NSObject
- (RBProcess *)processForIdentity:(RBSProcessIdentity *)identity;
@end

@interface RBProcessManager (RoadRunner)
@property (nonatomic, retain) NSString *nowPlayingBundleID;
- (RBProcess *)processForBundleID:(NSString *)bundleID;
- (void)nowPlayingAppChanged:(NSString *)bundleID;
@end
