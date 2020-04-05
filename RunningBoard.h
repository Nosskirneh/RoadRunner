#import "RunningBoardServices.h"


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
@end

@interface RBProcessManager : NSObject
- (RBProcess *)processForIdentity:(RBSProcessIdentity *)identity;
@end

@interface RBProcessManager (KeepPlaying)
@property (nonatomic, retain) RRCenter *kp_center_in;
@property (nonatomic, retain) NSString *nowPlayingBundleID;
- (RBProcess *)processForBundleID:(NSString *)bundleID;
@end


@interface RBSTerminateContext : NSObject
@end
