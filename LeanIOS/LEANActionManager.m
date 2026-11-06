//
//  LEANActionManager.m
//  GoNativeIOS
//
//  Created by Weiyin He on 11/25/14.
//  Copyright (c) 2014 GoNative.io LLC. All rights reserved.
//

#import "LEANActionManager.h"
#import "LEANUtilities.h"
#import "GonativeIO-Swift.h"
@import MedianCoreKMP;

@implementation LEANActionButtons

- (instancetype)initWithLeftItems:(NSArray *)leftItems rightItems:(NSArray *)rightItems {
    self = [super init];
    if (self) {
        self.leftItems = leftItems;
        self.rightItems = rightItems;
    }
    return self;
}

@end

@interface LEANActionManager ()
@property NSMutableArray<UIBarButtonItem *> *items;
@property (weak, nonatomic) LEANWebViewController *wvc;
@property NSString *currentMenuID;
@property NSMutableArray *buttons;
@property NSMutableArray *actionsData;
@property (readwrite, assign) NSString *currentSearchTemplateUrl;
@property CustomMenu *menuView;
@property MCKMPTopNavComponent *nav2TopNav;
@end

@implementation LEANActionManager

- (instancetype)initWithWebviewController:(LEANWebViewController *)wvc
{
    self = [super init];
    if (self) {
        self.wvc = wvc;
    }
    return self;
}

- (void)didLoadUrl:(NSURL *)url {
    if (!url) {
        return;
    }
    if (MCKMPMutableConfig.shared.instance.isNativeNavigationV2) {
        // nav2: buttons come from the resolved instance via loadNav2TopNav:
        return;
    }

    NSString *urlString = [url absoluteString];

    MCKMPActionConfig *actionConfig = MCKMPMutableConfig.shared.instance.configRoot.navigation.actionConfig;
    NSArray<MCKMPActionSelectionRule *> *selectionRules = actionConfig.active ? actionConfig.actionSelection : @[];
    for (NSUInteger i = 0; i < selectionRules.count; i++) {
        MCKMPActionSelectionRule *actionSelection = selectionRules[i];
        @try {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", actionSelection.regex];
            if ([predicate evaluateWithObject:urlString]) {
                [self setMenuID:actionSelection.id];
                return;
            }
        }
        @catch (NSException* exception) {
            NSLog(@"Error in action regex: %@", exception);
        }
    }
    
    [self setMenuID:nil];
}

- (void)setMenuID:(NSString *)menuID
{
    if (![self.currentMenuID isEqualToString:menuID] && (self.currentMenuID != nil || menuID != nil)) {
        self.currentMenuID = menuID;
    }
    
    [self.wvc updateNavigationBarItemsAnimated:YES];
}

// nav2: store the resolved top bar component and refresh the buttons
- (void)loadNav2TopNav:(MCKMPTopNavComponent *)topNav {
    self.nav2TopNav = topNav;
    [self.wvc updateNavigationBarItemsAnimated:YES];
}

