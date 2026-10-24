# Headset Gesture

[English](README.md) · **简体中文**

<img src="Resources/Brand/AppIcon.png" alt="Headset Gesture 图标" width="160">

把有线耳机或 USB-C 耳机上的线控按键变成 macOS 上可自定义的输入。Headset Gesture 会独占耳机的播放/暂停键和音量键，把单击、双击、三击和长按分别映射为按键、快捷键、媒体键、快捷指令或 Shell 命令。

## 功能

- **单击**、**双击**、**三击**、**长按**可分别设置；耳机能上报音量键时，**音量加**和**音量减**各有一套独立的映射。
- 可映射的动作：任意按键或组合键（F13–F20、字母、空格、Return、Escape、Tab），左/右 Control、Option、Command 可作为独立按键，媒体键（播放/暂停、下一首、上一首、音量、静音），macOS 快捷指令，或 Shell 命令。
- 可调整双击间隔和长按阈值；提供"仅点击"模式，适配会丢失松开信号的耳机。
- 按住时可在屏幕上显示计时，位置可选七个固定位置，或跟随当前聚焦的输入框。
- 实时监视器显示原始 HID 信号、识别器状态、映射输出和最近事件。
- 菜单栏控制面板；Dock 图标可以隐藏。
- 全部在本机处理，见 [PRIVACY.md](PRIVACY.md)。

## 系统要求

- macOS 13 Ventura 或更新版本，Apple 芯片或 Intel 均可。
- 带线控按键的有线耳机，插在 Mac 的耳机孔上（在 macOS 中显示为名为 `Headset` 的 HID 设备）；或带线控按键的 USB-C 耳机。USB 设备只有同时带 USB 音频接口时才会被接管，键盘和接收器上的媒体键不受影响。

## 安装

1. 从 [Releases](https://github.com/jarvisluk/HeadsetGesture/releases) 下载最新的 `HeadsetGesture-<版本号>.zip` 并解压。发布包已用 Developer ID 签名并通过 Apple 公证（Notarization）。
2. 把 **Headset Gesture.app** 移到"应用程序"文件夹，然后打开。
3. 在主窗口点击 **Request Accessibility Permission**，到"系统设置 → 隐私与安全性 → 辅助功能"中允许。辅助功能权限已包含事件监听；只有不授予辅助功能时，才需要单独允许"输入监控"。
4. 授权后几秒内 App 会自动识别新权限。如果状态没有变化，点击 **Restart App After Granting Access**。

如需隐藏 Dock 图标，在 Customization → App 或菜单栏面板中关闭 **Show icon in Dock**，之后通过菜单栏图标打开主窗口。

## 默认设置

| 手势 | 默认动作 |
| --- | --- |
| 单击 | 播放/暂停 |
| 双击 | F13 |
| 三击 | 关闭 |
| 长按 | F14（长按识别默认关闭） |
| 音量加 / 音量减 单击 | 音量加 / 音量减（音量键的其他手势默认关闭） |

为了和双击区分，单击会在双击间隔结束后才触发。如果某个键的双击和三击都关闭，它的单击会立即触发；如果它的长按关闭，按住也算单击。

## 硬件说明

这里的 `Headset` 设备是 Mac 耳机孔的线控解码器（`AppleCS42L84Mikey`），不是耳机本身。它的报告描述符声明了播放/暂停（0xCD）、音量减（0xEA）和音量加（0xE9），但只有 Apple 规格的线控才会上报音量键。常见的安卓 / CTIA 规格耳机上：

- 音量键没有信号，或者被识别成播放/暂停，所以所有按键共用同一套手势；
- 按偏时可能让播放/暂停信号一直处于"按下"，这段时间内的点击会丢失。

需要独立的音量键时，请使用 Apple 规格的有线耳机或 USB-C 耳机。USB-C 耳机会把播放/暂停（0xCD）、音量加（0xE9）、音量减（0xEA）作为不同的 Usage 上报；在 Customization 中选择按键即可编辑它的手势。

## 关于"全新按键"

普通签名的 App 可以可靠地发送 macOS 定义的虚拟键码，其中包括 F13–F20。F21–F24 或完全自定义的 HID Usage 需要 Apple 限制的 `com.apple.developer.hid.virtual.device` 权限（entitlement），或 Karabiner VirtualHID 这类系统扩展，因此本 App 不提供这些选项。

**原始虚拟键码**模式可以发送 0–127 范围内的任意 CGKeyCode。未定义的键码只有监听原始 CGEvent 的软件才能识别，大多数 App 会忽略。

## 从源码构建

```sh
swift test
./scripts/build-app.sh
```

App 和 zip 输出到 `dist/`。构建脚本会使用钥匙串中第一个 Developer ID Application 证书签名（也可用 `CODE_SIGN_IDENTITY` 指定），找不到证书时回退到临时签名（ad-hoc）；临时签名下每次重新构建后，macOS 可能要求重新授权。

构建、替换 `/Applications` 中已安装的版本并启动：

```sh
./scripts/build-and-run.sh        # release
./scripts/build-and-run.sh debug  # debug
```

如需安装到其他位置，设置 `HEADSET_GESTURE_INSTALL_PATH`。

## 发布

维护者用一条命令发布已签名、已公证的版本，见 [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)。

## 许可证

[MIT](LICENSE) © 2026 Jarvis Luk
