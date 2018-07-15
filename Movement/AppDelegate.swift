//
//  AppDelegate.swift
//  Movement
//
//  Created by Sean Simmons on 2017-11-30.
//  Copyright © 2017 Sean Simmons. All rights reserved.
//

import UIKit
import CoreLocation

protocol LogItemDelegate: class {
  func didUpdateLogItems(logItems: [String])
}


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  var window: UIWindow?
  var manager = CLLocationManager()
  weak var _delegate: LogItemDelegate?
  var delegate: LogItemDelegate? {
    get {
      return _delegate
    }
    set (newDelegate) {
      _delegate = newDelegate
      if let delegate = _delegate {
        delegate.didUpdateLogItems(logItems: logItems)
      }
    }
  }
  
  var logItems: [String] = []

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    uc_os_log("application:didFinishLaunchingWithOptions: %{public}@", "\(launchOptions.debugDescription)")
    logItems.append("\(df.string(from: Date())) - application:didFinishLaunchingWithOptions: \(launchOptions.debugDescription)")
    if let delegate = delegate {
      delegate.didUpdateLogItems(logItems: logItems)
    }
    
    // Override point for customization after application launch.
    let _ = UploadManager.sharedInstance // Ensure that we (re-)start the UploadManager
    
    manager.delegate = self
    manager.requestAlwaysAuthorization()
    manager.allowsBackgroundLocationUpdates = true
    manager.startMonitoringSignificantLocationChanges()
    return true
  }

}

extension AppDelegate: CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    uc_os_log("locationManager:didUpdataLocations: %{public}@", "\(locations)")
    logItems.append("\(df.string(from: Date())) - locationManager:didUpdataLocations: \(locations)")
    if let delegate = delegate {
      delegate.didUpdateLogItems(logItems: logItems)
    }
    UploadManager.sharedInstance.schedulePayload("\(locations)")
    UploadManager.sharedInstance.checkUpload()
  }
}


