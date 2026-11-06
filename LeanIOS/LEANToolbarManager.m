//
//  LEANToolbarManager.m
//  GoNativeIOS
//
//  Created by Weiyin He on 5/20/15.
//  Copyright (c) 2015 GoNative.io LLC. All rights reserved.
//

#import "LEANToolbarManager.h"
#import "LEANWebViewController.h"
#import "LEANUtilities.h"
#import "GonativeIO-Swift.h"
@import MedianCoreKMP;

// Local replacement for GoNativeCore's RegexEnabled
@interface LEANRegexEnabled : NSObject
@property NSPredicate *regex;
@property BOOL enabled;
@end
@implementation LEANRegexEnabled
@end

@interface LEANToolbarItem : NSObject
@property BOOL enabled;
@property NSArray<LEANRegexEnabled *> *regexes;
@property NSString *visibility;
@property UIBarButtonItem *item;
@end

@implementation LEANToolbarItem
@end

@interface LEANToolbarManager()
@property (weak, nonatomic) LEANWebViewController *wvc;
@property UIToolbar *toolbar;
@property LEANToolbarItem *backButton;
@property LEANToolbarItem *refreshButton;
@property LEANToolbarItem *forwardButton;
@property MCKMPToolbarComponent *nav2Component;
@property BOOL nav2ToolbarNeedsBack;
@end

@implementation LEANToolbarManager

- (instancetype)initWithToolbar:(UIToolbar*)toolbar heightConstraint:(NSLayoutConstraint *)heightConstraint wvc:(LEANWebViewController*)wvc {
    self = [super init];
    if (self) {
        self.toolbar = toolbar;
        
        if ([LEANUtilities isGlassDesignEnabled]) {
            heightConstraint.constant = 60;
        }
        
        self.wvc = wvc;
        [self processConfig];

    }
    return self;
}

- (void)processConfig {
    NSMutableArray *toolbarItems = [NSMutableArray array];
    
    // initialize buttons
    self.backButton = [[LEANToolbarItem alloc] init];
    self.forwardButton = [[LEANToolbarItem alloc] init];
    self.refreshButton = [[LEANToolbarItem alloc] init];
    
    NSString *defaultBackButtonText = NSLocalizedString(@"button-back", nil);
    NSString *defaultForwardButtonText = NSLocalizedString(@"button-forward", nil);
    
    self.backButton.item = [self createButtonWithTitle:defaultBackButtonText forButton:@"Back" andIcon:@"fas fa-chevron-left"];
    self.refreshButton.item = [self createButtonWithTitle:nil forButton:@"Refresh" andIcon:@"fas fa-redo-alt"];
    self.forwardButton.item = [self createButtonWithTitle:defaultForwardButtonText forButton:@"Forward" andIcon:@"fas fa-chevron-right"];
    
    self.backButton.enabled = NO;
    self.refreshButton.enabled = NO;
    self.forwardButton.enabled = NO;
    
    // loop through items from appConfig
    MCKMPToolbarNavigationConfig *toolbarNav = MCKMPMutableConfig.shared.instance.configRoot.navigation.toolbarNavigation;
    NSData *itemsData = [[toolbarNav itemsJson] dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *toolbarConfigItems = itemsData ? [NSJSONSerialization JSONObjectWithData:itemsData options:0 error:nil] : nil;
    if ([toolbarConfigItems isKindOfClass:[NSArray class]]) {
        for (NSDictionary *entry in toolbarConfigItems) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            
            NSString *system = entry[@"system"];
            NSString *visibility = entry[@"visibility"];
            BOOL enabled = NO;
            if ([entry[@"enabled"] isKindOfClass:[NSNumber class]]) {
                enabled = [entry[@"enabled"] boolValue];
            }

            if ([system isEqualToString:@"back"]) {
                NSString *title = [self getLabelUsingEntry:entry defaultLabel:defaultBackButtonText];
                self.backButton.item = [self createButtonWithTitle:title forButton:@"Back" andIcon:@"fas fa-chevron-left"];
                self.backButton.enabled = YES;
                self.backButton.regexes = [self getRegexesFromQuery:entry[@"urlRegex"]];
                self.backButton.visibility = visibility;
            }
            else if([system isEqualToString:@"refresh"]){
                self.refreshButton.enabled = enabled;
                self.refreshButton.regexes = [self getRegexesFromQuery:entry[@"urlRegex"]];
                self.refreshButton.visibility = visibility;
            }
            else if ([system isEqualToString:@"forward"]){
                NSString *title = [self getLabelUsingEntry:entry defaultLabel:defaultForwardButtonText];
                self.forwardButton.item = [self createButtonWithTitle:title forButton:@"Forward" andIcon:@"fas fa-chevron-right"];
                self.forwardButton.enabled = enabled;
                self.forwardButton.regexes = [self getRegexesFromQuery:entry[@"urlRegex"]];
                self.forwardButton.visibility = visibility;
            }
        }
    }
    
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *fixed = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    toolbarItems = [NSMutableArray arrayWithObjects:self.backButton.item, space, self.refreshButton.item, space, self.forwardButton.item, nil];
    
    if ([LEANUtilities isGlassDesignEnabled]) {
        if (!self.refreshButton.enabled) {
            [toolbarItems replaceObjectAtIndex:2 withObject:fixed];
        }
        
        if (!self.forwardButton.enabled) {
            [toolbarItems replaceObjectAtIndex:4 withObject:fixed];
        }
    }
    
    [self.toolbar setItems:toolbarItems animated:YES];
}

