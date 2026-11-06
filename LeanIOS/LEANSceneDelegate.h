//
//  LEANSceneDelegate.h
//  MedianIOS
//
//  Created by Kevin Mercado on 10/1/26.
//  Copyright © 2026 GoNative.io. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "LEANAppDelegate.h"

@interface LEANSceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (nonatomic, weak) LEANAppDelegate *appDelegate;

@end
