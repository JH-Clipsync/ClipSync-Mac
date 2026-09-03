<p align="center"><img src="icon.png" width="128" alt="ClipSync"/></p>

<h1 align="center">ClipSync for macOS</h1>

<p align="center">
  <b>手机验证码 & 剪贴板 → Mac 通知横幅，一键复制。</b><br/>
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a>
</p>

---

ClipSync 是一套自建的跨端消息同步工具。本仓库是 macOS 桌面客户端，使用 **Swift + SwiftUI** 开发，以**菜单栏常驻应用**形态运行。

核心场景：**手机上收到验证码或复制了内容后，Mac 右上角立即弹出 Toast 通知，一键复制验证码或全文；反之，Mac 上复制的文本/图片也能实时同步到其他设备。**

不依赖任何第三方推送服务，通信走你自己的 WebSocket 中转，端到端加密可选，隐私自主可控。

> 系统要求：**macOS 14 (Sonoma) 及以上** · 开发工具：**Xcode 16+** · 语言：**Swift 5.10**

---

## 🌐 公共服务端（默认已配置）

本客户端默认 `serverURL` = **`wss://www.95qw.com`**，**下载安装后无需任何配置**，注册账号即可使用。

- 如果你要连**自建实例**：打开「设置 → 服务器」，改成 `wss://你的域名`（**不要**带路径，路径在反代里）；
- 如果你要**完全离线 / 内网**：服务端 Docker 一行起，详见 [ClipSync-Server 部署文档](https://github.com/JH-Clipsync/ClipSync-Server#-反向代理与路径规划)。

---

## ✨ 核心功能

| 模块 | 说明 |
|------|------|
| 🔐 **账号密码登录** | 用户名 + 密码认证，首次连接自动换取 JWT Token；Token 过期自动用本地账密重新登录 |
| 👥 **在线设备列表** | WebSocket Presence 实时推送，主页显示同账号下在线设备的平台 / IP / 设备 ID / 上线时间 / 能力标签 |
| 🛡️ **端到端加密** | AES-256-GCM 加密，PBKDF2-HMAC-SHA256（20 万轮）派生密钥，服务端只转发密文；两端密钥指纹可见可比对 |
| 🔔 **Toast 通知横幅** | 屏幕右上角悬浮通知，设备上线/下线提醒、验证码自动识别、一键复制，不抢焦点 |
| 📩 **验证码智能识别** | 对收到的文本/短信自动正则提取验证码，并在 Toast 中提供「复制验证码」按钮 |
| 📋 **剪贴板双向同步** | 文本与 PNG 图片双向同步；本地变更防抖上传，远端内容按 MIME 类型写回剪贴板 |
| 🍎 **菜单栏常驻** | `MenuBarExtra` 状态栏图标：绿色已连接、黄色连接中、红色断开、灰色未启用；点击弹出快捷面板，**服务器地址可一键复制** |
| 🧭 **首次启动引导** | 引导页依次完成服务器地址、账号密码、端到端加密、剪贴板与辅助功能权限的配置 |
| ⚙️ **设置页** | 服务器地址、账号、加密开关 / 同步密码、是否自动上传剪贴板、是否自动应用远端内容、开机自启 |
| 🪟 **权限引导** | 内建剪贴板访问（自动化）、辅助功能、通知权限的检测与一键跳转系统设置 |
| 🔄 **自动重连** | 指数退避重连（1s → 2s → 4s … 最大 30s），网络恢复后自动恢复 Presence 与剪贴板监听 |
| 📜 **消息历史** | 本地持久化最近 500 条消息（短信 / 文本 / 图片），支持按类型筛选、复制、删除、清空 |
| 🚀 **开机自启** | 使用 `SMAppService` 注册登录项，一键开关，无需辅助功能权限 |
| 🖼️ **图片压缩** | 大于 200KB 的图片自动等比缩放到最长边 1600px、JPEG 0.8 压缩后再上行 |

---

## 🖼️ 界面预览

| 区域 | 说明 |
|------|------|
| 菜单栏图标 | 颜色实时反映连接状态，左键打开主面板，右键提供快捷菜单 |
| 主页 | 状态卡 + 当前账号/加密状态 + 在线设备列表 + 最近消息 |
| 设置 | 服务器、账号、端到端加密、剪贴板同步、开机自启、权限入口 |
| 历史记录 | 短信 / 剪贴板分类查看，文本与图片预览，支持复制和删除 |
| Toast 横幅 | 屏幕右上角悬浮，验证码单独高亮按钮，最多堆叠 3 条 |

---

## 📦 下载安装

前往 [GitHub Releases](https://github.com/JH-Clipsync/ClipSync-Mac/releases) 下载：

| 文件 | 适用场景 |
|------|----------|
| `ClipSync-<版本>-arm64.dmg` | Apple Silicon（M1 / M2 / M3 / M4）Mac（推荐） |
| `ClipSync-<版本>-x86_64.dmg` | Intel 芯片 Mac |
| `ClipSync-<版本>-universal.dmg` | 通用二进制，同时支持两种架构（体积较大） |

> 应用未做 Apple Developer 签名公证，首次打开时若提示「无法打开」，请在 **系统设置 → 隐私与安全性** 中点击「仍要打开」，或在「应用程序」里右键应用 → 打开。

---

## 🚀 快速开始

1. 将 `ClipSync.app` 拖入「应用程序」文件夹并启动
2. 首次启动会进入引导向导：
   - 填写**服务器地址**（如 `192.168.1.10:8080`，支持 `ws://` / `wss://`，不填前缀会自动补 `ws://`）
   - 填写管理员分配的**用户名 / 密码**（首次连接时会自动换取 Token）
   - 选择是否启用**端到端加密**并填写同步密码（两端需保持一致）
   - 按指引开启**剪贴板写入**和**辅助功能**权限
3. 点击「连接」，菜单栏图标变**绿色**即连接成功
4. 在手机端（[ClipSync-Android](https://github.com/JH-Clipsync/ClipSync-Android)）或 Windows 端（[ClipSync-Windows](https://github.com/JH-Clipsync/ClipSync-Windows)）填写同一账号，即可开始同步

---

## 🧩 项目架构

```
ClipSync-Mac/
├── ClipSync/
│   ├── main.swift                  # 入口：MenuBarExtra + AppRouter
│   ├── AppRouter.swift             # 页面路由（引导 / 主界面 / 设置 / 历史）
│   ├── ContentView.swift           # 主窗口容器
│   ├── HomeView.swift              # 主页：状态卡 + 在线设备 + 最近消息
│   ├── SettingsView.swift          # 设置页：服务器/账号/加密/同步/开机自启
│   ├── HistoryView.swift           # 消息历史（短信 / 剪贴板分页）
│   ├── ToastView.swift             # 右上角通知横幅 UI
│   ├── ToastManager.swift          # Toast 队列、堆叠、自动消失
│   ├── ToastStyle.swift            # Toast 颜色/图标样式定义
│   │
│   ├── WSClient.swift              # WebSocket 连接、Presence、自动重连、消息分发
│   ├── AuthClient.swift            # 用户名密码登录、Token 缓存、自动重新登录
│   ├── ServerAddress.swift         # 地址规范化（补 ws/wss、去路径）
│   │
│   ├── Models.swift                # SyncMessage / MessagePayload / OnlineDevice
│   ├── E2EECrypto.swift            # AES-256-GCM + PBKDF2 底层
│   ├── E2EEEnvelope.swift          # 加密信封封装/解包 + 指纹计算
│   ├── SmsCodeExtractor.swift      # 验证码正则识别（中英文模板）
│   │
│   ├── ClipboardMonitor.swift      # 本地剪贴板轮询监听（0.6s，含去重）
│   ├── ClipboardWriter.swift       # 远端消息写回剪贴板（文本 / PNG）
│   │
│   ├── SettingsStore.swift         # UserDefaults 配置读写
│   ├── HistoryStore.swift          # 历史记录持久化（JSON，最多 500 条）
│   │
│   ├── FingerprintLabel.swift      # 密钥指纹展示组件
│   ├── SyncPasswordField.swift     # 同步密码输入（显隐切换）
│   ├── RevealPasswordField.swift   # 通用密码输入框
│   ├── Info.plist                  # LSUIElement=1（无 Dock 图标）
│   └── Assets.xcassets/
├── ClipSync.xcodeproj/
├── project.yml                     # XcodeGen 工程定义
└── .github/workflows/release.yml   # GitHub Actions：arm64/x86_64 双架构 + DMG
```

### 技术栈

- **Swift 5.10** + **SwiftUI**（`@main` + `MenuBarExtra`）
- 最低系统：**macOS 14.0**（`MenuBarExtra`、`Observable`、`SMAppService`）
- 网络：原生 `URLSessionWebSocketTask`
- 加密：系统 `CryptoKit`（`AES.GCM` + `PBKDF2` + `SHA256`）
- 持久化：`UserDefaults` + 应用沙盒 `Application Support` 目录下的 JSON
- 工程生成：[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`project.yml`）
- CI/CD：GitHub Actions 打包 `.app` → `create-dmg` 生成 DMG → 发布 Release

---

## 🔧 从源码构建

### 前置条件

- macOS 14 及以上
- [Xcode 16+](https://developer.apple.com/xcode/)
- （可选）[XcodeGen](https://github.com/yonaskolb/XcodeGen)：若要修改 `project.yml` 后重新生成 `.xcodeproj`

### 命令行构建

```bash
# 克隆仓库
git clone https://github.com/JH-Clipsync/ClipSync-Mac.git
cd ClipSync-Mac

# 直接用 xcodebuild 构建（Release）
xcodebuild -project ClipSync.xcodeproj \
  -scheme ClipSync \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# 产物位于 build/Build/Products/Release/ClipSync.app
```

### 用 Xcode

```bash
# 若修改了 project.yml，先重新生成工程
brew install xcodegen
xcodegen generate

# 打开工程
open ClipSync.xcodeproj
```

在 Xcode 中选择 `ClipSync` 方案，按 ⌘R 运行。首次运行需在 **系统设置 → 隐私与安全性 → 辅助功能 / 剪贴板** 中为 ClipSync 开启权限。

### 生成 DMG（可选）

CI 使用 [create-dmg](https://github.com/create-dmg/create-dmg)：

```bash
brew install create-dmg
create-dmg \
  --volname "ClipSync" \
  --window-pos 200 120 \
  --window-size 540 340 \
  --icon-size 96 \
  --icon "ClipSync.app" 140 160 \
  --hide-extension "ClipSync.app" \
  --app-drop-link 400 160 \
  "ClipSync.dmg" \
  "build/Build/Products/Release/"
```

---

## 🔐 隐私与安全

| 维度 | 设计 |
|------|------|
| 数据传输 | 走你自己的服务器，不经过任何第三方推送/统计服务 |
| 数据存储 | 服务端不落库；Mac 端数据存于 `~/Library/Application Support/ClipSync/` |
| 账号信息 | 用户名、密码、Token 仅保存在 UserDefaults（本地），用于断线重连和重新登录 |
| 历史记录 | `history.json`（最近 500 条，可在应用内一键清空） |
| 日志 | `logs/clipsync-YYYY-MM-DD.log`（按天滚动，仅本机） |
| 端到端加密 | AES-256-GCM；密钥由同步密码经 PBKDF2-HMAC-SHA256（20 万轮）派生，盐固定在客户端，从不上传 |
| 指纹校对 | 设置页展示密钥指纹（如 `A1B2 C3D4 ...`），可在两端人工比对确认 |
| 权限最小化 | 不读浏览器、不读文件系统，仅使用剪贴板、辅助功能（用于写剪贴板）、网络 |
| 生产建议 | 用 Nginx / Caddy 反代加 TLS，走 `wss://` |

---

## 🐛 故障排查

| 现象 | 排查 |
|------|------|
| 菜单栏图标不出现 | 确认系统为 macOS 14+；在「活动监视器」中检查是否有残留 `ClipSync` 进程 |
| 连不上服务器 | 检查地址/端口、防火墙、服务端是否启动；尽量用 `ws://IP:端口` 而非 `localhost` |
| 收到消息但显示解密失败 | 两端「同步密码」不一致，或一端未开 E2EE；对照设置页的密钥指纹 |
| 复制内容不上传 | 检查设置中「自动上传剪贴板」是否开启；系统设置 → 隐私 → 辅助功能中是否已授权 |
| 远端内容没写进剪贴板 | macOS 需要「辅助功能」与「剪贴板」权限；在设置页点击「权限」逐项检查 |
| 验证码按钮不出现 | 部分短信模板不在识别规则内；可在 Toast 中用「复制全文」按钮兜底 |
| 开机自启不生效 | 使用 `SMAppService` 注册，需先把 App 移到 `/Applications`；在系统设置 → 通用 → 登录项中确认 |
| 频繁断线重连 | 查看菜单栏图标是否在黄/绿之间反复；检查 Mac 的网络代理 / VPN / 休眠策略 |

日志位置：`~/Library/Logs/ClipSync/`  
配置位置：`~/Library/Application Support/ClipSync/`

---

## 🤝 相关项目

| 项目 | 技术栈 | 链接 |
|------|--------|------|
| 服务端 | Go + gorilla/websocket | https://github.com/JH-Clipsync/ClipSync-Server |
| Windows 客户端 | .NET 8 + WPF | https://github.com/JH-Clipsync/ClipSync-Windows |
| Android 客户端 | Kotlin + OkHttp | https://github.com/JH-Clipsync/ClipSync-Android |
| 服务管理后台 | Go + Gin | https://github.com/JH-Clipsync/ClipSync-Admin |
| 后台前端 | Vue 3 + Vite | https://github.com/JH-Clipsync/ClipSync-Admin-Web |

---

## 📄 License

个人自用项目，代码可自由参考修改。

---

**Made with ❤️ · 三端全自研 · 隐私归你自己**