- (UIBarButtonItem *)createButtonWithTitle:(NSString *)title forButton:(NSString *)buttonType andIcon:(NSString *)icon {
    CGFloat imageSize = [LEANUtilities isGlassDesignEnabled] ? 20 : 24;
    UIImage *image = [LEANIcons imageForIconIdentifier:icon size:imageSize color:[UIColor colorNamed:@"tintColor"]];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:image forState:UIControlStateNormal];
    
    SEL action = @selector(refreshPressed:);
    if ([buttonType isEqualToString:@"Back"]) {
        action = @selector(backPressed:);
    } else if ([buttonType isEqualToString:@"Forward"]) {
        action = @selector(forwardPressed:);
        [button setSemanticContentAttribute:UISemanticContentAttributeForceRightToLeft];
    }
    
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    
    if ([LEANUtilities isGlassDesignEnabled]) {
        UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:image style:UIBarButtonItemStylePlain target:self action:action];
        return item;
    }
    
    if (title) {
        [button setTitle:title forState:UIControlStateNormal];
        [[button titleLabel] setFont:[UIFont systemFontOfSize:18]];
        [button setTitleColor:[UIColor colorNamed:@"tintColor"] forState:UIControlStateNormal];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        button.titleLabel.minimumScaleFactor = 0.7;
    }
    
    button.alpha = 0;
    button.enabled = NO;
    
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)backPressed:(id)sender
{
    if ([self.wvc canGoBack]) {
        [self.wvc goBack];
    } else if (self.wvc.navigationController.viewControllers.count >= 2) {
        [self.wvc.navigationController popViewControllerAnimated:YES];
    }
}

- (void)forwardPressed:(id)sender
{
    [self.wvc goForward];
}

- (void)refreshPressed:(id)sender
{
    [self.wvc refreshPage];
}

- (NSString *)getLabelUsingEntry:(NSDictionary *)entry defaultLabel:(NSString *)defaultLabel {
    NSString *titleType = entry[@"titleType"];
    if ([titleType isKindOfClass:[NSString class]]) {
        if ([titleType isEqualToString:@"noText"]) {
            return @"";
        }
        if ([titleType isEqualToString:@"customText"]) {
            NSString *title = entry[@"title"];
            if ([title isKindOfClass:[NSString class]]) {
                return title;
            }
            return @"";
        }
    }
    return defaultLabel;
}

- (NSArray *)getRegexesFromQuery:(NSArray *)query {
    NSMutableArray *regexes = [NSMutableArray array];
    if ([query isKindOfClass:[NSArray class]]) {
        for (NSDictionary *entry in query) {
            if ([entry[@"regex"] isKindOfClass:[NSString class]] &&
                [entry[@"enabled"] isKindOfClass:[NSNumber class]]) {
                
                LEANRegexEnabled *item = [[LEANRegexEnabled alloc] init];
                item.regex = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", entry[@"regex"]];
                item.enabled = [entry[@"enabled"] boolValue];
                [regexes addObject:item];
            }
        }
    }
    return regexes;
}

// nav2: ToolbarItems (system back/forward/refresh) from the resolved instance. The buttons are
// applied even when the instance's toolbar is off, so the JavaScript bridge shows its own buttons.
- (void)didLoadNav2Url:(NSURL *)url component:(MCKMPToolbarComponent *)component
{
    [self applyNav2Component:component];
    if (!component || !component.active) {
        [self.wvc hideToolbarAnimated:YES];
        return;
    }
    [self updateToolbarButtonsRequiringBack:self.nav2ToolbarNeedsBack];
}

