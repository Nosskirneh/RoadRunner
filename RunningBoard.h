@interface RBLaunchdJob : NSObject
// @property (nonatomic, copy, readonly) RBLaunchdJobLabel *label;
@end

@protocol RBBundleProperties
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@end

@interface RBProcess : NSObject
@property (nonatomic, readonly) RBLaunchdJob *job;
@property (nonatomic, readonly) id<RBBundleProperties> bundleProperties;
- (int)rbs_pid;
@end

@interface RBLaunchdJobRegistry : NSObject
+ (BOOL)_submitJob:(RBLaunchdJob *)job error:(id *)arg2;
@end

@interface RBProcessManager : NSObject
@property (retain) NSString *nowPlayingBundleID;
@property (nonatomic, retain) RBProcess *savedProcess;
@property (nonatomic, retain) KPCenter *kp_center_in;
@property (nonatomic, retain) KPCenter *kp_center_out;
- (RBProcess *)processForIdentity:(id)identity;
@end

@interface RBSProcessIdentifier : NSObject
- (int)rbs_pid;
@end

@interface RBSProcessIdentity : NSObject
@property (nonatomic, copy, readonly) NSString *embeddedApplicationIdentifier;
@property (nonatomic, copy, readonly) RBSProcessIdentifier *hostIdentifier;
@end

@interface RBSTerminateRequest : NSObject
@property (copy, nonatomic) RBSProcessIdentity *processIdentity;
@property (nonatomic, readonly) int pid;
@end
