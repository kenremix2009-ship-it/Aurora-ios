//
//  ContextMenuHandler.swift
//  Median
//
//  Created by Kevz on 4/18/24.
//  Copyright © 2024 GoNative.io LLC. All rights reserved.
//

import Foundation
import MedianCore

@objc public class ContextMenuHandler: NSObject {
    // Runtime-mutable state (JS bridge contextMenu/setEnabled|setLinkActions),
    // seeded from the appConfig contextMenu section.
    private static var enabled: Bool = MutableConfig.shared.instance.configRoot.contextMenu.enabled
    private static var linkActions: [String] = MutableConfig.shared.instance.configRoot.contextMenu.linkActions

    @objc public static func setEnabled(_ value: Bool) {
        enabled = value
    }

    @objc public static func setLinkActions(_ actions: [String]) {
        linkActions = actions
    }

    @objc public static func createConfigurationWith(url: URL, shareAction: @escaping () -> Void) -> UIContextMenuConfiguration? {
        if !enabled || url.host == nil {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                return UIMenu(title: "", children: [])
            }
        }

        var actionsList = [UIAction]()

        if linkActions.contains("copyLink") {
            let action = UIAction(title: NSLocalizedString("button-copy-link", comment: ""), image: UIImage(systemName: "doc.on.doc"), identifier: nil) { action in
                UIPasteboard.general.string = url.absoluteString
            }
            actionsList.append(action)
        }

        if linkActions.contains("openExternal") {
            let action = UIAction(title: NSLocalizedString("button-open-external", comment: ""), image: UIImage(systemName: "safari"), identifier: nil) { action in
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            actionsList.append(action)
        }

        if linkActions.contains("shareExternal") {
            let action = UIAction(title: NSLocalizedString("button-share-link", comment: ""), image: UIImage(systemName: "square.and.arrow.up"), identifier: nil) { action in
                shareAction()
            }
            actionsList.append(action)
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var title = url.absoluteString

            if title.count > 60 {
                title = title.prefix(60) + "…"
            }

            return UIMenu(title: title, children: actionsList)
        }
    }
}
