//
//  MedianEventsManager.m
//  Median
//
//  Created by Kevz on 6/14/24.
//  Copyright © 2024 GoNative.io LLC. All rights reserved.
//

#import "MedianEventsManager.h"
@import MedianCoreKMP;

@interface MedianEventsManager()
@property (weak, nonatomic) LEANWebViewController *wvc;
@property NSMutableDictionary<NSString *, NSMutableArray *> *queue;
@property NSMutableDictionary<NSString *, NSNumber *> *subscriptions;
@end

@implementation MedianEventsManager

- (instancetype)initWithWebViewController:(LEANWebViewController *)wvc {
    self = [super init];
    if (self) {
        self.wvc = wvc;
        self.queue = [NSMutableDictionary dictionary];
        self.subscriptions = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)triggerEvent:(NSString *)eventName data:(NSDictionary *)data {
    if (MCKMPMutableConfig.shared.instance.configRoot.general.injectMedianJS || !eventName) {
        return;
    }
    
    if (self.subscriptions[eventName]) {
        [self.wvc runJavascriptWithCallback:eventName data:data];
        return;
    }
    
    self.queue[eventName] = self.queue[eventName] ?: [NSMutableArray array];
    
    NSDictionary *item = data ?: @{};
    if (![self.queue[eventName] containsObject:item]) {
        [self.queue[eventName] addObject:item];
    }
}

- (void)subscribeEvent:(NSString *)eventName {
    if (MCKMPMutableConfig.shared.instance.configRoot.general.injectMedianJS || !eventName) {
        return;
    }
    
    self.subscriptions[eventName] = @YES;
    
    if (self.queue[eventName]) {
        for (NSDictionary *data in self.queue[eventName]) {
            [self.wvc runJavascriptWithCallback:eventName data:data];
        }
     
        [self.queue removeObjectForKey:eventName];
    }
}

- (void)unsubscribeEvent:(NSString *)eventName {
    if (MCKMPMutableConfig.shared.instance.configRoot.general.injectMedianJS || !eventName) {
        return;
    }
    
    self.subscriptions[eventName] = @NO;
}

- (BOOL)isSubscribedForEvent:(NSString *)eventName {
    return self.subscriptions[eventName];
}

- (void)clearSubscriptions {
    [self.subscriptions removeAllObjects];
}

@end
