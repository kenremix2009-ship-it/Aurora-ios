//
//  MedianPermissionHandler.swift
//  MedianIOS
//
//  Ported from GoNativeCore (shell-owned since the median-core migration).
//

import AppTrackingTransparency
import AVFoundation
import Contacts
import CoreLocation
import Foundation
import Photos
import UserNotifications

@objc public class MedianPermissionHandler: NSObject {
    @objc public static func getStatus(keys: [String]?) -> [String: String] {
        var data = [
            "Notifications": notificationPermission(),
            "Camera": cameraPermission(),
            "Contacts": contactsPermission(),
            "Microphone": microphonePermission(),
            "LocationWhenInUse": locationWhenInUsePermission(),
            "LocationAlways": locationAlwaysPermission(),
            "AppTrackingTransparency": appTrackingPermission(),
            "PhotoLibrary": photoLibraryPermission()
        ]

        if let keys = keys, keys.count > 0 {
            let keysToRemove = data.keys.filter { !keys.contains($0) }
            for key in keysToRemove {
                data.removeValue(forKey: key)
            }
        }

        return data
    }

    static func notificationPermission() -> String {
        var permissionStatus = "undetermined"
        let semaphore = DispatchSemaphore(value: 0)

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .denied {
                permissionStatus = "denied"
            } else if settings.authorizationStatus == .notDetermined {
                permissionStatus = "undetermined"
            } else {
                permissionStatus = "granted"
            }
            semaphore.signal()
        }

        semaphore.wait()
        return permissionStatus
    }

    static func cameraPermission() -> String {
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if permissionStatus == .authorized {
            return "granted"
        } else if permissionStatus == .notDetermined {
            return"undetermined"
        } else {
            return "denied"
        }
    }

    static func contactsPermission() -> String {
        let permissionStatus = CNContactStore.authorizationStatus(for: .contacts)
        if permissionStatus == .authorized {
            return "granted"
        } else if permissionStatus == .notDetermined {
            return"undetermined"
        } else {
            return "denied"
        }
    }

    static func microphonePermission() -> String {
        let permissionStatus = AVAudioSession.sharedInstance().recordPermission
        if permissionStatus == .granted {
            return "granted"
        } else if permissionStatus == .undetermined {
            return"undetermined"
        } else {
            return "denied"
        }
    }

    static func locationWhenInUsePermission() -> String {
        let permissionStatus = CLLocationManager.authorizationStatus()
        if permissionStatus == .authorizedWhenInUse {
            return "granted"
        } else if permissionStatus == .notDetermined {
            return "undetermined"
        } else {
            return "denied"
        }
    }

    static func locationAlwaysPermission() -> String {
        let permissionStatus = CLLocationManager.authorizationStatus()
        if permissionStatus == .authorizedAlways {
            return "granted"
        } else if permissionStatus == .notDetermined {
            return "undetermined"
        } else {
            return "denied"
        }
    }

    static func appTrackingPermission() -> String {
        if #available(iOS 14, *) {
            let permissionStatus = ATTrackingManager.trackingAuthorizationStatus
            if permissionStatus == .authorized {
                return "granted"
            } else if permissionStatus == .notDetermined {
                return "undetermined"
            } else {
                return "denied"
            }
        } else {
            return "undetermined"
        }
    }

    static func photoLibraryPermission() -> String {
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .authorized {
            return "granted"
        } else if status == .notDetermined {
            return "undetermined"
        } else {
            return "denied"
        }
    }
}
