<p align="center"><img src="icon.png" width="128" alt="ClipSync"/></p>

<h1 align="center">ClipSync for macOS</h1>

<p align="center">
  <b>Phone verification codes & clipboard → Mac notification banners, one-click copy.</b><br/>
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a>
</p>

---

ClipSync is a self-hosted, cross-device message sync tool. This repository contains the macOS desktop client, built with **Swift + SwiftUI** and designed to live in the **menu bar**.

Core scenario: **When you receive a verification code or copy something on your phone, a Toast notification instantly pops up in the top-right corner of your Mac, letting you copy the code or the full text in one click. Conversely, text or images copied on the Mac are synced to your other devices in real time.**

No third-party push services are involved — all traffic goes through your own WebSocket relay, with optional end-to-end encryption, so privacy stays under your control.

## 🌐 Public Server (Pre-configured)

The default `serverURL` in this client is **`wss://www.95qw.com`**. After installation, **no setup is required** — just register an account and you're in.

- **Self-hosted instance?** Open *Settings → Server* and change it to `wss://your-domain` (no path; the reverse proxy handles the path).
- **Fully offline / LAN?** The server is a single Go binary / Docker container. See the [ClipSync-Server deployment guide](https://github.com/JH-Clipsync/ClipSync-Server#-reverse-proxy--path-planning).


> System requirements: **macOS 14 (Sonoma) or later** · Development tools: **Xcode 16+** · Language: **Swift 5.10**

---

## ✨ Key Features

| Module | Description |
|------|------|
| 🔐 **Username & password login** | Authenticates with username + password and automatically exchanges for a JWT Token on first connect; when the Token expires, the locally saved credentials are used to log in again automatically. |
| 👥 **Online device list** | Real-time WebSocket Presence push; the main page shows each online device's platform / IP / device ID / online time / capability tags under the same account. |
| 🛡️ **End-to-end encryption** | AES-256-GCM with keys derived via PBKDF2-HMAC-SHA256 (200,000 iterations); the server only relays ciphertext; the key fingerprints of both ends are visible and can be compared. |
| 🔔 **Toast notification banners** | Floating notifications at the top-right of the screen for device online/offline events, automatic verification-code recognition, and one-click copy — without stealing focus. |
| 📩 **Smart verification-code recognition** | Automatically extracts verification codes from incoming text/SMS via regex and offers a "Copy code" button inside the Toast. |
| 📋 **Bidirectional clipboard sync** | Two-way sync for text and PNG images; local changes are uploaded with debouncing, while remote content is written back to the clipboard according to its MIME type. |
| 🍎 **Menu bar resident** | A `MenuBarExtra` status-bar icon: green = connected, yellow = connecting, red = disconnected, gray = disabled; click to open the quick panel. **The server-address line is selectable and supports ⌘C; the address is also shown in the menu-bar dropdown.** |
| 🧭 **First-launch onboarding** | A guided wizard walks you through server address, account credentials, end-to-end encryption, and clipboard/accessibility permissions. |
| ⚙️ **Settings page** | Server address, account, encryption toggle / sync password, auto-upload clipboard, auto-apply remote content, and launch at login. |
| 🪟 **Permission guidance** | Built-in detection and one-click jump to System Settings for clipboard access (Automation), Accessibility, and Notifications. |
| 🔄 **Automatic reconnect** | Exponential backoff reconnect (1s → 2s → 4s … max 30s); Presence and clipboard monitoring are automatically restored after the network comes back. |
| 📜 **Message history** | The latest 500 messages (SMS / text / images) are persisted locally, with filtering by type, copy, delete, and clear-all support. |
| 🚀 **Launch at login** | Registers a login item with `SMAppService`, toggleable in one click — no Accessibility permission required. |
| 🖼️ **Image compression** | Images larger than 200KB are proportionally scaled so the longest side is 1600px and compressed as JPEG 0.8 before upload. |

---

## 🖼️ Interface Overview

| Area | Description |
|------|------|
| Menu bar icon | Its color reflects the connection state in real time; left-click opens the main panel, right-click shows the quick menu. |
| Main page | Status card + current account/encryption status + online device list + recent messages. |
| Settings | Server, account, end-to-end encryption, clipboard sync, launch at login, and permission entry points. |
| History | Browse by SMS / clipboard category, preview text and images, with copy and delete support. |
| Toast banner | Floats at the top-right of the screen, with a separately highlighted button for verification codes; up to 3 banners stack. |

---

## 📦 Download & Install

Head to [GitHub Releases](https://github.com/JH-Clipsync/ClipSync-Mac/releases) to download:

| File | Use case |
|------|----------|
| `ClipSync-<version>-arm64.dmg` | Apple Silicon (M1 / M2 / M3 / M4) Mac (recommended) |
| `ClipSync-<version>-x86_64.dmg` | Intel-based Mac |
| `ClipSync-<version>-universal.dmg` | Universal binary supporting both architectures (larger file size) |

> The app is not signed or notarized with an Apple Developer certificate. If macOS shows "cannot be opened" on first launch, go to **System Settings → Privacy & Security** and click "Open Anyway", or right-click the app in "Applications" → Open.

---

## 🚀 Quick Start

1. Drag `ClipSync.app` into the "Applications" folder and launch it.
2. On first launch you'll enter the setup wizard:
   - Fill in the **server address** (e.g. `192.168.1.10:8080`; `ws://` / `wss://` are supported; if no prefix is provided, `ws://` is added automatically).
   - Fill in the **username / password** assigned by the administrator (a Token is automatically fetched on first connect).
   - Choose whether to enable **end-to-end encryption** and enter a sync password (it must match on both ends).
   - Follow the prompts to grant **clipboard write** and **Accessibility** permissions.
3. Click "Connect"; the menu bar icon turning **green** means the connection succeeded.
4. On the mobile app ([ClipSync-Android](https://github.com/JH-Clipsync/ClipSync-Android)) or the Windows client ([ClipSync-Windows](https://github.com/JH-Clipsync/ClipSync-Windows)), log in with the same account and start syncing.

---

## 🧩 Project Structure

```
ClipSync-Mac/
├── ClipSync/
│   ├── main.swift                  # Entry point: MenuBarExtra + AppRouter
│   ├── AppRouter.swift             # Page routing (onboarding / main / settings / history)
│   ├── ContentView.swift           # Main window container
│   ├── HomeView.swift              # Main page: status card + online devices + recent messages
│   ├── SettingsView.swift          # Settings page: server/account/encryption/sync/launch at login
│   ├── HistoryView.swift           # Message history (SMS / clipboard tabs)
│   ├── ToastView.swift             # Top-right notification banner UI
│   ├── ToastManager.swift          # Toast queue, stacking, auto-dismiss
│   ├── ToastStyle.swift            # Toast color/icon style definitions
│   │
│   ├── WSClient.swift              # WebSocket connection, Presence, auto-reconnect, message dispatch
│   ├── AuthClient.swift            # Username/password login, Token cache, automatic re-login
│   ├── ServerAddress.swift         # Address normalization (add ws/wss, strip path)
│   │
│   ├── Models.swift                # SyncMessage / MessagePayload / OnlineDevice
│   ├── E2EECrypto.swift            # AES-256-GCM + PBKDF2 low-level implementation
│   ├── E2EEEnvelope.swift          # Encryption envelope pack/unpack + fingerprint calculation
│   ├── SmsCodeExtractor.swift      # Verification-code regex recognition (Chinese/English templates)
│   │
│   ├── ClipboardMonitor.swift      # Local clipboard polling (0.6s, with deduplication)
│   ├── ClipboardWriter.swift       # Writes remote messages back to the clipboard (text / PNG)
│   │
│   ├── SettingsStore.swift         # UserDefaults configuration read/write
│   ├── HistoryStore.swift          # History persistence (JSON, up to 500 entries)
│   │
│   ├── FingerprintLabel.swift      # Key fingerprint display component
│   ├── SyncPasswordField.swift     # Sync password input (show/hide toggle)
│   ├── RevealPasswordField.swift   # Generic password input field
│   ├── Info.plist                  # LSUIElement=1 (no Dock icon)
│   └── Assets.xcassets/
├── ClipSync.xcodeproj/
├── project.yml                     # XcodeGen project definition
└── .github/workflows/release.yml   # GitHub Actions: arm64/x86_64 dual-arch + DMG
```

### Tech Stack

- **Swift 5.10** + **SwiftUI** (`@main` + `MenuBarExtra`)
- Minimum system: **macOS 14.0** (`MenuBarExtra`, `Observable`, `SMAppService`)
- Networking: native `URLSessionWebSocketTask`
- Crypto: system `CryptoKit` (`AES.GCM` + `PBKDF2` + `SHA256`)
- Persistence: `UserDefaults` + JSON under the app sandbox's `Application Support` directory
- Project generation: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`)
- CI/CD: GitHub Actions packages `.app` → `create-dmg` produces DMG → publishes a Release

---

## 🔧 Building from Source

### Prerequisites

- macOS 14 or later
- [Xcode 16+](https://developer.apple.com/xcode/)
- (Optional) [XcodeGen](https://github.com/yonaskolb/XcodeGen): required if you modify `project.yml` and want to regenerate `.xcodeproj`

### Command-line build

```bash
# Clone the repository
git clone https://github.com/JH-Clipsync/ClipSync-Mac.git
cd ClipSync-Mac

# Build directly with xcodebuild (Release)
xcodebuild -project ClipSync.xcodeproj \
  -scheme ClipSync \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# Output is at build/Build/Products/Release/ClipSync.app
```

### With Xcode

```bash
# If you modified project.yml, regenerate the project first
brew install xcodegen
xcodegen generate

# Open the project
open ClipSync.xcodeproj
```

In Xcode, select the `ClipSync` scheme and press ⌘R to run. On first run you'll need to enable permissions for ClipSync under **System Settings → Privacy & Security → Accessibility / Clipboard**.

### Generating a DMG (optional)

CI uses [create-dmg](https://github.com/create-dmg/create-dmg):

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

## 🔐 Privacy & Security

| Aspect | Design |
|------|------|
| Data in transit | Goes through your own server; no third-party push/analytics services are involved. |
| Data storage | The server stores nothing; Mac-side data lives in `~/Library/Application Support/ClipSync/`. |
| Account info | Username, password, and Token are only kept in UserDefaults (locally) for reconnect and re-login. |
| History | `history.json` (latest 500 entries; can be cleared in one click from inside the app). |
| Logs | `logs/clipsync-YYYY-MM-DD.log` (daily rotation, local machine only). |
| End-to-end encryption | AES-256-GCM; keys are derived from the sync password via PBKDF2-HMAC-SHA256 (200,000 iterations); the salt is fixed on the client and never uploaded. |
| Fingerprint verification | The settings page shows the key fingerprint (e.g. `A1B2 C3D4 ...`) so you can compare it manually on both ends. |
| Least privilege | Doesn't read browsers or the file system; only uses the clipboard, Accessibility (to write to the clipboard), and network. |
| Production advice | Put Nginx / Caddy in front with TLS and use `wss://`. |

---

## 🐛 Troubleshooting

| Symptom | What to check |
|------|------|
| The menu bar icon doesn't appear | Confirm the system is macOS 14+; check Activity Monitor for any leftover `ClipSync` process. |
| Can't connect to the server | Check address/port, firewall, and whether the server is running; prefer `ws://IP:port` over `localhost`. |
| Messages arrive but show decryption failure | The "sync password" differs between ends, or one end hasn't enabled E2EE; compare the key fingerprints on the settings page. |
| Copied content isn't uploaded | Check whether "Auto-upload clipboard" is enabled in Settings; verify Accessibility has been granted under System Settings → Privacy → Accessibility. |
| Remote content isn't written to the clipboard | macOS requires both "Accessibility" and "Clipboard" permissions; click "Permissions" on the settings page and check each item. |
| The verification-code button doesn't appear | Some SMS templates don't match the recognition rules; you can use the "Copy full text" button in the Toast as a fallback. |
| Launch at login doesn't work | Registered with `SMAppService`; the app must first be moved to `/Applications`; confirm under System Settings → General → Login Items. |
| Frequent disconnects and reconnects | Check whether the menu bar icon flickers between yellow and green; review the Mac's network proxy / VPN / sleep policy. |

Logs: `~/Library/Logs/ClipSync/`  
Config: `~/Library/Application Support/ClipSync/`

---

## 🤝 Related Projects

| Project | Tech stack | Link |
|------|--------|------|
| Server | Go + gorilla/websocket | https://github.com/JH-Clipsync/ClipSync-Server |
| Windows client | .NET 8 + WPF | https://github.com/JH-Clipsync/ClipSync-Windows |
| Android client | Kotlin + OkHttp | https://github.com/JH-Clipsync/ClipSync-Android |
| Admin backend | Go + Gin | https://github.com/JH-Clipsync/ClipSync-Admin |
| Admin frontend | Vue 3 + Vite | https://github.com/JH-Clipsync/ClipSync-Admin-Web |

---

## 📄 License

A personal, self-use project; feel free to study and modify the code.

---

**Made with ❤️ · Fully self-built across three platforms · Your privacy belongs to you**
