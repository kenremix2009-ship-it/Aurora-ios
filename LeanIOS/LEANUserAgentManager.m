//
//  LEANUserAgentManager.m
//  LeanIOS
//

#import "LEANUserAgentManager.h"
#import "LEANNotifications.h"
#import <WebKit/WebKit.h>
@import MedianCoreKMP;

@interface LEANUserAgentManager ()
@property NSString *userAgent;
@property BOOL userAgentReady;
@property WKWebView *uaWebview; // retained until the async UA read completes
@end

@implementation LEANUserAgentManager

+ (instancetype)sharedManager
{
    static LEANUserAgentManager *shared;
    @synchronized(self) {
        if (!shared) {
            shared = [[LEANUserAgentManager alloc] init];
            [shared compute];
        }
    }
    return shared;
}

- (void)compute
{
    MCKMPGeneralConfig *general = MCKMPMutableConfig.shared.instance.configRoot.general;

    NSString *forced = [general effectiveForceUserAgent];
    if (forced.length > 0) {
        [self finishWithUserAgent:forced];
        return;
    }

    // Read the default UA from a throwaway webview, then append userAgentAdd.
    self.uaWebview = [[WKWebView alloc] initWithFrame:CGRectZero];
    [self.uaWebview loadHTMLString:@"<html></html>" baseURL:nil];
    [self.uaWebview evaluateJavaScript:@"navigator.userAgent" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        NSString *originalAgent = [result isKindOfClass:[NSString class]] ? result : @"";

        NSString *userAgentAdd = [general effectiveUserAgentAdd];
        if (!userAgentAdd) userAgentAdd = @"gonative";
        if ([userAgentAdd isEqualToString:@"gonative"]) {
            userAgentAdd = @"GoNativeIOS/1.0 gonative";
        }

        NSString *newAgent = userAgentAdd.length > 0
            ? [NSString stringWithFormat:@"%@ %@", originalAgent, userAgentAdd]
            : originalAgent;

        [self finishWithUserAgent:newAgent];
        self.uaWebview = nil;
    }];
}

- (void)finishWithUserAgent:(NSString *)userAgent
{
    self.userAgent = userAgent;
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];
    self.userAgentReady = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:kGoNativeAppConfigNotificationUserAgentReady object:self];
}

@end
