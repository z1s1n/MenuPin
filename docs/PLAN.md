# MenuPin Implementation Plan

Goal: 可运行的原生菜单栏管理应用及完整源码。
Architecture: SwiftUI 面板 + AppKit 生命周期 + AX/CGEvent 引擎 + 独立可测试的几何与身份模型。
Tech Stack: Swift 6.1（Swift 5 模式），macOS 13 SDK，Swift Package Manager。

- [x] 建立 Core 与独立 Swift 测试，验证项目分类、跨屏坐标、窗口筛选与身份匹配。
- [x] 实现 AX 枚举和窗口补充；不在无权限时填充模拟项目。
- [x] 实现分隔符展开 / 收起、异步 Command 拖动、移动后验证与恢复失败反馈。
- [x] 实现列表打开原菜单、权限引导、搜索、更多操作和设置。
- [x] 实现启动及退出恢复、屏幕变化处理、自动收起、独立演示窗口。
- [x] 编译、测试、签名打包、渲染 UI、检查真实启动；记录实测边界。

此记录描述最初的本地实现。项目现已准备以 MIT License 在 GitHub 公开发布。
