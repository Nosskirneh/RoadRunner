#import "RRSettingsListController.h"
#import <notify.h>
#import <objc/runtime.h>
#import <spawn.h>
#import "LocalizableKeys.h"

@interface UISegmentedControl (Missing)
- (void)selectSegment:(int)index;
@end

@interface PSSegmentTableCell : PSControlTableCell
@property (retain) UISegmentedControl *control;
@end

@interface PSSwitchTableCell : PSControlTableCell
@property (retain) UISwitch *control;
@end

@interface PSSliderTableCell : PSControlTableCell
@property (retain) UISlider *control;
@end

typedef enum {
      NoneRespringStyle      = 0,
      RestartRenderServer    = (1 << 0), // also relaunch backboardd
      SnapshotTransition     = (1 << 1),
      FadeToBlackTransition  = (1 << 2),
} SBSRelaunchActionStyle;

@interface SBSRelaunchAction : NSObject
+ (id)actionWithReason:(NSString *)reason
               options:(SBSRelaunchActionStyle)options
             targetURL:(NSURL *)url;
@end

@interface SBSRestartRenderServerAction : SBSRelaunchAction
+ (id)restartActionWithTargetRelaunchURL:(NSURL *)url;
@end

@interface FBSSystemService : NSObject
+ (id)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)completion;
@end


static void killProcess(const char *name) {
    pid_t pid;
    int status;
    const char *args[] = { "killall", "-9", name, NULL };
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
    waitpid(pid, &status, WEXITED);
}

static void respring() {
    if (objc_getClass("FBSSystemService")) {
        Class relaunchAction = objc_getClass("SBSRelaunchAction");
        SBSRelaunchAction *restartAction = relaunchAction ?
                                               [relaunchAction actionWithReason:@"RestartRenderServer"
                                                                        options:FadeToBlackTransition
                                                                      targetURL:nil] :
                                               [objc_getClass("SBSRestartRenderServerAction") restartActionWithTargetRelaunchURL:nil];
        [[objc_getClass("FBSSystemService") sharedService] sendActions:[NSSet setWithObject:restartAction]
                                                            withResult:nil];
    } else {
        killProcess("SpringBoard");
    }
}

@implementation RRSettingsListController

- (void)respring {
    // This is not optimal, but debug savvy people will have to respring from the terminal...
    killProcess("runningboardd");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        respring();
    });
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:kPrefPath];
    NSString *key = [specifier propertyForKey:kKey];

    if (preferences[key])
        return preferences[key];

    return specifier.properties[kDefault];
}

- (void)savePreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:kKey];

    NSMutableDictionary *preferences = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefPath];
    if (!preferences)
        preferences = [NSMutableDictionary new];
    [preferences setObject:value forKey:key];
    [preferences writeToFile:kPrefPath atomically:YES];

    NSString *notificationString = specifier.properties[kPostNotification];
    if (notificationString)
        notify_post([notificationString UTF8String]);
}

- (void)preferenceValueChanged:(id)value specifier:(PSSpecifier *)specifier {}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [self preferenceValueChanged:value specifier:specifier];

    NSNumber *restart = [specifier propertyForKey:kRequiresRespring];
    if (restart && [restart boolValue]) {
        UIAlertAction *respringAction = [UIAlertAction actionWithTitle:stringForKey(kYES)
                                                                 style:UIAlertActionStyleDestructive
                                                               handler:^(UIAlertAction *action) {
                                            [self savePreferenceValue:value specifier:specifier];
                                            [self respring];
                                        }];

        UIAlertAction *cancelAction = [self createCancelAction:specifier];

        UIAlertAction *laterAction = [UIAlertAction actionWithTitle:stringForKey(kRESPRING_LATER)
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *action) {
            [self savePreferenceValue:value specifier:specifier];
        }];
        [self presentAlertWithTitle:stringForKey(kRESTART_PROCESSES)
                            message:stringForKey(kREQUIRES_RESPRING)
                            actions:@[respringAction, cancelAction, laterAction]];
        return;
    } else if ((restart = [specifier propertyForKey:kRequiresAppRestart]) && [restart boolValue]) {
        [self presentOKAlertWithTitle:stringForKey(kRESTART_APP)
                              message:stringForKey(kREQUIRES_APP_RESTART)];
    }

    [self savePreferenceValue:value specifier:specifier];
}

