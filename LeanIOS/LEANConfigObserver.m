//
//  LEANConfigObserver.m
//  LeanIOS
//

#import "LEANConfigObserver.h"
#import "LEANNotifications.h"
@import MedianCoreKMP;

@interface LEANConfigObserver () <MCKMPConfigObserver>
@end

@implementation LEANConfigObserver

+ (void)install {
    static LEANConfigObserver *shared;
    @synchronized(self) {
        if (!shared) {
            shared = [[LEANConfigObserver alloc] init];
            [MCKMPMutableConfig.shared.instance addObserverObserver:shared];
        }
    }
}

- (void)postOnMain:(NSString *)name {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
    });
}

- (void)onMenuChanged {
    [self postOnMain:kLEANAppConfigNotificationProcessedMenu];
}

- (void)onNavigationTitlesChanged {
    [self postOnMain:kLEANAppConfigNotificationProcessedNavigationTitles];
}

- (void)onNavigationLevelsChanged {
    [self postOnMain:kLEANAppConfigNotificationProcessedNavigationLevels];
}

- (void)onNavigationInstanceChanged {
    [self postOnMain:kLEANAppConfigNotificationNavigationInstanceChanged];
}

- (void)onMaxWindowsChanged {
    // windows controller reads maxWindows live; nothing to broadcast
}

- (void)onRegexRulesChanged {
    // regex rules manager reads instance.regexRules live; nothing to broadcast
}

- (void)onInitialUrlChanged {
    // initial url consumers read it live; nothing to broadcast
}

@end
