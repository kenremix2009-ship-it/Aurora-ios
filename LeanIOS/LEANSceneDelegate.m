//
//  LEANSceneDelegate.m
//  MedianIOS
//
//  Created by Kevin Mercado on 10/1/26.
//  Copyright © 2026 GoNative.io. All rights reserved.
//

#import "LEANSceneDelegate.h"
#import "LEANRootViewController.h"
#import "LEANNotifications.h"
#import "GNConfigPreferences.h"
#import <AppTrackingTransparency/ATTrackingManager.h>

@implementation LEANSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    self.appDelegate = (LEANAppDelegate *)UIApplication.sharedApplication.delegate;

    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController *rvc = [storyboard instantiateInitialViewController];
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];

    window.rootViewController = rvc;
    self.window = window;
    self.appDelegate.window = window;

    [self.appDelegate configureApplication];
    [self.appDelegate.bridge sceneWillConnectScene:scene session:session connectionOptions:connectionOptions];

    [window makeKeyAndVisible];

    NSURL *launchDeeplink = nil;
    NSUserActivity *activity = connectionOptions.userActivities.anyObject;
    if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && activity.webpageURL) {
        launchDeeplink = activity.webpageURL;
    }
    UIOpenURLContext *urlContext = connectionOptions.URLContexts.anyObject;
    if (!launchDeeplink && urlContext) {
        launchDeeplink = urlContext.URL;
    }
    if (launchDeeplink && [MCKMPMutableConfig.shared.instance applyLaunchDeeplinkDeeplinkUrl:launchDeeplink.absoluteString]) {
        return;
    }

    for (NSUserActivity *userActivity in connectionOptions.userActivities) {
        [self scene:scene continueUserActivity:userActivity];
    }
    if (urlContext) {
        [self scene:scene openURLContexts:[NSSet setWithObject:urlContext]];
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    for (UIOpenURLContext *context in URLContexts) {
        [self scene:scene openURLContext:context];
    }
}

- (void)scene:(UIScene *)scene openURLContext:(UIOpenURLContext *)context {
    if ([self.appDelegate.bridge sceneOpenURLContextScene:scene context:context]) {
        return;
    }

    NSURL *url = context.URL;
    if (![url.scheme hasSuffix:@".https"] && ![url.scheme hasSuffix:@".http"]) {
        return;
    }

    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    components.scheme = [url.scheme hasSuffix:@".https"] ? @"https" : @"http";

    UIViewController *rvc = self.window.rootViewController;
    dispatch_async(dispatch_get_main_queue(), ^{
        [(LEANRootViewController *)rvc handleJsNavigationUrl:components.URL.absoluteString];
    });
}

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity {
    if ([self.appDelegate.bridge sceneContinueUserActivityScene:scene userActivity:userActivity]) {
        return;
    }

    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        UIViewController *rvc = self.window.rootViewController;
        if ([rvc isKindOfClass:[LEANRootViewController class]] && userActivity.webpageURL) {
            [(LEANRootViewController *)rvc handleDeeplinkUrl:userActivity.webpageURL];
        }
    }
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    MCKMPMutableConfigState *config = MCKMPMutableConfig.shared.instance;
    if (config.loadError) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *message = @"Invalid appConfig json";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"button-ok", @"Button: OK") style:UIAlertActionStyleCancel handler:nil]];
            LEANRootViewController *rvc = (LEANRootViewController*) self.window.rootViewController;
            [rvc presentAlert:alert];
        });
    }

    [self.appDelegate.bridge sceneDidBecomeActiveScene:scene];

    if (self.appDelegate.previousInitialUrl) {
        NSString *initialUrl = [[GNConfigPreferences sharedPreferences] getInitialUrl];
        if (![self.appDelegate.previousInitialUrl isEqualToString:initialUrl]) {
            UIViewController *rvc = self.window.rootViewController;
            if ([rvc isKindOfClass:[LEANRootViewController class]]) {
                LEANRootViewController *vc = (LEANRootViewController*)rvc;
                if (initialUrl && initialUrl.length > 0) {
                    [vc loadUrl:[NSURL URLWithString:initialUrl]];
                } else {
                    [vc loadUrl:[NSURL URLWithString:config.initialUrl]];
                }
                self.appDelegate.previousInitialUrl = initialUrl;
            }
        }
    }

    BOOL wantsATT = config.configRoot.permissions.iOSRequestATTConsentOnLoad || config.configRoot.services.facebook.active;
    if ([self hasTrackingDescription] && wantsATT) {
        if (@available(iOS 14.5, *)) {
            [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kLEANAppConfigNotificationAppTrackingStatusChanged object:nil];
            }];
        }
    }
}

- (void)sceneWillResignActive:(UIScene *)scene {
    [self.appDelegate.bridge sceneWillResignActiveScene:scene];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    [self.appDelegate.bridge sceneDidEnterBackgroundScene:scene];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    if (![self.appDelegate.bridge sceneWillEnterForegroundScene:scene]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *rvc = self.window.rootViewController;
        if ([rvc isKindOfClass:[LEANRootViewController class]]) {
            if (MCKMPMutableConfig.shared.instance.configRoot.general.injectMedianJS) {
                [(LEANRootViewController *)rvc runJavascriptWithCallback:@[@"median_app_resumed", @"gonative_app_resumed"] data:nil];
            } else {
                [(LEANRootViewController *)rvc runJavascriptWithCallback:@"_median_app_resumed" data:nil];
            }
        }
    });
}

- (BOOL)hasTrackingDescription {
    return [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSUserTrackingUsageDescription"] isKindOfClass:[NSString class]];
}

@end
