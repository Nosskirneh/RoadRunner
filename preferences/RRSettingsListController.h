#import <Preferences/Preferences.h>
#import "../SettingsKeys.h"

#define RRColor [UIColor colorWithRed:0.00 green:0.65 blue:1.00 alpha:1.0] // #00A5FF

#define kPostNotification @"PostNotification"
#define kIconImage @"iconImage"
#define kKey @"key"
#define kID @"id"
#define kDefault @"default"
#define kCell @"cell"

@interface RRSettingsListController : PSListController {
    UIWindow *settingsView;
}
- (void)setEnabled:(BOOL)enabled forSpecifierWithID:(NSString *)identifier;
- (void)setEnabled:(BOOL)enabled forSpecifier:(PSSpecifier *)specifier;
- (void)setEnabled:(BOOL)enabled forSpecifiersAfterSpecifier:(PSSpecifier *)specifier;
- (void)setEnabled:(BOOL)enabled forSpecifiersAfterSpecifier:(PSSpecifier *)specifier
                                         excludedIdentifiers:(NSSet *)excludedIdentifiers;
- (void)presentOKAlertWithTitle:(NSString *)title message:(NSString *)message;
- (void)presentAlertWithTitle:(NSString *)title
                      message:(NSString *)message
                      actions:(NSArray<UIAlertAction *> *)actions;
- (void)respring;
@end
