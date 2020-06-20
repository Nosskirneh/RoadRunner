#import "RRSettingsListController.h"
#import <Preferences/Preferences.h>
#import <UIKit/UITableViewLabel.h>
#import "../DRMOptions.mm"
#import "../../DRM/PFStatusBarAlert/PFStatusBarAlert.h"
#import <spawn.h>
#import <notify.h>
#import "../../TwitterStuff/Prompt.h"
#import "../SettingsKeys.h"
#import "RRAppListController.h"


// Header
@interface RRSettingsHeaderCell : PSTableCell {
    UILabel *_label;
}
@end

// Colorful UISwitches
@interface PSSwitchTableCell : PSControlTableCell
- (id)initWithStyle:(int)style reuseIdentifier:(id)identifier specifier:(id)specifier;
@end

@interface RRSwitchTableCell : PSSwitchTableCell
@end


@interface RRColorButtonCell : PSTableCell
@end

#define kPostNotification @"PostNotification"

@interface RRRootListController : RRSettingsListController <PFStatusBarAlertDelegate, DRMDelegate>
@property (nonatomic, strong) PFStatusBarAlert *statusAlert;
@property (nonatomic, weak) UIAlertAction *okAction;
@property (nonatomic, weak) NSString *okRegex;
@property (nonatomic, strong) UIAlertController *giveawayAlertController;
@end

@implementation RRRootListController

- (id)init {
    if (self == [super init]) {
        UIBarButtonItem *respringButton = [[UIBarButtonItem alloc] initWithTitle:@"Respring"
                                                                           style:UIBarButtonItemStylePlain
                                                                          target:self
                                                                          action:@selector(respring)];
        self.navigationItem.rightBarButtonItem = respringButton;
    }

    return self;
}

- (NSArray *)specifiers {
    if (_specifiers)
        return _specifiers;

    NSMutableArray *specifiers = [NSMutableArray new];

    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:nil
                                                            target:nil
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSGroupCell
                                                              edit:nil];
    [specifier setProperty:NSStringFromClass(RRSettingsHeaderCell.class) forKey:@"headerCellClass"];
    [specifiers addObject:specifier];

    specifier = [self createSwitchCellWithLabel:@"Enabled" default:YES key:kEnabled requiresRespring:YES notification:NO];
    [specifiers addObject:specifier];

    PSSpecifier *modeGroupSpecifier = [self createGroupCellWithLabel:@"Mode" footerText:@"If \"Media apps\" is picked, RoadRunner will only exclude the now playing app. "\
                                          "If other apps is picked, keep in mind that you need to manually restart apps if a tweak that targets "\
                                          "them has been installed or updated. Also, beware that excluding of package managers may "\
                                          "cause weird behavior the next time opening them."];
    [specifiers addObject:modeGroupSpecifier];

    specifier = [self createSegmentCellWithValues:@[@NO, @YES]
                                           titles:@[@"Media apps", @"Media & Other apps"]
                                          default:@NO
                                              key:kExcludeOtherApps
                                 requiresRespring:NO
                                     notification:YES];
    [specifiers addObject:specifier];

    PSSpecifier *otherAppsGroupSpecifier = [self createGroupCellWithLabel:@"Other apps" footerText:nil];
    [specifiers addObject:otherAppsGroupSpecifier];

    PSSpecifier *applistSpecifier = [PSSpecifier preferenceSpecifierNamed:@"Listed apps"
                                                                   target:self
                                                                      set:@selector(setPreferenceValue:specifier:)
                                                                      get:@selector(readPreferenceValue:)
                                                                   detail:RRAppListController.class
                                                                     cell:PSLinkCell
                                                                     edit:nil];
    [applistSpecifier setProperty:kListedApps forKey:kID];

    NSString *listedAppsFooterText = @"Whitelist: only listed apps will be kept alive.\n"\
                                      "Blacklist: all apps will be kept alive aside from the listed ones.";
    if (dlopen("/usr/lib/libapplist.dylib", RTLD_NOW) == NULL) {
        [applistSpecifier setProperty:@NO forKey:kEnabled];
        listedAppsFooterText = [listedAppsFooterText stringByAppendingString:@"\n\nInstall AppList to whitelist or blacklist apps."];
    }
    [otherAppsGroupSpecifier setProperty:listedAppsFooterText forKey:kFooterText];

    specifier = [self createSegmentCellWithValues:@[@YES, @NO]
                                           titles:@[@"Whitelist", @"Blacklist"]
                                          default:@YES
                                              key:kIsWhitelist
                                 requiresRespring:NO
                                     notification:YES];

    [specifiers addObject:specifier];
    [specifiers addObject:applistSpecifier];

    specifier = [self createGroupCellWithLabel:@"Other" footerText:@"© 2020 Andreas Henriksson"];
    [specifier setProperty:@1 forKey:@"footerAlignment"];
    [specifiers addObject:specifier];

    [specifiers addObject:[self createButtonCellWithLabel:@"Check out my other tweaks"
                                                 selector:@selector(myTweaks)]];
    [specifiers addObject:[self createButtonCellWithLabel:@"Follow me on Twitter"
                                                 selector:@selector(followTwitter)]];
    [specifiers addObject:[self createButtonCellWithLabel:@"Discord server"
                                                 selector:@selector(discordServer)]];
    [specifiers addObject:[self createButtonCellWithLabel:@"Icon by @bossgfx_"
                                                 selector:@selector(iconCredits)]];
    [specifiers addObject:[self createButtonCellWithLabel:@"Email me"
                                                 selector:@selector(sendEmail)]];

    // Add license specifiers
    specifiers = addDRMSpecifiers(specifiers, self, licensePath$bs(), kPrefPath,
                                  package$bs(), licenseFooterText$bs(), trialFooterText$bs());

    _specifiers = specifiers;
    return specifiers;
}

