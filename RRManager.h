@interface RRManager : NSObject
@property (nonatomic, assign, readonly) BOOL trialEnded;
@property (nonatomic, retain, readonly) NSString *immortalPartyingBundleID;
- (void)setTrialEnded;
- (void)setup;
- (void)killImmortalPID:(int)pid;
- (NSDictionary *)getAllProcessStates;
- (void)handleDaemonDidStart;
@end
