//
//  BackgroundService.swift
//  flutter_foreground_task
//
//  Created by WOO JIN HWANG on 2021/08/11.
//

import Flutter
import Foundation
import UserNotifications

let NOTIFICATION_ID: String = "flutter_foreground_task/backgroundNotification"
let NOTIFICATION_CATEGORY_ID: String = "flutter_foreground_task/backgroundNotificationCategory"
let BG_ISOLATE_NAME: String = "flutter_foreground_task/backgroundIsolate"
let BG_CHANNEL_NAME: String = "flutter_foreground_task/background"

let ACTION_TASK_START: String = "onStart"
let ACTION_TASK_REPEAT_EVENT: String = "onRepeatEvent"
let ACTION_TASK_DESTROY: String = "onDestroy"
let ACTION_BUTTON_PRESSED: String = "onButtonPressed"
let ACTION_NOTIFICATION_PRESSED: String = "onNotificationPressed"

@available(iOS 10.0, *)
class BackgroundService: NSObject {
  static let sharedInstance = BackgroundService()
  
  var isRunningService: Bool = false
  private var isStarted: Bool? = nil

  private let userNotificationCenter: UNUserNotificationCenter
  private var isGrantedNotificationAuthorization: Bool = false
  
  private var notificationContentTitle: String = ""
  private var notificationContentText: String = ""
  private var showNotification: Bool = true
  private var playSound: Bool = false
  private var prevInterval: Int? = nil
  private var currInterval: Int = 5000
  private var prevIsOnceEvent: Bool? = nil
  private var currIsOnceEvent: Bool = false
  private var prevCallbackHandle: Int64? = nil
  private var currCallbackHandle: Int64? = nil
  private var interruptionLevel: Int = 1

  private var flutterEngine: FlutterEngine? = nil
  private var backgroundChannel: FlutterMethodChannel? = nil
  private var repeatTask: Timer? = nil
  
  override init() {
    userNotificationCenter = UNUserNotificationCenter.current()
    super.init()
    // userNotificationCenter.delegate = self
  }

  func run(action: BackgroundServiceAction) {
    let prefs = UserDefaults.standard

    notificationContentTitle = prefs.string(forKey: NOTIFICATION_CONTENT_TITLE) ?? notificationContentTitle
    notificationContentText = prefs.string(forKey: NOTIFICATION_CONTENT_TEXT) ?? notificationContentText
    showNotification = prefs.bool(forKey: SHOW_NOTIFICATION)
    playSound = prefs.bool(forKey: PLAY_SOUND)
    prevInterval = currInterval
    currInterval = prefs.integer(forKey: TASK_INTERVAL)
    prevIsOnceEvent = currIsOnceEvent
    currIsOnceEvent = prefs.bool(forKey: IS_ONCE_EVENT)
    prevCallbackHandle = currCallbackHandle
    currCallbackHandle = prefs.object(forKey: CALLBACK_HANDLE) as? Int64
    interruptionLevel = prefs.integer(forKey: INTERRUPTION_LEVEL)

    switch action {
      case .START:
        isStarted = true
        setNotificationCategory()
        requestNotificationAuthorization()
        isRunningService = true
        if let callbackHandle = currCallbackHandle {
          executeDartCallback(callbackHandle: callbackHandle)
        }
        break
      case .RESTART:
        isStarted = true
        setNotificationCategory()
        sendNotification()
        isRunningService = true
        if let callbackHandle = currCallbackHandle {
          executeDartCallback(callbackHandle: callbackHandle)
        }
        break
      case .UPDATE:
        if (isStarted == true) {
            setNotificationCategory()
            sendNotification()
            isRunningService = true
            if let callbackHandle = currCallbackHandle {
                if prevCallbackHandle != callbackHandle {
                    executeDartCallback(callbackHandle: callbackHandle)
                } else if prevInterval != currInterval || prevIsOnceEvent != currIsOnceEvent {
                    startRepeatTask()
                }
            }
        }
        break
      case .STOP:
        isStarted = false
        stopBackgroundTask() { _ in
          self.isRunningService = false
          self.isGrantedNotificationAuthorization = false
          self.removeAllNotification()
        }
        break
    }
  }

  private func requestNotificationAuthorization() {
    if showNotification {
      let options = UNAuthorizationOptions(arrayLiteral: .alert, .sound)
      userNotificationCenter.requestAuthorization(options: options) { success, error in
        if let error = error {
          print("Authorization error: \(error)")
        } else {
          if (success) {
            self.isGrantedNotificationAuthorization = true
            self.sendNotification()
          } else {
            print("Notification authorization denied.")
          }
        }
      }
    }
  }

  private func setNotificationCategory() {
    guard let buttonsJson = UserDefaults.standard.string(forKey: BUTTONS_DATA),
          let buttonsData = buttonsJson.data(using: .utf8),
          let buttons = try? JSONDecoder().decode([NotificationButton].self, from: buttonsData) else { return }
    createNotificationCategory(with: buttons)
  }