- (void)applyNav2Component:(MCKMPToolbarComponent *)component {
    if ([self.nav2Component isEqual:component]) return;
    self.nav2Component = component;

    self.backButton.enabled = NO;
    self.refreshButton.enabled = NO;
    self.forwardButton.enabled = NO;
    self.backButton.regexes = nil;
    self.refreshButton.regexes = nil;
    self.forwardButton.regexes = nil;
    self.backButton.visibility = nil;
    self.refreshButton.visibility = nil;
    self.forwardButton.visibility = nil;

    // Every button starts hidden and the instance's items switch them on: back is always shown,
    // forward and refresh only when switched on. The back button's visibility applies to the
    // whole toolbar: unless it is "always", a page load shows the toolbar only when the user can
    // go back.
    self.backButton.item = [self createButtonWithTitle:NSLocalizedString(@"button-back", nil) forButton:@"Back" andIcon:@"fas fa-chevron-left"];
    self.refreshButton.item = [self createButtonWithTitle:nil forButton:@"Refresh" andIcon:@"fas fa-redo-alt"];
    self.forwardButton.item = [self createButtonWithTitle:NSLocalizedString(@"button-forward", nil) forButton:@"Forward" andIcon:@"fas fa-chevron-right"];
    self.nav2ToolbarNeedsBack = YES;
    for (MCKMPToolbarItem *item in component.items) {
        if ([item.system isEqualToString:@"back"]) {
            self.backButton.item = [self createButtonWithTitle:[self nav2TitleForItem:item defaultLabel:NSLocalizedString(@"button-back", nil)] forButton:@"Back" andIcon:@"fas fa-chevron-left"];
            self.backButton.enabled = YES;
            self.nav2ToolbarNeedsBack = ![item.visibility isEqualToString:@"always"];
        }
        else if ([item.system isEqualToString:@"refresh"]) {
            self.refreshButton.enabled = item.enabled;
        }
        else if ([item.system isEqualToString:@"forward"]) {
            self.forwardButton.item = [self createButtonWithTitle:[self nav2TitleForItem:item defaultLabel:NSLocalizedString(@"button-forward", nil)] forButton:@"Forward" andIcon:@"fas fa-chevron-right"];
            self.forwardButton.enabled = item.enabled;
        }
    }

    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *fixed = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    NSMutableArray *toolbarItems = [NSMutableArray arrayWithObjects:self.backButton.item, space, self.refreshButton.item, space, self.forwardButton.item, nil];

    if ([LEANUtilities isGlassDesignEnabled]) {
        if (!self.backButton.enabled) {
            [toolbarItems replaceObjectAtIndex:0 withObject:fixed];
        }
        if (!self.refreshButton.enabled) {
            [toolbarItems replaceObjectAtIndex:2 withObject:fixed];
        }
        if (!self.forwardButton.enabled) {
            [toolbarItems replaceObjectAtIndex:4 withObject:fixed];
        }
    }

    [self.toolbar setItems:toolbarItems animated:YES];
}

- (NSString *)nav2TitleForItem:(MCKMPToolbarItem *)item defaultLabel:(NSString *)defaultLabel {
    if ([item.titleType isEqualToString:@"customText"]) {
        return item.title ?: @"";
    }
    if ([item.titleType isEqualToString:@"defaultText"]) {
        return defaultLabel;
    }
    return @""; // "noText" (default)
}

- (void)didLoadUrl:(NSURL*)url
{
    if (MCKMPMutableConfig.shared.instance.isNativeNavigationV2) {
        // canGoBack/canGoForward KVO path; the component was applied by didLoadNav2Url
        if (self.nav2Component && self.nav2Component.active) {
            [self updateToolbarButtonsRequiringBack:self.nav2ToolbarNeedsBack];
        } else {
            [self.wvc hideToolbarAnimated:YES];
        }
        return;
    }

    MCKMPToolbarNavigationConfig *toolbarNav = MCKMPMutableConfig.shared.instance.configRoot.navigation.toolbarNavigation;
    BOOL toolbarEnabled = toolbarNav ? toolbarNav.enabled : YES;
    if (!toolbarEnabled) {
        BOOL toolbarVisible = [self tryToShowBackButton:url];
        if (toolbarVisible) {
            [self.wvc showToolbarAnimated:YES];
        } else {
            [self.wvc hideToolbarAnimated:YES];
        }
        return;
    }
    
    // 1. Check visibilityByPages
    // 2. Check if back button is active
    // 3. Check visibilityByBackButton
    // 4. Check if refresh button is active
    // 5. Check if forward button is active
    // 6. 1 && 3 && (2 || 4 || 5)
    
    NSString *urlString = [url absoluteString];
    
    BOOL visibilityByPages = YES;
    BOOL visibilityByBackButton = YES;
    
    // Check visibilityByPages
    // if specific pages only
    if ([toolbarNav.visibilityByPages isEqualToString:@"specificPages"]) {
        NSMutableArray *pageRegexes = [NSMutableArray array];
        for (MCKMPToolbarRegexRule *rule in toolbarNav.regexes) {
            LEANRegexEnabled *item = [[LEANRegexEnabled alloc] init];
            item.regex = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", rule.regex];
            item.enabled = rule.enabled;
            [pageRegexes addObject:item];
        }
        visibilityByPages = [self evaluateUrlString:urlString usingRegexes:pageRegexes];
    }
    
    // Update back button
    BOOL backEnabled = [self tryToShowBackButton:url];
    if (!backEnabled) {
        backEnabled = [self checkToolbarItem:self.backButton forUrl:urlString enabled:[self canGoBack]];
    }
    
    // Check visibilityByBackButton
    // if back button active only
    if (![toolbarNav.visibilityByBackButton isEqualToString:@"always"]) {
        visibilityByBackButton = backEnabled;
    }
    
    // Update forward button
    BOOL forwardEnabled = [self checkToolbarItem:self.forwardButton forUrl:urlString enabled:[self.wvc canGoForward]];
    
    // Update refresh button
    BOOL refreshEnabled = [self checkToolbarItem:self.refreshButton forUrl:urlString enabled:YES];
    
    BOOL toolbarVisible = visibilityByPages && visibilityByBackButton && (backEnabled || forwardEnabled || refreshEnabled);
    if (toolbarVisible) {
        [self.wvc showToolbarAnimated:YES];
    } else {
        [self.wvc hideToolbarAnimated:YES];
    }
}

