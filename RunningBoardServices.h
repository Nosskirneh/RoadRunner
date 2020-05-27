#define kImmortalProcess @"immortalProcess"
#define kPartyingProcess @"partyingProcess"

typedef enum RBSTaskState {
    RBSTaskStateRunningActive = 4
} RBSTaskState;

@interface RBSProcessIdentifier : NSObject
- (int)rbs_pid;
@end

@interface RBSConnection : NSObject
+ (id)sharedInstance;
- (id)_connection;
@end

@interface RBSProcessIdentity : NSObject
@property (getter=isEmbeddedApplication, nonatomic, readonly) BOOL embeddedApplication;
@property (nonatomic, copy, readonly) NSString *embeddedApplicationIdentifier;
@property (nonatomic, copy, readonly) RBSProcessIdentifier *hostIdentifier;
+ (id)identityForEmbeddedApplicationIdentifier:(NSString *)applicationIdentifier;
+ (id)identityForDaemonJobLabel:(NSString *)jobLabel;
@end


@interface RBSTerminateContext : NSObject
@property (assign, nonatomic) unsigned long long exceptionCode;
@property (nonatomic, copy) NSString *explanation;
@end

@interface RBSTerminateRequest : NSObject
@property (nonatomic, copy) RBSProcessIdentity *processIdentity;
@property (nonatomic, readonly) RBSTerminateContext *context;
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
@property (assign, nonatomic) unsigned char taskState;
@end

@interface BSXPCCoder : NSObject
- (BOOL)decodeBoolForKey:(NSString *)key;
- (void)encodeBool:(BOOL)value forKey:(NSString *)key;
@end


@interface RBSXPCMessage : NSObject
+ (id)messageForMethod:(SEL)method arguments:(NSArray *)arguments;
- (id)invokeOnConnection:(id)connection withReturnClass:(Class)returnClass error:(id *)error;
@end
