@interface KPManager : NSObject
@property (nonatomic, retain) NSString *immortalBundleID;
@property (nonatomic, assign) int immortalPID;
- (void)killImmortalApp;
@end