- (LEANActionButtons *)configureNavBarButtonsAllowingLeftAction:(BOOL)allowLeftAction {
    if (MCKMPMutableConfig.shared.instance.isNativeNavigationV2) {
        // nav2: MenuBarItems from the resolved instance; allowLeftMenu puts the first
        // item in the left slot when neither the hamburger nor a back button is there
        NSMutableArray *entries = [NSMutableArray array];
        if (self.nav2TopNav && self.nav2TopNav.active) {
            for (MCKMPMenuBarItem *item in self.nav2TopNav.items) {
                NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                entry[@"label"] = item.label;
                if (item.url) entry[@"url"] = item.url;
                if (item.icon) entry[@"icon"] = item.icon;
                if (item.system) entry[@"system"] = item.system;
                [entries addObject:entry];
            }
        }
        return [self buildButtonsFromActions:entries allowLeftAction:allowLeftAction allowLeftMenu:self.nav2TopNav.allowLeftMenu];
    }

    if (!self.currentMenuID) {
        self.items = nil;
        self.currentSearchTemplateUrl = nil;
        return [[LEANActionButtons alloc] initWithLeftItems:@[] rightItems:@[]];
    }

    MCKMPActionMenu *actionGroup = nil;
    for (MCKMPActionMenu *menuEntry in MCKMPMutableConfig.shared.instance.configRoot.navigation.actionConfig.actions) {
        if ([menuEntry.id isEqualToString:self.currentMenuID]) {
            actionGroup = menuEntry;
            break;
        }
    }
    NSData *actionItemsData = actionGroup ? [[actionGroup itemsJson] dataUsingEncoding:NSUTF8StringEncoding] : nil;
    NSArray *actions = actionItemsData ? [NSJSONSerialization JSONObjectWithData:actionItemsData options:0 error:nil] : nil;
    return [self buildButtonsFromActions:actions allowLeftAction:allowLeftAction allowLeftMenu:actionGroup.allowLeftMenu];
}

- (LEANActionButtons *)buildButtonsFromActions:(NSArray *)actions allowLeftAction:(BOOL)allowLeftAction allowLeftMenu:(BOOL)allowLeftMenu {
    self.items = [NSMutableArray array];
    self.buttons = [NSMutableArray array];
    self.actionsData = [NSMutableArray array];

    if (![actions isKindOfClass:[NSArray class]]) {
        return [[LEANActionButtons alloc] initWithLeftItems:@[] rightItems:@[]];
    }

    NSUInteger maxVisibleItems = 1;
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        maxVisibleItems = 4;
    }
    if (allowLeftAction && allowLeftMenu) {
        maxVisibleItems += 1;
    }
    
    NSArray *menu = actions;
    if (actions.count > maxVisibleItems + 1) {
        NSMutableArray *visibleItems = [NSMutableArray arrayWithArray:[actions subarrayWithRange:NSMakeRange(0, maxVisibleItems)]];
        [visibleItems addObject: @{
            @"label": NSLocalizedString(@"button-menu", nil),
            @"icon": @"md mi-more-vert",
            @"submenu": [actions subarrayWithRange:NSMakeRange(maxVisibleItems, actions.count - maxVisibleItems)]
        }];
        menu = visibleItems;
    }
    
    for (NSDictionary *entry in menu) {
        NSString *system = entry[@"system"];
        NSString *label = entry[@"label"];
        NSString *icon = entry[@"icon"];
        NSString *url = entry[@"url"];
        NSArray *submenu = entry[@"submenu"];
        
        [self.actionsData insertObject:@{ @"system": system ?: @"", @"url": url ?: @"" } atIndex:0];
        
        if ([system isKindOfClass:[NSString class]]) {
            if ([system isEqualToString:@"share"]) {
                [self createButtonWithIcon:icon defaultIcon:@"md mi-ios-share" label:label url:url menu:submenu];
                continue;
            }
            if ([system isEqualToString:@"refresh"]) {
                [self createButtonWithIcon:icon defaultIcon:@"fas fa-redo-alt" label:label url:url menu:submenu];
                continue;
            }
            if ([system isEqualToString:@"search"]) {
                [self createButtonWithIcon:icon defaultIcon:@"fas fa-search" label:label url:url menu:submenu];
                continue;
            }
        }
        
        [self createButtonWithIcon:icon defaultIcon:@"" label:label url:url menu:submenu];
    }
    
    NSArray *leftItems = @[];
    NSArray *rightItems = self.items;
    
    if (allowLeftAction && allowLeftMenu) {
        leftItems = self.items.count > 0 ? @[self.items.lastObject] : @[];
        rightItems = self.items.count > 1 ? [self.items subarrayWithRange:NSMakeRange(0, self.items.count - 1)] : @[];
    }
    
    return [[LEANActionButtons alloc] initWithLeftItems:leftItems rightItems:rightItems];
}

