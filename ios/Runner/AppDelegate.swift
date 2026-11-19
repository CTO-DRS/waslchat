import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Wasl Shield (1.10.0): iOS لا يسمح بمنع اللقطات؛ نكتشف التسجيل/البث (UIScreen.isCaptured)
  // ونخفي المحتوى في Flutter أثناءه، وننبّه بعد لقطة الشاشة.
  private var shieldChannel: FlutterMethodChannel?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WaslShield") {
      shieldChannel = FlutterMethodChannel(name: "wasl/shield", binaryMessenger: registrar.messenger())
    }
    let nc = NotificationCenter.default
    nc.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
      self?.shieldChannel?.invokeMethod("onScreenshot", arguments: nil)
    }
    nc.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.shieldChannel?.invokeMethod("onRecording", arguments: UIScreen.main.isCaptured)
    }
    DispatchQueue.main.async { [weak self] in
      if UIScreen.main.isCaptured { self?.shieldChannel?.invokeMethod("onRecording", arguments: true) }
    }
  }
}
