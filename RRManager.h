@interface RRManager : NSObject
@property (nonatomic, assign, readonly) BOOL trialEnded;
- (void)setTrialEnded;
- (void)setup;
- (NSDictionary *)getAllProcessStates;
- (void)handleDaemonDidStart;
@end
