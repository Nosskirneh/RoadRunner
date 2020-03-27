#import "Common.h"
#import "KPCenter.h"
#import "FrontBoard.h"
#import "SpringBoard.h"
#import "KPManager.h"


KPManager *manager;


%hook SBFluidSwitcherViewController

- (void)killContainer:(SBReusableSnapshotItemContainer *)container
            forReason:(long long)reason {
    SBAppLayout *appLayout = container.snapshotAppLayout;
    NSString *immortalBundleID = manager.immortalBundleID;

    if (immortalBundleID && [appLayout containsItemWithBundleIdentifier:immortalBundleID]) {
        [manager killImmortalApp];
    }

    %orig;
}

%end


%ctor {
    if (%c(SpringBoard) || %c(FBProcessManager)) {
        manager = [[KPManager alloc] init];
        %init;
    }
}
