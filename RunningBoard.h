@interface RBProcessManager : NSObject
@property (retain) NSString *nowPlayingBundleID;
@property (retain) KPCenter *kp_center;
@end

@interface RBSProcessIdentity : NSObject
@property (nonatomic, copy, readonly) NSString *embeddedApplicationIdentifier;
@end

@interface RBSTerminateRequest : NSObject
@property (copy, nonatomic) RBSProcessIdentity *processIdentity;
@end
