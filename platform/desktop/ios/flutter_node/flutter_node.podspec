#
# flutter_node.podspec —— iOS 端 Node 运行时（vendored，非 pub 插件）
#
# 来源与改动（全部有据可查）：
#   * 基线 = https://github.com/xuelongqy/flutter_node 的 ios/ 目录
#     （原版 PeekPili IPA 里 flutter_node.framework 的编译路径为
#      /Users/runner/work/PeekPili/PeekPili/flutter_node-master/ios/Classes/，
#      证明原版正是把该仓库 zip 解出的 flutter_node-master 直接 vendor 进来的）
#   * **追加** `Classes/NodeWrapper.c`：NodeMobile 只导出 `node_start`（2 参、阻塞），
#     而 Dart 侧按 camelCase 查找 `nodeStart` / `nodeStartThread` / `nodeStop`。
#     原版 flutter_node.framework 的导出表里就有这三个符号
#     （_nodeStart@0x400c / _nodeStartThread@0x40ec / _nodeStop@0x4264），
#     本文件即按该二进制的反汇编逐条还原。
#   * `Frameworks/NodeMobile.framework` = com.janeasystems.NodeMobile（nodejs-mobile），
#     arm64 / iPhoneOS / min iOS 13.0，从原版 IPA 原样取出（未加密，无 LC_ENCRYPTION_INFO）。
#
Pod::Spec.new do |s|
  s.name             = 'flutter_node'
  s.version          = '0.0.1'
  s.summary          = 'Node.js for Flutter (NodeMobile + NodeWrapper camelCase shim).'
  s.description      = <<-DESC
Node.js for Flutter, based on NodeMobile (nodejs-mobile).
PeekPili 追加 Classes/NodeWrapper.c，补齐 NodeMobile 缺失的
nodeStart / nodeStartThread / nodeStop 三个 camelCase 符号，
使 Dart 侧可以用 DynamicLibrary.process() 按名字直接调用。
                       DESC
  s.homepage         = 'https://github.com/xuelongqy/flutter_node'
  s.license          = { :type => 'MIT' }
  s.author           = { 'xuelongqy' => 'xuelongqy@foxmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  # NodeMobile 是 arm64 真机专用框架，**没有模拟器切片**
  # （Info.plist: CFBundleSupportedPlatforms = [iPhoneOS]），
  # 所以本 pod 只能在 iphoneos SDK 下构建。
  s.vendored_frameworks = 'Frameworks/NodeMobile.framework'
  s.libraries = 'c++'

  s.platform = :ios, '13.0'

  # 必须是非静态框架：NodeWrapper 的 C 符号要在运行期由
  # Dart 的 DynamicLibrary.process() 按名字查找，静态库 + dead_strip
  # 会把「无人引用」的符号删掉。做成 dylib 才能保住导出表。
  s.static_framework = false

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'VALID_ARCHS[sdk=iphoneos*]' => 'arm64',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64 x86_64',
    'IPHONEOS_DEPLOYMENT_TARGET' => '13.0',
  }
  s.swift_version = '5.0'
end
