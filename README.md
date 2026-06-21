# ShadeTransfer

>这是一个 Vibe Coding 产物，看起来好像很失败😰，虽然能正常编译打包，但核心功能貌似是不可用的状态

>如果你对这个项目感兴趣，可以自己 fork 来玩玩，有什么好的改进也可以提交 PR，但请注意，您必须遵守本项目使用的 MPL 开源协议 。

>受制于设备条件，本人暂时无法完成对 iOS、MacOS、Linux 的适配

使用 Flutter 构建的P2P传输应用程序。
先后使用 `mimo-v2-pro` 和 `grok-code-fast-1` 大模型编写

## 免责声明

本人不会对您因使用本项目产生的任何后果（包括但不限于：隐私泄露、法律后果）负责，您查看、clone 本项目，以及使用本项目的编译产物，即代表您已知悉并接受本声明。

## 功能

- **端到端加密（待验证）** - AES-256 + RSA 加密保护您的数据
- **信令设计** - 通过二维码或文本建立连接（二维码暂不可用）
- **点对点传输** - 直接连接，无需中间服务器
- **可恢复传输（待验证）** - 允许暂停或恢复文件传输
- **跨平台** - 适配 Windows、Android。

## 如何工作

1. **发送方**: 选择文件/文件夹 -> 生成信令 -> 等待接收方输入信令 -> 等待连接 -> 传输开始
2. **接收方**: 输入来自发送方的信令 -> 开始 -> 等待连接 -> 传输开始

## 获取安装包
### 1. 直接下载
#### 正式版
您可以从[Github Release](https://github.com/Drific/ShadeTransfer/release)下载
#### 调试/测试版
您可以从[Github Actions](https://github.com/Drific/ShadeTransfer/actions)下载

### 2. 从源码构建
需要提前准备好环境：
>Flutter SDK、Dart SDK、Android SDK等。
#### Windows
打包exe：
```bash
flutter build windows
```
>你将得到exe文件及dll文件等依赖，无需安装，双击exe文件即可启动

打包msix:
```bash
flutter pub run msix:create
```
>你将得到msix文件，可一键安装或卸载
#### Android
全架构打包：
```bash
flutter build apk --release
```
>你将得到app-release.apk，体积通常较大，但所有架构的设备均可安装（仅限arm64、arm32、x86_64）

分架构打包：
```bash
flutter build apk --release --split-per-abi
```
>你将得到app-arm64-v8a-release.apk、app-armeabi-v7a-release.apk、app-x86_64-release.apk这三个文件，单个体积通常较小，但一个包只适配一个架构，你可以选择自己的设备对应的架构进行安装。

## 用到的依赖

- `flutter_webrtc` - WebRTC P2P 连接
- `qr_flutter` - 二维码生成
- `mobile_scanner` - 二维码扫描 (摄像机 + 图像)
- `image_picker` - 图像文件选择器（为二维码图片扫描）
- `file_picker` - 文件选择
- `encrypt` / `pointycastle` - 加密
- `provider` - 状态管理
- `msix` - 为 Windows 打包 MSIX 安装包
