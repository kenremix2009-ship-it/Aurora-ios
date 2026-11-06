//
//  LEANWindowOverrideHandler.m
//  MedianIOS
//
//  Created by Kevin Mercado on 10/9/26.
//  Copyright © 2026 GoNative.io. All rights reserved.
//

#import "LEANWindowOverrideHandler.h"

@implementation LEANWindowOverrideHandler

+ (LEANWindowOverrideHandler *)shared {
    static LEANWindowOverrideHandler *shared;
    @synchronized(self) {
        if (!shared) {
            shared = [[LEANWindowOverrideHandler alloc] init];
        }
        return shared;
    }
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    [self handleMessage:message];
}

- (BOOL)handleMessage:(WKScriptMessage *)message {
    NSDictionary *body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    NSString *windowMethod = body[@"windowMethod"];
    if (![windowMethod isKindOfClass:[NSString class]]) {
        return NO;
    }
    
    if  ([windowMethod isEqualToString:@"window.print"]) {
        [self printWebview:message.webView];
        return YES;
    }
    
    return NO;
}

- (void)printWebview:(WKWebView *)webview {
    if (!webview) {
        return;
    }
    
    UIPrintInteractionController *printController = [UIPrintInteractionController sharedPrintController];
    
    UIPrintInfo *printInfo = [UIPrintInfo printInfo];
    printInfo.outputType = UIPrintInfoOutputGeneral;
    printInfo.jobName = webview.title ?: @"Document";

    printController.printInfo = printInfo;
    printController.printFormatter = [webview viewPrintFormatter];

    [printController presentAnimated:YES completionHandler:nil];
}

@end
