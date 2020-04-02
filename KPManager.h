@interface KPManager : NSObject
@property (nonatomic, assign, readonly) BOOL trialEnded;
@property (nonatomic, retain, readonly) NSString *immortalPartyingBundleID;
- (void)killImmortalPID:(int)pid;
- (void)setTrialEnded;
- (void)setup;
- (NSDictionary *)getAllProcessStates;
@end
