//
//  LEANUserAgentManager.h
//  LeanIOS
//
//  Shell-owned user-agent pipeline (previously inside GoNativeCore's GoNativeAppConfig).
//  Computes the app-wide UA (default webview UA + userAgentAdd, or a forced UA) and
//  posts kGoNativeAppConfigNotificationUserAgentReady when available.
//

#import <Foundation/Foundation.h>

@interface LEANUserAgentManager : NSObject
+ (instancetype)sharedManager;

@property (readonly) NSString *userAgent;
@property (readonly) BOOL userAgentReady;

@end