  private func createNotificationCategory(with buttons: [NotificationButton]) {
    let notificationActions = buttons.map { buttonData in
      UNNotificationAction(identifier: buttonData.id, title: buttonData.text, options: [])
    }

    let notificationCategory =
          UNNotificationCategory(identifier: NOTIFICATION_CATEGORY_ID,
          actions: notificationActions,
          intentIdentifiers: [],
          hiddenPreviewsBodyPlaceholder: "", options: [.customDismissAction])
    userNotificationCenter.setNotificationCategories([notificationCategory])
  }

  private func sendNotification() {
    if isGrantedNotificationAuthorization && showNotification {
      let notificationContent = UNMutableNotificationContent()
      notificationContent.title = notificationContentTitle
      notificationContent.body = notificationContentText
      if playSound {
        notificationContent.sound = UNNotificationSound.default
      }
      notificationContent.categoryIdentifier = NOTIFICATION_CATEGORY_ID
      notificationContent.userInfo[PERSISTENT] = UserDefaults.standard.bool(forKey: PERSISTENT)
      if #available(iOS 15.0, *),
          let interruptionLevel = UNNotificationInterruptionLevel.init(rawValue: UInt(interruptionLevel)) {
        notificationContent.interruptionLevel = interruptionLevel
      }
      let request = UNNotificationRequest(identifier: NOTIFICATION_ID, content: notificationContent, trigger: nil)
      userNotificationCenter.add(request, withCompletionHandler: nil)
    }
  }

  private func removeAllNotification() {
    userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [NOTIFICATION_ID])
    userNotificationCenter.removeDeliveredNotifications(withIdentifiers: [NOTIFICATION_ID])
  }

  private func executeDartCallback(callbackHandle: Int64) {
    stopBackgroundTask() { _ in
      // The backgroundChannel cannot be registered unless the registerPlugins function is called.
      if (SwiftFlutterForegroundTaskPlugin.registerPlugins == nil) { return }

      self.flutterEngine = FlutterEngine(name: BG_ISOLATE_NAME, project: nil, allowHeadlessExecution: true)

      let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(callbackHandle)
      let entrypoint = callbackInfo?.callbackName
      let uri = callbackInfo?.callbackLibraryPath
      self.flutterEngine?.run(withEntrypoint: entrypoint, libraryURI: uri)

      SwiftFlutterForegroundTaskPlugin.registerPlugins!(self.flutterEngine!)

      let backgroundMessenger = self.flutterEngine!.binaryMessenger
      self.backgroundChannel = FlutterMethodChannel(name: BG_CHANNEL_NAME, binaryMessenger: backgroundMessenger)
      self.backgroundChannel?.setMethodCallHandler(self.onMethodCall)
    }
  }

  private func startBackgroundTask() {
    stopRepeatTask()
    
    backgroundChannel?.invokeMethod(ACTION_TASK_START, arguments: nil) { _ in
      self.startRepeatTask()
    }
  }

  private func startRepeatTask() {
    stopRepeatTask()

    if currIsOnceEvent {
      backgroundChannel?.invokeMethod(ACTION_TASK_REPEAT_EVENT, arguments: nil)
      return
    }

    let timeInterval = TimeInterval(currInterval / 1000)
    repeatTask = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { _ in
      self.backgroundChannel?.invokeMethod(ACTION_TASK_REPEAT_EVENT, arguments: nil)
    }
  }
  
  private func stopRepeatTask() {
    repeatTask?.invalidate()
    repeatTask = nil
  }
  
  private func stopBackgroundTask(onComplete: @escaping (Bool) -> Void) {
    stopRepeatTask()
    
    // The background task destruction is complete and a new background task can be started.
    if backgroundChannel == nil {
      onComplete(true)
    } else {
      backgroundChannel?.invokeMethod(ACTION_TASK_DESTROY, arguments: nil) { _ in
        self.flutterEngine?.destroyContext()
        self.flutterEngine = nil
        self.backgroundChannel = nil
        onComplete(true)
      }
    }
  }

  private func onMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "initialize":
        startBackgroundTask()
      default:
        result(FlutterMethodNotImplemented)
    }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
    // If it is not a notification requested by this plugin, the processing below is ignored.
    if response.notification.request.identifier != NOTIFICATION_ID { return }

    // Get data from the original notification.
    if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      backgroundChannel?.invokeMethod(ACTION_NOTIFICATION_PRESSED, arguments: nil)
    } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
      if let persistent = response.notification.request.content.userInfo[PERSISTENT] as? Bool, persistent {
        sendNotification()
      }
    } else {
      backgroundChannel?.invokeMethod(ACTION_BUTTON_PRESSED, arguments: response.actionIdentifier)
    }

    completionHandler()
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    // If it is not a notification requested by this plugin, the processing below is ignored.
    if notification.request.identifier != NOTIFICATION_ID { return }

    if playSound {
      completionHandler([.alert, .sound])
    } else {
      completionHandler([.alert])
    }
  }
}