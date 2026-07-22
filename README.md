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

## 项目结构

```text
Sources/       Swift 源码
Resources/     桌宠图片资源
DogDesktopPet.xcodeproj/  Xcode 项目与共享 scheme
Release/       可直接分享的 zip 包
Info.plist     macOS 应用配置
build.sh       本地构建脚本
```

## 说明

图片资源来自个人宠物照片，仅用于个人分享和试玩。
