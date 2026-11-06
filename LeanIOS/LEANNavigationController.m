//
//  LEANNavigationController.m
//  GoNativeIOS
//
//  Created by Weiyin He on 2/8/14.
//  Copyright (c) 2014 GoNative.io LLC. All rights reserved.
//

#import "LEANNavigationController.h"
#import "LEANWebViewController.h"
#import "LEANRootViewController.h"
#import "LEANUtilities.h"
@import MedianCoreKMP;

@interface LEANNavigationController () <UINavigationControllerDelegate>
@end

@implementation LEANNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // recognize swipe from left edge (nav2 toggles sidebarEnabled per resolved instance)
    if (MCKMPMutableConfig.shared.instance.showNavigationMenu || MCKMPMutableConfig.shared.instance.isNativeNavigationV2) {
        // D1: under nav2, stay disabled until the first applyNav2ForUrl: resolves an
        // active sidebar — an early edge-swipe would show the stale V1 menu otherwise
        self.sidebarEnabled = !MCKMPMutableConfig.shared.instance.isNativeNavigationV2;
        UIScreenEdgePanGestureRecognizer *r = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureRecognized:)];
        if ([UIView userInterfaceLayoutDirectionForSemanticContentAttribute:self.view.semanticContentAttribute] == UIUserInterfaceLayoutDirectionRightToLeft) {
            r.edges = UIRectEdgeRight;
        } else {
            r.edges = UIRectEdgeLeft;
        }
        [self.view addGestureRecognizer:r];
    } else {
        self.sidebarEnabled = NO;
    }
    
    self.delegate = self;
}

-(void)viewDidLayoutSubviews
{
    // theme and colors
    if ([MCKMPMutableConfig.shared.instance.configRoot.styling.iosTheme isEqualToString:@"dark"]) {
        self.navigationBar.barStyle = UIBarStyleBlack;
        self.view.backgroundColor = [UIColor blackColor];
    } else {
        self.navigationBar.barStyle = UIBarStyleDefault;
        
        if (@available(iOS 12.0, *)) {
            if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                self.view.backgroundColor = [UIColor blackColor];
            } else {
                self.view.backgroundColor = [UIColor whiteColor];
            }
        } else {
            self.view.backgroundColor = [UIColor whiteColor];
        }
    }
    
    UIColor *titleColor = [UIColor colorNamed:@"titleColor"];
    UIColor *navBarTintColor = [UIColor colorNamed:@"navigationBarTintColor"];
    NSDictionary *titleTextAttributes = @{NSForegroundColorAttributeName: titleColor};
    self.navigationBar.titleTextAttributes = titleTextAttributes;
    self.navigationBar.barTintColor = navBarTintColor;

    if (![LEANUtilities isGlassDesignEnabled] || !MCKMPMutableConfig.shared.instance.configRoot.styling.iosTransparentNavBar) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        [appearance setBackgroundColor:navBarTintColor];
        [appearance setTitleTextAttributes:titleTextAttributes];
        [self.navigationBar setStandardAppearance:appearance];
        [self.navigationBar setScrollEdgeAppearance:appearance];
    }
    
    [super viewDidLayoutSubviews];
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    UIViewController *wvc = self.visibleViewController;
    for (UIViewController *vc in self.viewControllers) {
        if ([vc isKindOfClass:[LEANWebViewController class]]) {
            wvc = vc;
        }
    }
    return wvc;
}

#pragma mark - UINavigationControllerDelegate
- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    if ([viewController isKindOfClass:[LEANWebViewController class]] && MCKMPMutableConfig.shared.instance.configRoot.styling.showToolbar) {
        [navigationController setToolbarHidden:NO animated:YES];
    }
    else {
        [navigationController setToolbarHidden:YES animated:YES];
    }
    
    
}

#pragma mark - Gesture recognizer

- (UIViewController *)rootWebViewController
{
    for (UIViewController *vc in self.viewControllers) {
        if ([vc isKindOfClass:[LEANWebViewController class]]) return vc;
    }
    return nil;
}

- (void)panGestureRecognized:(UIScreenEdgePanGestureRecognizer *)sender
{
    // the sidebar belongs to the root screen; pushed screens swipe back instead
    if (self.sidebarEnabled && self.topViewController == [self rootWebViewController]) {
        [self.frostedViewController panGestureRecognized:sender];
    }
}


@end
