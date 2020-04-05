#import "Common.h"
#import "SettingsKeys.h"

BOOL isEnabled() {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:kPrefPath];

    if (preferences) {
        NSNumber *enabled = preferences[kEnabled];
        if (enabled && ![enabled boolValue]) {
            return NO;
        }
    }
    return YES;
}
