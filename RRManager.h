#import <Foundation/Foundation.h>

@interface RRManager : NSObject
@property (nonatomic, retain, readonly) NSString *immortalPartyingBundleID;
- (NSDictionary *)getAllProcessStates;
- (void)handleDaemonDidStart;
@end