- (BOOL)canGoBack {
    return [self.wvc canGoBack] || self.wvc != self.wvc.navigationController.viewControllers.firstObject;
}

- (BOOL)tryToShowBackButton:(NSURL *)url {
    if (![self canGoBack]) return NO;
    
    if ([self.urlMimeType hasPrefix:@"image/"]) {
        [self setToolbarItem:self.backButton enabled:YES];
        return YES;
    }
    
    return NO;
}

- (BOOL)checkToolbarItem:(LEANToolbarItem *)toolbarItem forUrl:(NSString *)urlString enabled:(BOOL)enabled {
    if (!toolbarItem.enabled) {
        return NO;
    }
    
    if (!enabled) {
        [self setToolbarItem:toolbarItem enabled:NO];
        return NO;
    }
    
    if (![toolbarItem.visibility isEqualToString:@"specificPages"]) {
        [self setToolbarItem:toolbarItem enabled:YES];
        return YES;
    }
        
    BOOL value = [self evaluateUrlString:urlString usingRegexes:toolbarItem.regexes];
    [self setToolbarItem:toolbarItem enabled:value];
    return value;
}

- (void)setToolbarItem:(LEANToolbarItem *)toolbarItem enabled:(BOOL)enabled {
    // design the button "disabled"
    toolbarItem.item.enabled = enabled;
    toolbarItem.item.customView.alpha = enabled ? 1 : 0.3;
}

- (BOOL)evaluateUrlString:(NSString *)urlString usingRegexes:(NSArray *)regexes {
    for (LEANRegexEnabled *regexObject in regexes) {
        @try {
            BOOL matches = [regexObject.regex evaluateWithObject:urlString];
            if (matches) return regexObject.enabled;
        }
        @catch (NSException* exception) {
            NSLog(@"Error in toolbar regexes: %@", exception);
        }
    }
    return NO;
}

- (void)updateToolbarButtons {
    [self updateToolbarButtonsRequiringBack:NO];
}

// requireBack: show the toolbar only when the user can go back.
- (void)updateToolbarButtonsRequiringBack:(BOOL)requireBack {
    BOOL backEnabled = NO;
    if (self.backButton.enabled) {
        backEnabled = [self canGoBack];
        [self setToolbarItem:self.backButton enabled:backEnabled];
    }
    
    BOOL forwardEnabled = NO;
    if (self.forwardButton.enabled) {
        forwardEnabled = [self.wvc canGoForward];
        [self setToolbarItem:self.forwardButton enabled:forwardEnabled];
    }
    
    BOOL refreshEnabled = self.refreshButton.enabled;
    if (self.refreshButton.enabled) {
        [self setToolbarItem:self.refreshButton enabled:YES];
    }
    
    if ((!requireBack || backEnabled) && (backEnabled || forwardEnabled || refreshEnabled)) {
        [self.wvc showToolbarAnimated:YES];
    } else {
        [self.wvc hideToolbarAnimated:YES];
    }
}

- (void)setToolbarEnabled:(BOOL)enabled {
    if (!enabled) {
        [self.wvc hideToolbarAnimated:YES];
    } else {
        [self updateToolbarButtons];
    }
}

- (void)handleUrl:(NSURL *)url query:(NSDictionary *)query {
    if ([url.path isEqualToString:@"/contextualNavToolbar/set"]) {
        [self setToolbarEnabled:[query[@"enabled"] boolValue]];
    }
    return;
}

@end
