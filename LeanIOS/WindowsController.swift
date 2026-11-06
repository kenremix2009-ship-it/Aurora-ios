//
//  WindowsController.swift
//  GonativeIO
//
//  Created by Hunaid Hassan on 14.06.21.
//  Copyright © 2021 GoNative.io LLC. All rights reserved.
//

import Foundation
import MedianCore

@objc class WindowsController: NSObject {
    @objc class public func windowCountChanged() {
        guard let maxWindows = MutableConfig.shared.instance.maxWindows, maxWindows.enabled else { return }
        let numWindows = Int(maxWindows.numWindows)
        guard LEANWebViewController.currentWindows > numWindows else {
            return
        }
        
        if let rootViewController = UIApplication.shared.windows.first?.rootViewController as? LEANRootViewController,
           let navigationController = rootViewController.contentViewController as? UINavigationController {
            var viewControllers = navigationController.viewControllers
            let removeTillIndex = LEANWebViewController.currentWindows - numWindows
            viewControllers.removeSubrange(1...removeTillIndex)
            navigationController.viewControllers = viewControllers
        }
    }
}
