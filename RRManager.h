#import <Foundation/Foundation.h>

@interface RRManager : NSObject
@property (nonatomic, assign, readonly) BOOL trialEnded;
@property (nonatomic, retain, readonly) NSString *immortalPartyingBundleID;
- (void)setTrialEnded;
- (NSDictionary *)getAllProcessStates;
- (void)handleDaemonDidStart;
@end
