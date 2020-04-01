/*
	TODO:
	Clean up this file. It's very messy due to a lot of testing
	and reverse engineering.
*/

#import "RunningBoardServices.h"



@interface RBSProcessHandle (RB)
@property (nonatomic, assign) BOOL partying;
@property (nonatomic, assign) BOOL immortal;
@end



@interface RBLaunchdJob : NSObject
@property (nonatomic, copy, readonly) RBSProcessIdentity *identity;
@end

@interface RBLaunchdJobLabel : NSObject
@property (nonatomic, copy, readonly) RBSProcessIdentity *identity;
@end


@interface RBProcessState : NSObject {
    unsigned char _terminationResistance;
}
@property (readonly) unsigned char terminationResistance;
@end


@protocol RBBundleProperties
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@end

@interface RBProcess : NSObject
@property (nonatomic, readonly) RBLaunchdJob *job;
@property (nonatomic, readonly) id<RBBundleProperties> bundleProperties;
@property (nonatomic, copy, readonly) RBSProcessIdentity *identity;
@property (nonatomic, copy, readonly) RBSProcessHandle *handle;

- (int)rbs_pid;
@end

@interface RBProcessManager : NSObject
@property (nonatomic, retain) KPCenter *kp_center_in;
@property (nonatomic, retain) NSString *immortalProcessBundleID;
@property (nonatomic, retain) NSString *nowPlayingBundleID;
- (RBProcess *)processForIdentity:(RBSProcessIdentity *)identity;
- (RBProcess *)processForBundleID:(NSString *)bundleID;
@end


@interface RBSTerminateContext : NSObject
@property (nonatomic, copy) NSArray *attributes;
@property (nonatomic, retain) NSSet *preventingEndowmentNamespaces;
@property (nonatomic, copy) NSString *explanation;
- (void)setMaximumTerminationResistance:(unsigned char)arg1;
@end

@interface RBSTerminateRequest : NSObject
@property (copy, nonatomic) RBSProcessIdentity *processIdentity;
@property (nonatomic, readonly) int pid;
@property (nonatomic, readonly) RBSTerminateContext *context;
@end



@interface RBAssertionIntransientState : NSObject
@property (assign, nonatomic) BOOL terminateTargetOnOriginatorExit;
@end

@interface RBConcreteTarget : NSObject
@property (nonatomic, readonly) RBProcess *process;
@property (nonatomic, copy, readonly) RBSProcessIdentity *identity;
@end

@interface RBSAttribute : NSObject
@end

@interface RBSResistTerminationGrant : RBSAttribute
+ (id)grantWithResistance:(unsigned char)resistance;
@property (nonatomic, readonly) unsigned char resistance;
@end

@interface RBAssertion : NSObject
@property (nonatomic, copy, readonly) NSString *explanation;
@property (nonatomic, copy, readonly) RBAssertionIntransientState *intransientState;
@property (nonatomic, copy, readonly) RBConcreteTarget *target;
@end

@interface RBSAssertionDescriptor : NSObject
@property (nonatomic, copy, readonly) NSString *explanation;
@property (nonatomic, copy, readonly) NSArray *attributes;
@end


@interface RBAssertionAcquisitionContext : NSObject
+ (id)contextForProcess:(id)arg1 withDescriptor:(id)arg2;
@property (nonatomic, readonly) RBProcess *process;
@property (nonatomic, readonly) RBSAssertionDescriptor *descriptor;
@end


@interface RBProcessStateChangeSet : NSObject
- (id)processStateChangeForIdentity:(id)arg1;
@end




@interface RBSEndowmentGrant
+ (id)grantWithNamespace:(id)arg1 endowment:(NSObject *)arg2;
@property (nonatomic,copy,readonly) NSString *endowmentNamespace;
@end



@interface RBSHereditaryGrant : RBSAttribute
+ (id)grantWithNamespace:(NSString *)arg1 endowment:(NSObject *)arg2 attributes:(id)arg3 ;
+ (id)grantWithNamespace:(NSString *)arg1 sourceEnvironment:(id)arg2 attributes:(id)arg3 ;
@end



@interface RBLaunchdJobRegistry : NSObject
+ (BOOL)_submitJob:(RBLaunchdJob *)arg1 error:(id *)arg2;
@end