- (PSSpecifier *)createSegmentCellWithValues:(NSArray *)values
                                      titles:(NSArray *)titles
                                     default:(NSNumber *)def
                                         key:(NSString *)key
                            requiresRespring:(BOOL)requiresRespring
                                notification:(BOOL)notification {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:nil
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSegmentCell
                                                              edit:nil];
    [specifier setProperty:kIsWhitelist forKey:kKey];
    [specifier setProperty:kIsWhitelist forKey:kID];
    [specifier setValues:values titles:titles];

    [specifier setProperty:def forKey:kDefault];
    [specifier setProperty:key forKey:kKey];
    [specifier setProperty:key forKey:kID];
    if (requiresRespring) {
        [specifier setProperty:@YES forKey:kRequiresRespring];
    }

    if (notification) {
        [specifier setProperty:@kSettingsChanged forKey:kPostNotification];
    }
    return specifier;
}

- (PSSpecifier *)createSwitchCellWithLabel:(NSString *)label
                                   default:(BOOL)def
                                       key:(NSString *)key
                          requiresRespring:(BOOL)requiresRespring
                              notification:(BOOL)notification {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:label
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSwitchCell
                                                              edit:nil];
    [specifier setProperty:RRSwitchTableCell.class forKey:@"cellClass"];
    [specifier setProperty:@(def) forKey:kDefault];
    [specifier setProperty:key forKey:kKey];
    [specifier setProperty:key forKey:kID];
    if (requiresRespring) {
        [specifier setProperty:@YES forKey:kRequiresRespring];
    }

    if (notification) {
        [specifier setProperty:@kSettingsChanged forKey:kPostNotification];
    }
    return specifier;
}

- (PSSpecifier *)createButtonCellWithLabel:(NSString *)label selector:(SEL)selector {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:label
                                                            target:nil
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
    [specifier setProperty:RRColorButtonCell.class forKey:@"cellClass"];

    if (selector) {
        [specifier setProperty:NSStringFromSelector(selector) forKey:kAction];
    }
    return specifier;
}

- (PSSpecifier *)createGroupCellWithLabel:(NSString *)label
                               footerText:(NSString *)footerText {
    PSSpecifier *specifier = [PSSpecifier groupSpecifierWithName:label];
    if (footerText) {
        [specifier setProperty:footerText forKey:kFooterText];
        [specifier setProperty:@0 forKey:@"footerAlignment"];
    }
    return specifier;
}

- (void)loadView {
    [super loadView];
    presentFollowAlert(kPrefPath, self);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (!self.statusAlert) {
        self.statusAlert = [[PFStatusBarAlert alloc] initWithMessage:nil
                                                        notification:nil
                                                              action:@selector(respring)
                                                              target:self];
        self.statusAlert.backgroundColor = [UIColor colorWithHue:0.590
                                                      saturation:1
                                                      brightness:1
                                                           alpha:0.9];
        self.statusAlert.textColor = [UIColor whiteColor];
    }
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:kPrefPath];
    NSString *key = [specifier propertyForKey:kKey];
    if ([key isEqualToString:kExcludeOtherApps] && (!preferences[key] || ![preferences[key] boolValue])) {
        [super setEnabled:NO forSpecifierWithID:kListedApps];
        [super setEnabled:NO forSpecifierWithID:kIsWhitelist];
    }

    return [super readPreferenceValue:specifier];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:kKey];
    if ([key isEqualToString:kExcludeOtherApps]) {
        BOOL enable = [value boolValue];
        [super setEnabled:enable forSpecifierWithID:kListedApps];
        [super setEnabled:enable forSpecifierWithID:kIsWhitelist];
    }

    [super setPreferenceValue:value specifier:specifier];
}