- (UIAlertAction *)createCancelAction:(PSSpecifier *)specifier {
    return [UIAlertAction actionWithTitle:stringForKey(kREVERT_CHANGE)
                                    style:UIAlertActionStyleCancel
                                  handler:^(UIAlertAction *action) {
        NSIndexPath *indexPath = [self indexPathForSpecifier:specifier];
        PSTableCell *cell = [self tableView:self.table cellForRowAtIndexPath:indexPath];
        id pickedValue = [self readPreferenceValue:specifier];

        if ([cell isKindOfClass:%c(PSSegmentTableCell)]) {
            PSSegmentTableCell *segmentCell = (PSSegmentTableCell *)cell;
            int segmentIndex = [MSHookIvar<NSArray *>(segmentCell, "_values") indexOfObject:pickedValue];
            [segmentCell.control selectSegment:segmentIndex];
        } else if ([cell isKindOfClass:%c(PSSwitchTableCell)]) {
            PSSwitchTableCell *switchCell = (PSSwitchTableCell *)cell;
            [switchCell.control setOn:[pickedValue boolValue] animated:YES];
        } else if ([cell isKindOfClass:%c(PSSliderTableCell)]) {
            PSSliderTableCell *sliderCell = (PSSliderTableCell *)cell;
            [sliderCell.control setValue:[pickedValue floatValue] animated:YES];
        }

        [self preferenceValueChanged:pickedValue specifier:specifier];
    }];
}

- (void)setEnabled:(BOOL)enabled forSpecifierWithID:(NSString *)identifier {
    PSSpecifier *specifier = [self specifierForID:identifier];
    [self setEnabled:enabled forSpecifier:specifier];
}

- (void)setEnabled:(BOOL)enabled forSpecifier:(PSSpecifier *)specifier {
    if (!specifier || [[specifier propertyForKey:kCell] isEqualToString:@"PSGroupCell"])
        return;

    NSIndexPath *indexPath = [self indexPathForSpecifier:specifier];
    if (indexPath.row == NSNotFound)
        return;

    PSTableCell *cell = [self tableView:self.table cellForRowAtIndexPath:indexPath];
    if (cell) {
        cell.userInteractionEnabled = enabled;
        cell.textLabel.enabled = enabled;
        cell.detailTextLabel.enabled = enabled;

        if ([cell isKindOfClass:[PSControlTableCell class]]) {
            PSControlTableCell *controlCell = (PSControlTableCell *)cell;
            if (controlCell.control)
                controlCell.control.enabled = enabled;
        } else {
            [cell setCellEnabled:enabled];
        }
    }
}

- (void)setEnabled:(BOOL)enabled forSpecifiersAfterSpecifier:(PSSpecifier *)specifier {
    long long index = [self indexOfSpecifier:specifier];
    for (int i = index + 1; i < _specifiers.count; i++)
        [self setEnabled:enabled forSpecifier:_specifiers[i]];
}

- (void)setEnabled:(BOOL)enabled forSpecifiersAfterSpecifier:(PSSpecifier *)specifier
                                         excludedIdentifiers:(NSSet *)excludedIdentifiers {
    if (!excludedIdentifiers)
        return [self setEnabled:enabled forSpecifiersAfterSpecifier:specifier];

    long long index = [self indexOfSpecifier:specifier];
    for (int i = index + 1; i < _specifiers.count; i++) {
        PSSpecifier *specifier = _specifiers[i];
        if (![excludedIdentifiers containsObject:specifier.identifier])
            [self setEnabled:enabled forSpecifier:specifier];
    }
}

- (void)presentOKAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *defaultAction = [UIAlertAction actionWithTitle:stringForKey(kOK)
                                                            style:UIAlertActionStyleDefault
                                                          handler:nil];
    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentAlertWithTitle:(NSString *)title
                      message:(NSString *)message
                      actions:(NSArray<UIAlertAction *> *)actions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    if (actions) {
        for (UIAlertAction *action in actions)
            [alert addAction:action];
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Tint
    settingsView = [[UIApplication sharedApplication] keyWindow];
    settingsView.tintColor = RRColor;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    settingsView = [[UIApplication sharedApplication] keyWindow];
    settingsView.tintColor = nil;
}

@end
