<p align="center">
  <img src="icon.png" width="120" alt="ClipSync"/>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a>
</p>

# ClipSync-Mac

<p align="center">
  <b>The macOS client of the ClipSync three-device sync system</b><br/>
  A menu bar resident utility: receive SMS verification codes from your phone in real time, and sync clipboard contents (text/images) bidirectionally.<br/>
  Pure Swift + SwiftUI, macOS 14+, Menu Bar Extra form factor, zero distraction.
</p>

<p align="center">
  <a href="https://github.com/JH-Clipsync/ClipSync-Mac/releases">⬇️ Download dmg/zip</a> ·
  <a href="https://github.com/orgs/JH-Clipsync/packages">📦 Packages (ghcr.io)</a> ·
  <a href="https://github.com/JH-Clipsync/ClipSync-Server">🖧 Server</a> ·
  <a href="https://github.com/JH-Clipsync/ClipSync-Android">📱 Android</a>
</p>

---

## 1. What It Can Do

| Feature | Description | Corresponding Module |
|---|---|---|
| **Receive verification codes** | SMS verification codes from the phone pop up on the Mac in real time; copy with one click / auto-write to clipboard | `WebSocketClient` + `ClipboardWriter` |
| **Bidirectional clipboard sync** | Copy on Mac → push to phone; copy on phone → write to Mac clipboard | `ClipboardMonitor` / `ClipboardWriter` |
| **Menu bar resident** | Status bar icon shows connection state (connected / disconnected / reconnecting); click to open the menu | `ClipSyncApp` (MenuBarExtra) |
| **Settings center** | Server address / Token / auto-write-to-clipboard switch / clipboard sync switch | `SettingsStore` + `SettingsView` |
| **Permission guidance** | Requesting and status detection for clipboard, accessibility, and other permissions | `PermissionHelper` + `PermissionsView` |
| **Toasts** | Lightweight toast when content is received, without stealing focus | `ToastOverlay` |
| **Auto-reconnect on disconnect** | Exponential backoff reconnect after WS disconnect, reflected in the status bar in real time | `ConnectionState` |

## 2. Download and Installation

Download from [Releases](https://github.com/JH-Clipsync/ClipSync-Mac/releases):

- `ClipSync-x.y.z.dmg`: double-click to open → drag into "Applications" (recommended)
- `ClipSync-x.y.z.zip`: unzip to get the `.app` and use it directly

If "Unable to verify developer" appears on first launch: System Settings → Privacy & Security → Open Anyway.

After launching:
1. The ClipSync icon appears in the menu bar;
2. Open Settings, fill in the **Server address** (`ws://server-ip:8080`) and **Token** (matching the phone end will auto-pair);
3. Grant clipboard permission as prompted; the icon turns green when connected.

## 3. Message Protocol (Agreed with the Server)

```json
{ "type": "notify_pc", "kind": "sms_code", "text": "[Some Bank] Verification code 314159" }
```

- The server broadcasts messages from `role=phone` under the same token to all `role=pc`; this client connects as `role=pc`;
- When this client copies clipboard content, it sends it upstream with the `clipboard` type; the phone end decides whether to write it to the clipboard based on its switch;
- The server does not persist data; it only routes in real time.

## 4. Building from Source

Requirements: macOS 14+, Xcode 16+ (project objectVersion 77).

```bash
# Command-line build (Release, unsigned)
xcodebuild -project ClipSync.xcodeproj -scheme ClipSync \
  -configuration Release \
  -archivePath build/ClipSync.xcarchive \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO archive

# Export .app
cp -R build/ClipSync.xcarchive/Products/Applications/ClipSync.app ./

# Or create a dmg
hdiutil create -volname "ClipSync" -srcfolder ClipSync.app -ov -format UDZO ClipSync.dmg
```

Or simply open `ClipSync.xcodeproj` in Xcode → ▶️ Run.

## 5. CI Automated Packaging

Pushing a tag automatically builds and publishes a Release + pushes a container image (macos-15 runner, Xcode 16.4):

```bash
git tag v1.2.0 && git push origin v1.2.0
```

Artifacts: `ClipSync-<version>.dmg` + `ClipSync-<version>.zip`, automatically attached to the Release page.

## 6. Project Structure

```
ClipSync/
├── ClipSyncApp.swift        # Entry: MenuBarExtra + settings window
├── ConnectionState.swift    # Connection state machine (disconnected/connecting/connected/reconnecting)
├── WebSocketClient.swift    # WS client: heartbeat, reconnect, message dispatch
├── ClipboardMonitor.swift   # Polls NSPasteboard; sends changes upstream
├── ClipboardWriter.swift    # Writes received content to NSPasteboard (including images)
├── SettingsStore.swift      # UserDefaults-persisted config (address/Token/switches)
├── Views/
│   ├── MenuBarView.swift    # Menu bar dropdown content
│   ├── SettingsView.swift   # Settings page
│   ├── PermissionsView.swift# Permission guidance page
│   └── ToastOverlay.swift   # Lightweight toast overlay
├── Helpers/
│   └── PermissionHelper.swift # Permission request/detection
├── Info.plist               # Version/permission declarations
└── Assets.xcassets          # Icon resources
```

## 7. FAQ

| Problem | Solution |
|---|---|
| Icon is gray and won't connect | Check address/Token; verify port 8080 is open on the server; use the same network or a public address |
| Clipboard not syncing | Turn on "Clipboard sync" in Settings; grant clipboard permission in System Settings |
| Not receiving phone pushes | Make sure the phone end service is running and using the same Token |
| Prompt says it can't be opened | Privacy & Security → Open Anyway (normal for unsigned distribution) |
| Want it to launch at login | System Settings → General → Login Items → add ClipSync |

## 8. System Requirements and Notes

- Minimum macOS 14.0; supports both Apple Silicon and Intel (CI produces Apple Silicon builds; Intel requires building from source)
- Bundle ID: `com.jiahui.ClipSyncApp`
- No data is collected; clipboard content only flows point-to-point between your devices and the server, and the server does not persist it
