import Flutter
import UIKit

/// flutter_node 的 MethodChannel 侧。
///
/// **注意**：PeekPili 真正用的是 `Classes/NodeWrapper.c` 提供的 C 符号
/// （`nodeStart` / `nodeStartThread` / `nodeStop`），由 Dart 侧通过
/// `DynamicLibrary.process()` 查找，**不走** MethodChannel。
/// 这里保留 channel 只是为了：
///   1. 保持 pod 结构合法（register 必须存在，否则插件注册失败）；
///   2. 让 `FlutterNode.platformVersion` 这个 Dart 探针可用，便于排障。
public class SwiftFlutterNodePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_node",
      binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterNodePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
