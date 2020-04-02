#define kImmortalProcess @"immortalProcess"
#define kPartyingProcess @"partyingProcess"


@interface RBSProcessIdentifier : NSObject
- (int)rbs_pid;
@end

@interface RBSConnection : NSObject
+ (id)sharedInstance;
@end

@interface RBSProcessIdentity : NSObject
@property (nonatomic, copy, readonly) NSString *embeddedApplicationIdentifier;
@property (nonatomic, copy, readonly) RBSProcessIdentifier *hostIdentifier;
+ (id)identityForEmbeddedApplicationIdentifier:(NSString *)applicationIdentifier;
@end


@class RBSProcessState, RBSProcessHandle;

@interface RBSProcessHandle : NSObject
@property (nonatomic, readonly) RBSProcessState *currentState;
@property (nonatomic, readonly) RBSProcessHandle *hostProcess;
@property (nonatomic, copy, readonly) RBSProcessIdentity *identity;
@property (nonatomic, readonly) int pid;
@end


@interface RBSProcessState : NSObject
@property (nonatomic, readonly) RBSProcessHandle *process;
@end

@interface BSXPCCoder : NSObject
- (BOOL)decodeBoolForKey:(NSString *)key;
- (void)encodeBool:(BOOL)value forKey:(NSString *)key;
@end
