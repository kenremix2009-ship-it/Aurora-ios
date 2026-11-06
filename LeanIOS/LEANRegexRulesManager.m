//
//  LEANRegexRulesManager.m
//  GonativeIO
//
//  Created by bld ai on 6/14/22.
//  Copyright © 2022 GoNative.io LLC. All rights reserved.
//

#import "LEANRegexRulesManager.h"
#import "LEANWindowsManager.h"
#import "GonativeIO-Swift.h"
@import MedianCoreKMP;

@interface LEANRegexRulesManager()
@property LEANWindowsManager *windowsManager;
@end

@implementation LEANRegexRulesManager

- (instancetype)initWithWvc:(LEANWebViewController *)wvc
{
    self = [super init];
    if (self) {
        self.windowsManager = [[LEANWindowsManager alloc] initWithWvc:wvc];
    }
    return self;
}

- (void)handleUrl:(NSURL *)url query:(NSDictionary*)query {
    if ([@"/set" isEqualToString:url.path]) {
        NSArray *rules = query[@"rules"];
        if ([rules isKindOfClass:[NSArray class]]) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:rules options:0 error:nil];
            NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (json) [MCKMPMutableConfig.shared.instance setRegexRulesFromJsonRulesJson:json];
        }
    }
}

// First matching regexInternalExternal rule decides; same-host/subdomain fallback when none match.
- (BOOL)shouldHandleRequest:(NSURLRequest *)request {
    NSURL *url = [request URL];
    NSString *urlString = [url absoluteString];

    MCKMPMutableConfigState *config = MCKMPMutableConfig.shared.instance;

    // median-core resolves this against route rules once the app config has been
    // migrated, and against the V1 regexes until then. nil means no rule matched.
    NSString *mode = [config linkModeForUrlUrl:urlString];
    if (mode) {
        if (![mode isEqualToString:@"internal"]) {
            [self.windowsManager openUrl:request.URL mode:mode];
            return NO;
        }
        return YES;
    }

    // no rule matched: stay in-app for the initial host and its subdomains
    if (![config.configRoot.general isInternalHostUrl:urlString ?: @""]) {
        [self.windowsManager openUrl:request.URL mode:@"external"];
        return NO;
    }

    return YES;
}

@end
