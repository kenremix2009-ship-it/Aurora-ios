//
//  LEANWindowOverrideHandler.h
//  MedianIOS
//
//  Created by Kevin Mercado on 10/9/26.
//  Copyright © 2026 GoNative.io. All rights reserved.
//

#import <WebKit/WebKit.h>
#import "LEANWebViewController.h"

static NSString * LEANWindowOverrideHandlerName = @"windowOverride";

@interface LEANWindowOverrideHandler : NSObject <WKScriptMessageHandler>
+ (LEANWindowOverrideHandler *)shared;
- (BOOL)handleMessage:(WKScriptMessage *)message;
@end
