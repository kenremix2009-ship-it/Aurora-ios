//
//  LEANConfigObserver.h
//  LeanIOS
//
//  Bridges median-core config-change callbacks to the legacy kLEAN* NSNotifications
//  that shell components observe.
//

#import <Foundation/Foundation.h>

@interface LEANConfigObserver : NSObject
+ (void)install;
@end
