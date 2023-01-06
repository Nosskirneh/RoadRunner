#import <Foundation/Foundation.h>

typedef struct {
    virtual void normal() = 0;
    virtual void welcome() = 0;
    virtual void trial() = 0;
    virtual void pirated() = 0;
} IInitFunctions;

@interface RRManager : NSObject
@property (nonatomic, assign, readonly) BOOL trialEnded;
@property (nonatomic, retain, readonly) NSString *immortalPartyingBundleID;
- (void)setTrialEnded;
- (NSDictionary *)getAllProcessStates;
- (void)handleDaemonDidStart;
@end
