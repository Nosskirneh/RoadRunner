#import "../Common.h"
#import <UIKit/UIKit.h>
#import <HBLog.h>
#import "RRSettingsListController.h"
#import <Preferences/Preferences.h>
#import <UIKit/UITableViewLabel.h>
#import <spawn.h>
#import <notify.h>
#import <dlfcn.h>
#import "TwitterStuff/Prompt.h"
#import "../SettingsKeys.h"
#import "RRAppListController.h"
#import "LocalizableKeys.h"

#define ICON_DESIGNER @"bossgfx_"


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

@interface RRRootListController : RRSettingsListController 
@end

@implementation RRRootListController

- (id)init {
    if (self == [super init]) {
        UIBarButtonItem *respringButton = [[UIBarButtonItem alloc] initWithTitle:stringForKey(kRESPRING)
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
    [specifier setProperty:NSStringFromClass(RRSettingsHeaderCell.class) forKey:kHeaderCellClass];
    [specifiers addObject:specifier];

    specifier = [self createSwitchCellWithLabel:stringForKey(kENABLED) default:YES key:kEnabled requiresRespring:YES notification:NO];
    [specifiers addObject:specifier];

    PSSpecifier *modeGroupSpecifier = [self createGroupCellWithLabel:stringForKey(kMODE) footerText:stringForKey(kMODE_FOOTER_TEXT)];
    [specifiers addObject:modeGroupSpecifier];

    specifier = [self createSegmentCellWithValues:@[@NO, @YES]
                                           titles:@[stringForKey(kMEDIA_APPS), stringForKey(kMEDIA_AND_OTHER_APPS)]
                                          default:@NO
                                              key:kExcludeOtherApps
                                 requiresRespring:NO
                                     notification:YES];
    [specifiers addObject:specifier];

    PSSpecifier *otherAppsGroupSpecifier = [self createGroupCellWithLabel:stringForKey(kOTHER_APPS) footerText:nil];
    [specifiers addObject:otherAppsGroupSpecifier];

    PSSpecifier *applistSpecifier = [PSSpecifier preferenceSpecifierNamed:stringForKey(kLISTED_APPS)
                                                                   target:self
                                                                      set:@selector(setPreferenceValue:specifier:)
                                                                      get:@selector(readPreferenceValue:)
                                                                   detail:RRAppListController.class
                                                                     cell:PSLinkCell
                                                                     edit:nil];
    [applistSpecifier setProperty:kListedApps forKey:kID];

    NSString *listedAppsFooterText = [NSString stringWithFormat:@"%@\n%@", stringForKey(kWHITELIST_DESCRIPTION),
                                                                           stringForKey(kBLACKLIST_DESCRIPTION)];
    if (dlopen("/usr/lib/libapplist.dylib", RTLD_NOW) == NULL) {
        [applistSpecifier setProperty:@NO forKey:kEnabled];
        listedAppsFooterText = [listedAppsFooterText stringByAppendingFormat:@"\n\n%@", stringForKey(kINSTALL_APPLIST)];
    }
    [otherAppsGroupSpecifier setProperty:listedAppsFooterText forKey:kFooterText];

    specifier = [self createSegmentCellWithValues:@[@YES, @NO]
                                           titles:@[stringForKey(kWHITELIST), stringForKey(kBLACKLIST)]
                                          default:@YES
                                              key:kIsWhitelist
                                 requiresRespring:NO
                                     notification:YES];

    [specifiers addObject:specifier];
    [specifiers addObject:applistSpecifier];

    specifier = [self createGroupCellWithLabel:stringForKey(kOTHER) footerText:@"© 2020 Andreas Henriksson"];
    [specifier setProperty:@1 forKey:kFooterAlignment];
    [specifiers addObject:specifier];

    [specifiers addObject:[self createButtonCellWithLabel:stringForKey(kOTHER_TWEAKS)
                                                 selector:@selector(myTweaks)]];
    [specifiers addObject:[self createButtonCellWithLabel:stringForKey(kFOLLOW_TWITTER)
                                                 selector:@selector(followTwitter)]];
    [specifiers addObject:[self createButtonCellWithLabel:stringForKey(kDISCORD_SERVER)
                                                 selector:@selector(discordServer)]];
    [specifiers addObject:[self createButtonCellWithLabel:[NSString stringWithFormat:stringForKey(kICON_BY), ICON_DESIGNER]
                                                 selector:@selector(iconCredits)]];
    [specifiers addObject:[self createButtonCellWithLabel:stringForKey(kEMAIL_ME)
                                                 selector:@selector(sendEmail)]];

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
    [specifier setProperty:RRSwitchTableCell.class forKey:kCellClass];
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
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
    [specifier setProperty:RRColorButtonCell.class forKey:kCellClass];

    if (selector) {
        specifier->action = selector;
    }
    return specifier;
}

- (PSSpecifier *)createGroupCellWithLabel:(NSString *)label
                               footerText:(NSString *)footerText {
    PSSpecifier *specifier = [PSSpecifier groupSpecifierWithName:label];
    if (footerText) {
        [specifier setProperty:footerText forKey:kFooterText];
        [specifier setProperty:@0 forKey:kFooterAlignment];
    }
    return specifier;
}

- (void)loadView {
    [super loadView];
    presentFollowAlert(kPrefPath, self);
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

- (void)sendEmail {
    openURL([NSURL URLWithString:@"mailto:andreaskhenriksson@gmail.com?subject=RoadRunner"]);
}

- (void)followTwitter {
    openTwitter();
}

- (void)myTweaks {
    openURL([NSURL URLWithString:@"https://henrikssonbrothers.com/cydia/repo/packages.html"]);
}

- (void)iconCredits {
    openTwitterWithUsername(ICON_DESIGNER);
}

- (void)discordServer {
    openURL([NSURL URLWithString:@"https://discord.gg/znn8wfw"]);
}

@end



@implementation RRSwitchTableCell

- (id)initWithStyle:(int)style reuseIdentifier:(id)identifier specifier:(id)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self)
        [((UISwitch *)[self control]) setOnTintColor:RRColor];
    return self;
}

@end


@implementation RRSettingsHeaderCell

- (id)initWithSpecifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kHeaderClass specifier:specifier];
    if (self) {
        _label = [[UILabel alloc] initWithFrame:[self frame]];
        [_label setTranslatesAutoresizingMaskIntoConstraints:NO];
        [_label setAdjustsFontSizeToFitWidth:YES];
        [_label setFont:[UIFont fontWithName:@"HelveticaNeue-UltraLight" size:48]];

        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:@"RoadRunner"];
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
    [self.textLabel setTextColor:RRColor];
}

@end
