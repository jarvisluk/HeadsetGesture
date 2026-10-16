# Headset Gesture

<img src="Resources/Brand/AppIcon.png" alt="Headset Gesture 图标" width="160">

一个带主窗口和菜单栏入口的 macOS App，用于独占读取名为 `Headset` 的 Audio Consumer HID 设备：

- 单击映射为自定义按键或快捷键（默认播放/暂停）
- 双击映射为自定义按键或快捷键
- 长按映射为自定义按键或快捷键
- 可调整双击间隔与长按阈值
- 长按时在屏幕浮层实时显示持有时间，可选择七个固定位置或跟随当前聚焦的输入框
- 实时示意图显示原始按键、手势识别阶段、映射输出与最近事件
- 支持 F13–F20、字母键和修饰键组合
- 支持独立映射左/右 Control、Option 和 Command 键
- 支持播放/暂停、上一首、下一首、音量和静音等媒体键
- 支持运行 macOS 快捷指令或 Shell 命令
- 支持实验性的原始 CG 虚拟键码

## 使用

1. 将 `Headset Gesture.app` 移到“应用程序”文件夹。
2. 启动后会自动显示按键映射主窗口，Dock 和菜单栏均有入口。如需隐藏 Dock 图标，可在 Customization → App 或菜单栏菜单中关闭“Show icon in Dock”，之后通过菜单栏图标打开主窗口。
3. 在主窗口分别点击“请求输入监控权限”和“请求辅助功能权限”。
4. 在“隐私与安全性”中允许“辅助功能”；该权限也包含事件监听。只有不授予辅助功能时，才需要单独允许“输入监控”。返回 App 后，授权状态会自动刷新。
5. 回到 App 后会自动刷新并重新连接；如果状态仍未更新，点击“授权后重启 App”。

默认单击发送播放/暂停，双击发送 F13，长按发送 F14。为区分双击，单击动作会在双击间隔结束后触发。

当前硬件把三个实体按钮都上报为同一个播放/暂停 HID 信号，所以三者共用相同手势配置。

这里的 “Headset” 设备是 Mac 耳机孔的线控解码器（`AppleCS42L84Mikey`）。它的报告描述符虽然声明了播放/暂停（0xCD）、音量减（0xEA）和音量加（0xE9），但只有 Apple 规格的线控才会上报音量键；常见安卓/CTIA 规格耳机的音量键无法被解码，按偏或按到音量键时可能没有信号，或者让播放/暂停信号持续处于“按下”，导致这段时间内的点击丢失。需要独立的音量键时，请使用 Apple 规格的有线耳机、USB-C 或蓝牙耳机。

## 关于“全新按键”

普通本地签名 App 可以可靠发送 macOS 定义的虚拟键码，其中功能键为 F13–F20。F21–F24 或完全自定义的 HID Usage 需要 Apple 限制的 `com.apple.developer.hid.virtual.device` entitlement，或者依赖 Karabiner VirtualHID 等系统扩展，因此本项目不伪装提供这些不可用选项。

“原始虚拟键码”模式可以发送 0–127 范围的 CGKeyCode，但未定义键码只会被监听原始 CGEvent 的软件识别，普通 App 可能忽略。

## 构建

```sh
swift test
swift build -c release
```

生成可双击运行的 `.app` 和 zip：

```sh
./scripts/build-app.sh
```

产物位于 `dist/`。

构建脚本会优先使用钥匙串中的 Developer ID Application 证书，以便 macOS 在重建后仍能识别同一个 App。也可以通过 `CODE_SIGN_IDENTITY` 指定签名身份；如果机器上没有可用证书，脚本会回退到临时签名，此时每次重建后可能需要重新授权。

构建、关闭旧实例、安装到 `/Applications/Headset Gesture.app` 并立即运行最新 App：

```sh
./scripts/build-and-run.sh
```

也可以构建并运行 debug 版本：

```sh
./scripts/build-and-run.sh debug
```

脚本使用自身所在位置定位项目，因此也可以从其他目录通过绝对路径调用。
如需改用其他固定安装位置，可通过 `HEADSET_GESTURE_INSTALL_PATH` 指定完整的 `.app` 路径。

## 正式发布

当前流程面向 Developer ID 签名并经 Apple 公证的站外直接分发，不是 Mac App Store 提交流程。项目包含 App Icon 母版、`.icns` 生成脚本、通用二进制构建、Developer ID 签名检查和 `notarytool` 公证流程。第一次公开发布前，请先完成 [发布检查清单](RELEASE_CHECKLIST.md)，尤其是永久 Bundle ID、版本号、版权/许可证、隐私说明和干净环境测试。

完整的签名与公证示例：

```sh
BUNDLE_IDENTIFIER=com.example.HeadsetGesture \
MARKETING_VERSION=1.2.0 \
BUILD_NUMBER=4 \
COPYRIGHT_NOTICE='Copyright © 2026 Your Name. All rights reserved.' \
NOTARY_PROFILE=HeadsetGesture \
./scripts/prepare-release.sh
```

如果暂时不设置 `NOTARY_PROFILE`，脚本只生成并验证已签名的发布包；公开分发前仍需执行 `./scripts/notarize-app.sh`。隐私处理说明见 [PRIVACY.md](PRIVACY.md)。
