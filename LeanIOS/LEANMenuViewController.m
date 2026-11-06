//
//  LEANMenuViewController.m
//  GoNativeIOS
//
//  Created by Weiyin He on 2/7/14.
//  Copyright (c) 2014 GoNative.io LLC. All rights reserved.
//

#import "LEANMenuViewController.h"
#import "LEANNavigationController.h"
#import "LEANWebViewController.h"
#import "LEANRootViewController.h"
#import "LEANUrlInspector.h"
#import "LEANTabManager.h"
#import "LEANUtilities.h"
#import "LEANNotifications.h"
#import "GonativeIO-Swift.h"
@import MedianIcons;
@import MedianCoreKMP;

@interface LEANMenuViewController ()

@property NSArray<MCKMPMenuItem *> *menuItems;
@property NSArray<MCKMPMenuItem *> *nav2Items; // nav2: overrides config sidebarMenus when set
@property NSMutableArray *groupExpanded;

@property LEANWebViewController *wvc;

@property UIImage *collapsedIndicator;
@property UIImage *expandedIndicator;

@property UIView *headerView;

@property BOOL groupsHaveIcons;
@property BOOL childrenHaveIcons;
@property NSString *lastUpdatedStatus;

@end

@implementation LEANMenuViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.opaque = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.sectionHeaderHeight = 0;
    self.tableView.sectionFooterHeight = 0;
    
    NSArray *arr = [[NSBundle mainBundle] loadNibNamed:@"SidebarHeaderView" owner:nil options:nil];

    UIView *headerView = arr[0];
    self.headerView = headerView;
    headerView.autoresizingMask = UIViewAutoresizingNone;
    UIButton *headerButton = (UIButton*)[headerView viewWithTag:1];
    [headerButton addTarget:self action:@selector(picturePressed:) forControlEvents:UIControlEventTouchUpInside];

    // segmented control dropped (legacy); hide the nib view
    [headerView viewWithTag:3].hidden = YES;

    self.tableView.tableHeaderView = headerView;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    
    // actually update the menus
    [self updateMenuWithStatus:@"default"];

    // pre-load images. Color them too.
    self.collapsedIndicator = [[UIImage imageNamed:@"chevronDown"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.expandedIndicator = [[UIImage imageNamed:@"chevronUp"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:kLEANAppConfigNotificationProcessedMenu object:nil];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveNotification:(NSNotification*)notification
{
    // dynamic menu update
    if ([[notification name] isEqualToString:kLEANAppConfigNotificationProcessedMenu]) {
        [self updateMenuWithStatus:self.lastUpdatedStatus];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // webviewcontroller reference
    LEANNavigationController* nav = (LEANNavigationController*)self.frostedViewController.contentViewController;
    self.wvc = (LEANWebViewController*)nav.viewControllers[0];
}

// nav2: items from the resolved instance; the existing table machinery renders them
- (void)setNav2MenuItems:(NSArray<MCKMPMenuItem *> *)items
{
    if ([self.nav2Items isEqualToArray:items]) return;
    self.nav2Items = items;
    [self updateMenuWithStatus:self.lastUpdatedStatus];
}

- (void)updateMenuWithStatus:(NSString *)status
{
    if (!status) status = @"default";

    self.lastUpdatedStatus = status;

    self.menuItems = self.nav2Items ?: MCKMPMutableConfig.shared.instance.sidebarMenus;

    // see if any menu items have icons. Used for layout indentation.
    self.groupsHaveIcons = NO;
    self.childrenHaveIcons = NO;
    for (MCKMPMenuItem *item in self.menuItems) {
        if (item.icon.length > 0) {
            self.groupsHaveIcons = YES;
        }

        if (item.isGrouping) {
            for (MCKMPMenuItem *sublink in item.subLinks) {
                if (sublink.icon.length > 0) {
                    self.childrenHaveIcons = YES;
                    break;
                }
            }
        }
    }
    
    // groups are initially collapsed
    self.groupExpanded = [[NSMutableArray alloc] initWithCapacity:[self.menuItems count]];
    for (int i = 0; i < [self.menuItems count]; i++) {
        self.groupExpanded[i] = [NSNumber numberWithBool:NO];
    }
    
    [self.tableView reloadData];
}

- (void)logOut
{
    [self.wvc logout];
    [self updateMenuWithStatus:@"default"];
}

- (IBAction)picturePressed:(id)sender {
    [self.wvc loadUrl:[NSURL URLWithString:MCKMPMutableConfig.shared.instance.initialUrl]];
    [self.frostedViewController hideMenuViewController];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self.menuItems count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([self.groupExpanded[section] boolValue]) {
        return 1 + self.menuItems[section].subLinks.count;
    }
    else
        return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *cellNib;
    UITableViewCell *cell;
    UIImageView *imageView;
    UILabel *label;
    if (indexPath.row == 0) {
        if (self.groupsHaveIcons) cellNib = @"MenuGroupIcon";
        else cellNib = @"MenuGroupNoIcon";
    } else {
        if (self.groupsHaveIcons || self.childrenHaveIcons) cellNib = @"MenuChildIcon";
        else cellNib = @"MenuChildNoIcon";
    }
    
    cell = [tableView dequeueReusableCellWithIdentifier:cellNib];
    if (nil == cell) {
        cell = [[NSBundle mainBundle] loadNibNamed:cellNib owner:nil options:nil][0];
        cell.backgroundColor = [UIColor clearColor]; // shouldn't need this, but background is white on ipad if I don't do this.
        UIView* separatorLineView = [[UIView alloc] initWithFrame:CGRectMake(15, 0, 240, 1)];
        separatorLineView.backgroundColor = [UIColor colorWithHue:0 saturation:0 brightness:.7 alpha:.5];
        separatorLineView.tag = 99;
        [cell addSubview:separatorLineView];
    }
    
    label = (UILabel*)[cell.contentView viewWithTag:1];
    imageView = (UIImageView*)[cell.contentView viewWithTag:2];
    
    // get data
    MCKMPMenuItem *menuItem;
    if (indexPath.row == 0) {
        menuItem = self.menuItems[indexPath.section];
    } else {
        menuItem = self.menuItems[indexPath.section].subLinks[indexPath.row - 1];
    }

    // text
    label.text = [menuItem.label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *sidebarFont = MCKMPMutableConfig.shared.instance.navDefaultStyles.sidebarNavigationBar.styling.ios.sidebarFont;
    if (sidebarFont.length > 0) {
        UIFont *font = [UIFont fontWithName:sidebarFont size:label.font.pointSize];
        if (font) label.font = font;
    }

    // expand/collapse indicator
    if (menuItem.isGrouping) {
        if ([self.groupExpanded[indexPath.section] boolValue]) {
            cell.accessoryView = [[UIImageView alloc] initWithImage:self.expandedIndicator];
        } else {
            cell.accessoryView = [[UIImageView alloc] initWithImage:self.collapsedIndicator];
        }
    } else
        cell.accessoryView = nil;
    
    // icon
    UILabel *icon;
    NSString *iconName = menuItem.icon;
    if (iconName.length > 0) {
        if ([iconName hasPrefix:@"gonative-"]) {
            UIImage *image = [UIImage imageNamed:iconName];
            imageView.image = image;
        } else {
            // add fontawesome/material/custom icon to imageView
            icon = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, imageView.bounds.size.width, imageView.bounds.size.height)];
            icon.textAlignment = NSTextAlignmentCenter;
            icon.attributedText = [[NSAttributedString alloc] initWithIconName:iconName color:[UIColor colorNamed:@"sidebarTextColor"] size:[UIFont systemFontSize]];
            [imageView addSubview:icon];
        }
    } else {
        imageView.image = nil;
        [[imageView subviews]
         makeObjectsPerformSelector:@selector(removeFromSuperview)];
    }
                           
    // configure background color
    self.view.backgroundColor = [UIColor colorNamed:@"sidebarBackgroundColor"];
    
    // configure text color
    UIColor *sidebarTextColor = [UIColor colorNamed:@"sidebarTextColor"];
    label.textColor = sidebarTextColor;
    cell.tintColor = sidebarTextColor;
    
    // hide separator line from first cell
    if (indexPath.section == 0 && indexPath.row == 0) {
        [cell viewWithTag:99].hidden = YES;
    } else {
        [cell viewWithTag:99].hidden = NO;
    }
    
    return cell;
}

#pragma mark - Table view delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *url = nil;
    BOOL isLogout;
    
    // if is first row, then check if it is grouped.
    if (indexPath.row == 0) {
        if (self.menuItems[indexPath.section].isGrouping) {
            self.groupExpanded[indexPath.section] = [NSNumber numberWithBool:![self.groupExpanded[indexPath.section] boolValue]];
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else {
            MCKMPMenuItem *item = self.menuItems[indexPath.section];
            url = item.url;
            isLogout = item.isLogout;
        }
    } else {
        // regular child
        MCKMPMenuItem *item = self.menuItems[indexPath.section].subLinks[indexPath.row - 1];
        url = item.url;
        isLogout = item.isLogout;
    }
    
    if (url == nil) {
        return;
    }
    
    // check for GONATIVE_USERID string.
    url = [url stringByReplacingOccurrencesOfString:@"GONATIVE_USERID" withString:[LEANUrlInspector sharedInspector].userId];
    [self.wvc handleJsNavigationUrl:url];
    
    if (![url hasPrefix:@"javascript:"] && MCKMPMutableConfig.shared.instance.configRoot.general.injectMedianJS) {
        [self.wvc.tabManager selectTabWithUrl:url];
        
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            [self.wvc setSharePopOverRect:[tableView rectForRowAtIndexPath:indexPath]];
        }
    }
    
    [self.frostedViewController hideMenuViewController];
    
    if (isLogout) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.wvc logout];
        });
    }
}

@end