- (void)activate {
    activate(licensePath$bs(), package$bs(), self);
}

- (BOOL)textField:(UITextField *)textField
        shouldChangeCharactersInRange:(NSRange)range
        replacementString:(NSString *)string {
    [self textFieldChanged:textField];
    return YES;
}

- (void)textFieldChanged:(UITextField *)textField {
    determineUnlockOKButton(textField, self);
}

- (void)trial {
    trial(licensePath$bs(), package$bs(), self);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self reloadSpecifiers];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (self.statusAlert)
        [self.statusAlert hideOverlay];
}

- (void)sendEmail {
    openURL([NSURL URLWithString:@"mailto:andreaskhenriksson@gmail.com?subject=RoadRunner"]);
}

- (void)followTwitter {
    openTwitter();
}

- (void)purchase {
    fetchPrice(package$bs(), self, ^(const NSString *respondingServer,
                                     const NSString *price,
                                     const NSString *URL) {
        redirectToCheckout(respondingServer, URL, self);
    });
}

- (void)myTweaks {
    openURL([NSURL URLWithString:@"https://henrikssonbrothers.com/cydia/repo/packages.html"]);
}

- (void)iconCredits {
    openTwitterWithUsername(@"bossgfx_");
}

- (void)discordServer {
    openURL([NSURL URLWithString:@"https://discord.gg/znn8wfw"]);
}

- (void)safariViewControllerDidFinish:(id)arg1 {
    safariViewControllerDidFinish(self);
}

@end



@implementation RRSwitchTableCell

- (id)initWithStyle:(int)style reuseIdentifier:(id)identifier specifier:(id)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self)
        [((UISwitch *)[self control]) setOnTintColor:KPColor];
    return self;
}

@end


@implementation RRSettingsHeaderCell

- (id)initWithSpecifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"headerCell" specifier:specifier];
    if (self) {
        _label = [[UILabel alloc] initWithFrame:[self frame]];
        [_label setTranslatesAutoresizingMaskIntoConstraints:NO];
        [_label setAdjustsFontSizeToFitWidth:YES];
        [_label setFont:[UIFont fontWithName:@"HelveticaNeue-UltraLight" size:48]];

        NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:@"RoadRunner"];

        [_label setAttributedText:attributedString];
        [_label setTextAlignment:NSTextAlignmentCenter];
        [_label setBackgroundColor:[UIColor clearColor]];

        [self addSubview:_label];
        [self setBackgroundColor:[UIColor clearColor]];

        // Setup constraints
        NSLayoutConstraint *leftConstraint = [NSLayoutConstraint constraintWithItem:_label
                                                                          attribute:NSLayoutAttributeLeft
                                                                          relatedBy:NSLayoutRelationEqual
                                                                             toItem:self
                                                                          attribute:NSLayoutAttributeLeft
                                                                         multiplier:1.0
                                                                           constant:0.0];
        NSLayoutConstraint *rightConstraint = [NSLayoutConstraint constraintWithItem:_label
                                                                           attribute:NSLayoutAttributeRight
                                                                           relatedBy:NSLayoutRelationEqual
                                                                              toItem:self
                                                                           attribute:NSLayoutAttributeRight
                                                                          multiplier:1.0
                                                                            constant:0.0];
        NSLayoutConstraint *bottomConstraint = [NSLayoutConstraint constraintWithItem:_label
                                                                            attribute:NSLayoutAttributeBottom
                                                                            relatedBy:NSLayoutRelationEqual
                                                                               toItem:self
                                                                            attribute:NSLayoutAttributeBottom
                                                                           multiplier:1.0
                                                                             constant:0.0];
        NSLayoutConstraint *topConstraint = [NSLayoutConstraint constraintWithItem:_label
                                                                         attribute:NSLayoutAttributeTop
                                                                         relatedBy:NSLayoutRelationEqual
                                                                            toItem:self
                                                                         attribute:NSLayoutAttributeTop
                                                                        multiplier:1.0
                                                                          constant:0.0];
        [self addConstraints:@[leftConstraint, rightConstraint, bottomConstraint, topConstraint]];
    }
    return self;
}

// Return a custom cell height.
- (CGFloat)preferredHeightForWidth:(CGFloat)width {
    return 140.f;
}

@end


@implementation RRColorButtonCell

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.textLabel setTextColor:KPColor];
}

@end
