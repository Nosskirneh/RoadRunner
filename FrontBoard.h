@interface FBApplicationProcess : NSObject
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@end

@interface FBProcessManager : NSObject
+ (id)sharedInstance;
- (id)applicationProcessForPID:(int)pid;
@end
