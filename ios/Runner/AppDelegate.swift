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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "NativeDisplayLayoutPlugin"
    ) {
      NativeDisplayLayoutPlugin.register(with: registrar)
    }
  }
}

private final class NativeDisplayLayoutPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private weak var observerView: DisplayRegionObserverView?
  private var eventSink: FlutterEventSink?
  private var lastSnapshotData: Data?

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = NativeDisplayLayoutPlugin()
    let channel = FlutterEventChannel(
      name: "novelty/display_layout",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(plugin)

    if let rootView = registrar.viewController?.view {
      let observerView = DisplayRegionObserverView(frame: rootView.bounds)
      observerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      observerView.isUserInteractionEnabled = false
      observerView.backgroundColor = .clear
      observerView.onLayoutChange = { [weak plugin] value in
        plugin?.publish(value)
      }
      rootView.addSubview(observerView)
      plugin.observerView = observerView
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    lastSnapshotData = nil
    observerView?.publishCurrentLayout()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    lastSnapshotData = nil
    return nil
  }

  private func publish(_ snapshot: [String: Any]) {
    guard let eventSink else {
      return
    }

    guard
      let data = try? JSONSerialization.data(
        withJSONObject: snapshot,
        options: [.sortedKeys]
      ),
      data != lastSnapshotData
    else {
      return
    }

    lastSnapshotData = data
    eventSink(snapshot)
  }
}

private final class DisplayRegionObserverView: UIView {
  var onLayoutChange: (([String: Any]) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    if #available(iOS 17.0, *) {
      registerForTraitChanges([UITraitHorizontalSizeClass.self]) {
        (view: DisplayRegionObserverView, _: UITraitCollection) in
        view.publishCurrentLayout()
      }
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) は使用しません")
  }

  override func updateConstraints() {
    let snapshot = currentLayout()
    super.updateConstraints()
    onLayoutChange?(snapshot)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    publishCurrentLayout()
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    publishCurrentLayout()
  }

  func publishCurrentLayout() {
    setNeedsUpdateConstraints()
    onLayoutChange?(currentLayout())
  }

  private func currentLayout() -> [String: Any] {
    let widthClass: String?
    switch traitCollection.horizontalSizeClass {
    case .compact:
      widthClass = "compact"
    case .regular:
      widthClass = "regular"
    default:
      widthClass = nil
    }

    var divisionRegions = [[Double]]()
    var occlusionRegions = [[Double]]()
    if #available(iOS 27.1, *) {
      divisionRegions = reservedRegions(kind: .division)
        .filter(\.isActive)
        .map { region in
          [
            Double(region.frame.origin.x),
            Double(region.frame.origin.y),
            Double(region.frame.width),
            Double(region.frame.height),
          ]
        }
      occlusionRegions = reservedRegions(kind: .occlusion)
        .filter(\.isActive)
        .map { region in
          [
            Double(region.frame.origin.x),
            Double(region.frame.origin.y),
            Double(region.frame.width),
            Double(region.frame.height),
          ]
        }
    }

    var result: [String: Any] = [
      "divisionRegions": divisionRegions,
      "occlusionRegions": occlusionRegions,
    ]
    if let widthClass {
      result["horizontalSizeClass"] = widthClass
    }
    return result
  }
}
