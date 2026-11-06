//
//  LEANAppDelegate.m
//  LeanIOS
//
//  Created by Weiyin He on 2/10/14.
// Copyright (c) 2014 GoNative.io LLC. All rights reserved.
//

#import "LEANAppDelegate.h"
#import "LEANWebViewIntercept.h"
#import "LEANUrlCache.h"
#import "LEANRootViewController.h"
#import "LEANConfigUpdater.h"
#import "LEANUtilities.h"
#import "LEANNotifications.h"
#import "LEANConfigObserver.h"
#import "GonativeIO-Swift.h"

@implementation LEANAppDelegate

@synthesize bridge;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // clear keychain item if this is first launch
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"hasLaunched"]) {
        [[NSUserDefaults standardUserDefaults] setValue:@YES forKey:@"hasLaunched"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        self.isFirstLaunch = YES;
    } else {
        self.isFirstLaunch = NO;
    }

    MCKMPMutableConfigState *config = MCKMPMutableConfig.shared.instance;

    // bridge config-change callbacks to legacy notifications
    [LEANConfigObserver install];

    // Register launch
    [LEANConfigUpdater registerEvent:@"launch" data:nil];

    // proxy handler to intercept HTML for custom CSS and viewport
    [LEANWebViewIntercept register];

    // listen for reachability
    self.internetReachability = [Reachability reachabilityForInternetConnection];
    [self.internetReachability startNotifier];

    // disable sleep if requested
    if (config.configRoot.general.keepScreenOn) {
        application.idleTimerDisabled = YES;
    }

    self.bridge = [[MCKMPViewControllerHost alloc] initWithRegistry:MCKMPPluginRegistry.shared];

    [bridge applicationDidFinishLaunchingApplication:application launchOptions:launchOptions];

    return YES;
}

- (void)configureApplication
{
    self.window.tintColor = [UIColor colorNamed:@"tintColor"];
}

-(void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    NSLog(@"Successfully registered for push notifications");
    [self setApnsToken:[GNSwiftUtilities deviceTokenWithData:deviceToken]];
    [self.bridge applicationDidRegisterForRemoteNotificationsApplication:application deviceToken:deviceToken];
}

- (void)application:(UIApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)err {
    NSLog(@"Error registering for push notifications: %@", err);
    [self setApnsToken:nil];
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application
  supportedInterfaceOrientationsForWindow:(UIWindow *)window
{
    if (![window.rootViewController isKindOfClass:[LEANRootViewController class]]) {
        // likely to be a full-screen video. Allow all orientations.
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }

    // default implementation, use what the Info.plist specifies
    return [application supportedInterfaceOrientationsForWindow:window];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    [bridge applicationWillTerminateApplication:application];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    [bridge applicationDidReceiveRemoteNotificationApplication:application userInfo:userInfo];
}

@end
