@interface RBLaunchdJob : NSObject
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
@property (nonatomic, retain) NSString *nowPlayingBundleID;
@property (nonatomic, retain) RBProcess *immortalProcess;
@property (nonatomic, retain) KPCenter *kp_center_in;
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