- (UIButton *)buttonWithIcon:(NSString *)icon {
    UIImage *iconImage = [LEANIcons imageForIconIdentifier:icon size:[self sizeForIcon:icon] color:[UIColor blackColor]];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:iconImage forState:UIControlStateNormal];
    [button setFrame:CGRectMake(0, 0, 30, 30)];
    button.tintColor = [UIColor colorNamed:@"titleColor"];
    return button;
}

- (void)createButtonWithIcon:(NSString *)icon defaultIcon:(NSString *)defaultIcon label:(NSString *)label url:(NSString *)url menu:(NSArray *)menu {
    if (defaultIcon && (![icon isKindOfClass:[NSString class]] || icon.length == 0)) {
        icon = defaultIcon;
    }
    
    UIButton *button = [self buttonWithIcon:icon];
    
    if ([menu isKindOfClass:[NSArray class]]) {
        objc_setAssociatedObject(button, "menu", menu, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addTarget:self action:@selector(openMenu:) forControlEvents:UIControlEventTouchUpInside];
    }
    else {
        [button addTarget:self action:@selector(itemWasSelected:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    UIBarButtonItem *buttonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
    [buttonItem setAccessibilityLabel:label];
    
    [self.items insertObject:buttonItem atIndex:0];
    [self.buttons insertObject:button atIndex:0];
}

- (UIBarButtonItem *)createNavBarButtonWithLabel:(NSString *)label icon:(NSString *)icon target:(id)target action:(SEL)action {
    UIButton *button = [self buttonWithIcon:icon];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *barButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
    barButtonItem.accessibilityLabel = label;
    return barButtonItem;
}

- (CGFloat)sizeForIcon:(NSString *)iconName {
    CGFloat size = [LEANUtilities isGlassDesignEnabled] ? 18 : 20;
    if ([iconName hasPrefix:@"custom "]) {
        size = size * 1.05;
    } else if ([iconName hasPrefix:@"md "]) {
        size = size * 1.2;
    }
    return size;
}

- (void)itemWasSelected:(id)sender {
    NSUInteger index = [self.buttons indexOfObject:sender];
    
    if (index == NSNotFound || index >= self.actionsData.count) {
        return;
    }
    
    NSDictionary *data = self.actionsData[index];
    NSString *system = data[@"system"];
    NSString *url = data[@"url"];
    
    [self handleAction:system url:url];
}

- (void)handleAction:(NSString *)system url:(NSString *)url {
    if ([system isKindOfClass:[NSString class]]) {
        if ([system isEqualToString:@"share"]) {
            [self.wvc sharePage:nil];
            return;
        }
        if ([system isEqualToString:@"refresh"]) {
            [self.wvc refreshPressed:nil];
            return;
        }
        if ([system isEqualToString:@"search"]) {
            if ([url isKindOfClass:[NSString class]]) {
                self.currentSearchTemplateUrl = url;
            } else {
                self.currentSearchTemplateUrl = @"";
            }
            [self.wvc searchPressed:nil];
            return;
        }
    }
    
    [self.wvc handleJsNavigationUrl:url];
}

- (void)openMenu:(id)sender {
    [self closeMenu];
    
    UIButton *button = (UIButton *)sender;
    NSArray *menu = objc_getAssociatedObject(sender, "menu");
    
    UIView *keyWindow = UIApplication.sharedApplication.currentKeyWindow;
    
    self.menuView = [[CustomMenu alloc] initWithContainer:keyWindow button:button data:menu onTap:^(NSDictionary *data) {
        [self closeMenu];
        
        NSString *system = data[@"system"];
        NSString *url = data[@"url"];
    
        [self handleAction:system url:url];
    }];
    
    [self.menuView setMenuColor:[UIColor colorNamed:@"navigationBarTintColor"]];
}

- (void)closeMenu {
    if (self.menuView) {
        [self.menuView removeFromSuperview];
        self.menuView = nil;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    // Close menu so the icons update their color
    [self closeMenu];
}

@end
