<p align="center">
  <img src="icon.png" width="120" alt="ClipSync"/>
</p>

# ClipSync-Mac

<p align="center">
  <b>ClipSync 三端同步体系的 macOS 客户端</b><br/>
  菜单栏常驻小工具：实时接收手机验证码、双向同步剪贴板（文本/图片）。<br/>
  纯 Swift + SwiftUI，macOS 14+，Menu Bar Extra 形态，零打扰。
</p>

<p align="center">
  <a href="https://github.com/gitwangjiahui/ClipSync-Mac/releases">⬇️ 下载 dmg/zip</a> ·
  <a href="https://github.com/orgs/gitwangjiahui/packages">📦 Packages (ghcr.io)</a> ·
  <a href="https://github.com/gitwangjiahui/ClipSync-Server">🖧 服务端</a> ·
  <a href="https://github.com/gitwangjiahui/ClipSync-Android">📱 Android 端</a>
</p>

---

## 一、它能干什么

| 能力 | 说明 | 对应模块 |
|---|---|---|
| **接收验证码** | 手机短信验证码实时弹到 Mac，可一键复制/自动进剪贴板 | `WebSocketClient` + `ClipboardWriter` |
| **剪贴板双向同步** | Mac 复制 → 推给手机；手机复制 → 写入 Mac 剪贴板 | `ClipboardMonitor` / `ClipboardWriter` |
| **菜单栏常驻** | 状态栏图标显示连接状态（已连/断开/重连中），点开即菜单 | `ClipSyncApp`（MenuBarExtra） |
| **设置中心** | 服务器地址 / Token / 自动写入剪贴板开关 / 剪贴板同步开关 | `SettingsStore` + `SettingsView` |
| **权限引导** | 剪贴板、辅助功能等权限的申请与状态检测 | `PermissionHelper` + `PermissionsView` |
| **轻提示** | 收到内容时轻量 Toast，不抢焦点 | `ToastOverlay` |
| **断线自动重连** | WS 断开后指数退避重连，状态栏实时反映 | `ConnectionState` |

## 二、下载与安装

到 [Releases](https://github.com/gitwangjiahui/ClipSync-Mac/releases) 下载：

- `ClipSync-x.y.z.dmg`：双击打开 → 拖入「应用程序」即可（推荐）
- `ClipSync-x.y.z.zip`：解压出 `.app` 直接用

首次打开若提示「无法验证开发者」：系统设置 → 隐私与安全性 → 仍要打开。

启动后：
1. 菜单栏出现 ClipSync 图标；
2. 打开设置，填 **服务器地址**（`ws://服务器IP:8080`）与 **Token**（与手机端一致即自动配对）；
3. 按提示授予剪贴板权限；图标变绿即已连接。

## 三、消息协议（与服务端约定）

```json
{ "type": "notify_pc", "kind": "sms_code", "text": "【某银行】验证码 314159" }
```

- 服务端把同 token 下 `role=phone` 的消息广播给所有 `role=pc`，本端以 `role=pc` 接入；
- 本端复制剪贴板内容时以 `clipboard` 类型上行，手机端按开关决定是否落剪贴板；
- 服务端不落库，只做实时路由。

## 四、源码构建

要求：macOS 14+、Xcode 16+（工程 objectVersion 77）。

```bash
# 命令行构建（Release，不签名）
xcodebuild -project ClipSync.xcodeproj -scheme ClipSync \
  -configuration Release \
  -archivePath build/ClipSync.xcarchive \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO archive

# 导出 .app
cp -R build/ClipSync.xcarchive/Products/Applications/ClipSync.app ./

# 或打 dmg
hdiutil create -volname "ClipSync" -srcfolder ClipSync.app -ov -format UDZO ClipSync.dmg
```

或直接 Xcode 打开 `ClipSync.xcodeproj` → ▶️ 运行。

## 五、CI 自动打包

打 tag 即自动构建并发 Release + 推容器包（macos-15 runner，Xcode 16.4）：

```bash
git tag v1.2.0 && git push origin v1.2.0
```

产物：`ClipSync-<版本>.dmg` + `ClipSync-<版本>.zip`，自动挂在 Release 页。

## 六、项目结构

```
ClipSync/
├── ClipSyncApp.swift        # 入口：MenuBarExtra + 设置窗口
├── ConnectionState.swift    # 连接状态机（断开/连接中/已连/重连）
├── WebSocketClient.swift    # WS 客户端：心跳、重连、消息分发
├── ClipboardMonitor.swift   # 轮询 NSPasteboard，变化即上行
├── ClipboardWriter.swift    # 收到内容写入 NSPasteboard（含图片）
├── SettingsStore.swift      # UserDefaults 持久化配置（地址/Token/开关）
├── Views/
│   ├── MenuBarView.swift    # 菜单栏下拉内容
│   ├── SettingsView.swift   # 设置页
│   ├── PermissionsView.swift# 权限引导页
│   └── ToastOverlay.swift   # 轻提示浮层
├── Helpers/
│   └── PermissionHelper.swift # 权限申请/检测
├── Info.plist               # 版本/权限声明
└── Assets.xcassets          # 图标资源
```

## 七、常见问题

| 问题 | 解决 |
|---|---|
| 图标灰色连不上 | 检查地址/Token；服务端 8080 是否放行；同网络或用公网地址 |
| 剪贴板不同步 | 设置里开「剪贴板同步」；系统设置授予剪贴板权限 |
| 收不到手机推送 | 确认手机端服务已启动且同 Token |
| 提示无法打开 | 隐私与安全性 → 仍要打开（未签名分发的正常现象） |
| 想要开机自启 | 系统设置 → 通用 → 登录项 → 添加 ClipSync |

## 八、系统要求与说明

- 最低 macOS 14.0，Apple 芯片 / Intel 均支持（CI 出 Apple 芯片包；Intel 需源码构建）
- Bundle ID：`com.jiahui.ClipSyncApp`
- 不采集任何数据；剪贴板内容仅在你的设备与服务端之间点对点流转，服务端不落库
