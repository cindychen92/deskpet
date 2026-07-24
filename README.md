# DogDesktopPet

一个 macOS 桌面宠物小狗应用，使用真实宠物图片制作。

## 功能

- 在桌面边缘慢速走动
- 单击切换状态：趴下、睡觉、吃饭、撒娇、继续走路
- 右键菜单：手动切换状态、跳一跳、摇头、暂停走动、退出
- 走路动画使用 15 FPS 序列帧控制器
- 移动使用 Lerp + EaseInOut 缓动
- 动作切换会等待当前动作周期结束，减少闪烁和硬切

## 直接使用

下载 `Release/DogDesktopPet-share.zip`，解压后打开 `DogDesktopPet.app`。

如果 macOS 提示无法验证开发者：

1. 按住 Control 键点击 `DogDesktopPet.app`
2. 选择“打开”
3. 在弹窗里再次选择“打开”

这是因为该应用是本地打包版本，没有经过 Apple 公证。

## 从源码构建

在 Xcode 中打开 `DogDesktopPet.xcodeproj`，选择 `DogDesktopPet` scheme，然后运行或归档。

也可以继续使用命令行构建：

```bash
./build.sh
```

构建结果会输出到：

```text
build/DogDesktopPet.app
build/DogDesktopPet.zip
```

### Firebase 配置

远程桌宠图片依赖 Firebase Storage。真实的 `GoogleService-Info.plist` 包含 Firebase app 配置和 API key，不应提交到 git。

本地启用远程资源：

1. 从 Firebase Console 下载配置文件：Project settings -> General -> Your apps。
2. 选择 bundle ID 为 `scrapps.deskpet` 的 iOS/macOS app。
3. 下载 `GoogleService-Info.plist`，放在仓库根目录。
4. 重新构建应用。

仓库中提供 `GoogleService-Info.example.plist` 作为占位模板。协作者应从 Firebase Console 或团队密码管理器获取真实 plist。没有本地 `GoogleService-Info.plist` 时，应用仍会启动，但会跳过 Firebase 远程资源加载。

CI 如果需要 Firebase 远程资源，应在 Xcode 构建前从 secret 写入根目录的 `GoogleService-Info.plist`。不要把真实 plist 或 secret 输出到日志。

### Firebase API key 轮换

如果真实 plist 曾经出现在公开仓库中，请在 Google Cloud Console 轮换对应的 iOS key，并把新 key 限制到 bundle ID `scrapps.deskpet`。轮换后重新从 Firebase Console 下载 `GoogleService-Info.plist`，替换本地文件，并确认 Firebase Storage 资源加载正常。已有的本地 plist 不会自动更新，所有协作者和 CI 都切换到新 plist 后，再删除旧 key。

## 项目结构

```text
Sources/
  App/         应用入口、AppDelegate、窗口生命周期
  Firebase/    Firebase 配置、匿名认证、远程资源加载与缓存
  PetDomain/   桌宠状态、动作、动画时序与状态机
  Movement/    位置缓动和移动基础逻辑
  Rendering/   PetView、绘制、资源加载协议和交互回调
  UI/          右键菜单构建
DogDesktopPet.xcodeproj/  Xcode 项目与共享 scheme
Release/       可直接分享的 zip 包
Info.plist     macOS 应用配置
GoogleService-Info.example.plist  Firebase 配置模板
build.sh       本地构建脚本
```

## 说明

桌宠列表、默认 `simba` 宠物、所有可选宠物和当前选中的宠物 ID 由 Firestore 管理。实际 PNG 图片仍存放在 Firebase Storage 中，应用会按选中宠物文档里的 `storagePath` 加载并缓存图片；如果 Firestore 不可用或资源不完整，会回退到默认 `simba` 或备用绘制。
