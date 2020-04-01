@interface KPManager : NSObject
@property (nonatomic, retain, readonly) NSString *immortalPartyingBundleID;
- (void)killImmortalPID:(int)pid;
@end
