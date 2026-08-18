<p align="center"><img src="icon.png" width="128" alt="ClipSync"/></p>

<h1 align="center">ClipSync for macOS</h1>

<p align="center">
  <b>スマホの認証コード & クリップボード → Mac の通知バナーへ、ワンクリックでコピー。</b><br/>
  <a href="README.md">简体中文</a> ·
  <a href="README.en.md">English</a> ·
  <a href="README.ja.md">日本語</a>
</p>

---

ClipSync は、セルフホスト型のクロスデバイス・メッセージ同期ツールです。本リポジトリは macOS デスクトップクライアントで、**Swift + SwiftUI** で開発され、**メニューバー常駐アプリ**として動作します。

主なユースケース：**スマホで認証コードを受信したり、何かをコピーしたりすると、Mac の右上に Toast 通知が即座に表示され、認証コードや全文をワンクリックでコピーできます。逆に Mac でコピーしたテキストや画像も、他のデバイスへリアルタイムに同期されます。**

サードパーティのプッシュサービスには依存せず、すべての通信は自分自身の WebSocket 中継サーバーを経由します。エンドツーエンド暗号化も任意で有効化でき、プライバシーは自分自身で管理できます。

> システム要件：**macOS 14 (Sonoma) 以降** · 開発ツール：**Xcode 16+** · 言語：**Swift 5.10**

---

## ✨ 主な機能

| モジュール | 説明 |
|------|------|
| 🔐 **ユーザー名/パスワードログイン** | ユーザー名 + パスワードで認証し、初回接続時に JWT Token を自動取得します。Token の期限切れ時は、ローカルに保存した認証情報で自動的に再ログインします。 |
| 👥 **オンラインデバイス一覧** | WebSocket Presence をリアルタイムで受信し、同じアカウントのオンラインデバイスのプラットフォーム / IP / デバイス ID / オンライン時刻 / 機能タグをメイン画面に表示します。 |
| 🛡️ **エンドツーエンド暗号化** | AES-256-GCM で暗号化し、鍵は PBKDF2-HMAC-SHA256（20 万回）で導出します。サーバーは暗号文を中継するだけで、両端の鍵フィンガープリントを表示して突き合わせられます。 |
| 🔔 **Toast 通知バナー** | 画面右上にフローティング表示され、デバイスのオンライン/オフライン通知、認証コードの自動認識、ワンクリックコピーを提供します。フォーカスは奪いません。 |
| 📩 **認証コードのスマート認識** | 受信したテキスト/SMS を正規表現で自動抽出し、Toast 内に「認証コードをコピー」ボタンを表示します。 |
| 📋 **クリップボード双方向同期** | テキストと PNG 画像を双方向に同期します。ローカルの変更はデバウンスでアップロードし、リモートの内容は MIME タイプに応じてクリップボードへ書き戻します。 |
| 🍎 **メニューバー常駐** | `MenuBarExtra` のステータスバーアイコン：緑＝接続済み、黄＝接続中、赤＝切断、灰＝無効。クリックでクイックパネルを開きます。 |
| 🧭 **初回起動ガイド** | サーバーアドレス、アカウント情報、エンドツーエンド暗号化、クリップボード/アクセシビリティ権限の設定を順に案内します。 |
| ⚙️ **設定ページ** | サーバーアドレス、アカウント、暗号化の切り替え / 同期パスワード、クリップボードの自動アップロード、リモート内容の自動反映、ログイン時起動を設定できます。 |
| 🪟 **権限ガイド** | クリップボードアクセス（オートメーション）、アクセシビリティ、通知の各権限を検出し、システム設定へワンクリックで遷移します。 |
| 🔄 **自動再接続** | 指数バックオフ（1s → 2s → 4s … 最大 30s）で再接続し、ネットワーク復帰後に Presence とクリップボード監視を自動的に再開します。 |
| 📜 **メッセージ履歴** | 直近 500 件のメッセージ（SMS / テキスト / 画像）をローカルに保存し、種類別のフィルタ、コピー、削除、全件消去に対応します。 |
| 🚀 **ログイン時起動** | `SMAppService` でログイン項目を登録し、ワンクリックで切り替え可能。アクセシビリティ権限は不要です。 |
| 🖼️ **画像圧縮** | 200KB を超える画像は、最長辺 1600px になるよう等倍でリサイズし、JPEG 0.8 で圧縮してからアップロードします。 |

---

## 🖼️ 画面構成

| エリア | 説明 |
|------|------|
| メニューバーアイコン | 色で接続状態をリアルタイムに表示します。左クリックでメインパネル、右クリックでクイックメニューを開きます。 |
| メインページ | ステータスカード + 現在のアカウント/暗号化状態 + オンラインデバイス一覧 + 最近のメッセージ。 |
| 設定 | サーバー、アカウント、エンドツーエンド暗号化、クリップボード同期、ログイン時起動、権限設定への入口。 |
| 履歴 | SMS / クリップボードで分類表示し、テキストと画像をプレビュー、コピーや削除が可能です。 |
| Toast バナー | 画面右上にフローティング表示され、認証コードは専用の強調ボタンになります。最大 3 件までスタックします。 |

---

## 📦 ダウンロードとインストール

[GitHub Releases](https://github.com/JH-Clipsync/ClipSync-Mac/releases) からダウンロードしてください：

| ファイル | 用途 |
|------|----------|
| `ClipSync-<バージョン>-arm64.dmg` | Apple Silicon（M1 / M2 / M3 / M4）Mac（推奨） |
| `ClipSync-<バージョン>-x86_64.dmg` | Intel チップ搭載 Mac |
| `ClipSync-<バージョン>-universal.dmg` | 両方のアーキテクチャに対応するユニバーサルバイナリ（ファイルサイズは大きめ） |

> アプリは Apple Developer の署名/公証を受けていません。初回起動時に「開けない」と表示された場合は、**システム設定 → プライバシーとセキュリティ** で「このまま開く」をクリックするか、「アプリケーション」フォルダでアプリを右クリック → 開く を選択してください。

---

## 🚀 クイックスタート

1. `ClipSync.app` を「アプリケーション」フォルダにドラッグして起動します。
2. 初回起動時はセットアップウィザードが表示されます：
   - **サーバーアドレス**を入力します（例: `192.168.1.10:8080`。`ws://` / `wss://` に対応。プレフィックスを省略すると自動的に `ws://` が補われます）。
   - 管理者から割り当てられた**ユーザー名 / パスワード**を入力します（初回接続時に Token が自動取得されます）。
   - **エンドツーエンド暗号化**を有効にするか選択し、同期パスワードを入力します（両端で一致させる必要があります）。
   - 案内に従って**クリップボード書き込み**と**アクセシビリティ**の権限を許可します。
3. 「接続」をクリックし、メニューバーアイコンが**緑色**になれば接続成功です。
4. スマホ版（[ClipSync-Android](https://github.com/JH-Clipsync/ClipSync-Android)）または Windows 版（[ClipSync-Windows](https://github.com/JH-Clipsync/ClipSync-Windows)）で同じアカウントにログインすると、同期が始まります。

---

## 🧩 プロジェクト構成

```
ClipSync-Mac/
├── ClipSync/
│   ├── main.swift                  # エントリーポイント: MenuBarExtra + AppRouter
│   ├── AppRouter.swift             # ページルーティング（ガイド / メイン / 設定 / 履歴）
│   ├── ContentView.swift           # メインウィンドウコンテナ
│   ├── HomeView.swift              # メインページ: ステータスカード + オンラインデバイス + 最近のメッセージ
│   ├── SettingsView.swift          # 設定ページ: サーバー/アカウント/暗号化/同期/ログイン時起動
│   ├── HistoryView.swift           # メッセージ履歴（SMS / クリップボードタブ）
│   ├── ToastView.swift             # 右上通知バナー UI
│   ├── ToastManager.swift          # Toast キュー、スタック、自動消去
│   ├── ToastStyle.swift            # Toast の色/アイコンスタイル定義
│   │
│   ├── WSClient.swift              # WebSocket 接続、Presence、自動再接続、メッセージ振り分け
│   ├── AuthClient.swift            # ユーザー名/パスワードログイン、Token キャッシュ、自動再ログイン
│   ├── ServerAddress.swift         # アドレス正規化（ws/wss 補完、パス除去）
│   │
│   ├── Models.swift                # SyncMessage / MessagePayload / OnlineDevice
│   ├── E2EECrypto.swift            # AES-256-GCM + PBKDF2 の下位実装
│   ├── E2EEEnvelope.swift          # 暗号化エンベロープのパック/アンパック + フィンガープリント計算
│   ├── SmsCodeExtractor.swift      # 認証コードの正規表現認識（中国語/英語テンプレート）
│   │
│   ├── ClipboardMonitor.swift      # ローカルクリップボードのポーリング監視（0.6 秒、重複除去付き）
│   ├── ClipboardWriter.swift       # リモートメッセージをクリップボードへ書き戻し（テキスト / PNG）
│   │
│   ├── SettingsStore.swift         # UserDefaults 設定の読み書き
│   ├── HistoryStore.swift          # 履歴の永続化（JSON、最大 500 件）
│   │
│   ├── FingerprintLabel.swift      # 鍵フィンガープリント表示コンポーネント
│   ├── SyncPasswordField.swift     # 同期パスワード入力（表示/非表示切り替え）
│   ├── RevealPasswordField.swift   # 汎用パスワード入力フィールド
│   ├── Info.plist                  # LSUIElement=1（Dock アイコンなし）
│   └── Assets.xcassets/
├── ClipSync.xcodeproj/
├── project.yml                     # XcodeGen プロジェクト定義
└── .github/workflows/release.yml   # GitHub Actions: arm64/x86_64 デュアルアーキ + DMG
```

### 技術スタック

- **Swift 5.10** + **SwiftUI**（`@main` + `MenuBarExtra`）
- 最小システム：**macOS 14.0**（`MenuBarExtra`、`Observable`、`SMAppService`）
- ネットワーク：ネイティブの `URLSessionWebSocketTask`
- 暗号化：システム標準の `CryptoKit`（`AES.GCM` + `PBKDF2` + `SHA256`）
- 永続化：`UserDefaults` + アプリサンドボックスの `Application Support` ディレクトリ内 JSON
- プロジェクト生成：[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`project.yml`）
- CI/CD：GitHub Actions で `.app` をパッケージ → `create-dmg` で DMG 生成 → Release を公開

---

## 🔧 ソースからのビルド

### 前提条件

- macOS 14 以降
- [Xcode 16+](https://developer.apple.com/xcode/)
- （任意）[XcodeGen](https://github.com/yonaskolb/XcodeGen)：`project.yml` を変更して `.xcodeproj` を再生成する場合に必要です。

### コマンドラインビルド

```bash
# リポジトリをクローン
git clone https://github.com/JH-Clipsync/ClipSync-Mac.git
cd ClipSync-Mac

# xcodebuild で直接ビルド（Release）
xcodebuild -project ClipSync.xcodeproj \
  -scheme ClipSync \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# 成果物は build/Build/Products/Release/ClipSync.app
```

### Xcode を使う場合

```bash
# project.yml を変更した場合は、先にプロジェクトを再生成
brew install xcodegen
xcodegen generate

# プロジェクトを開く
open ClipSync.xcodeproj
```

Xcode で `ClipSync` スキームを選択し、⌘R で実行します。初回実行時は **システム設定 → プライバシーとセキュリティ → アクセシビリティ / クリップボード** で ClipSync の権限を有効にしてください。

### DMG の生成（任意）

CI では [create-dmg](https://github.com/create-dmg/create-dmg) を使用しています：

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

## 🔐 プライバシーとセキュリティ

| 観点 | 設計 |
|------|------|
| 通信経路 | 自分自身のサーバーを経由し、サードパーティのプッシュ/分析サービスは通りません。 |
| データ保存 | サーバー側には保存されません。Mac 側のデータは `~/Library/Application Support/ClipSync/` にあります。 |
| アカウント情報 | ユーザー名、パスワード、Token は UserDefaults（ローカル）にのみ保存され、切断時の再接続と再ログインに使用されます。 |
| 履歴 | `history.json`（直近 500 件。アプリ内からワンクリックで消去可能）。 |
| ログ | `logs/clipsync-YYYY-MM-DD.log`（日次ローテーション、ローカルマシンのみ）。 |
| エンドツーエンド暗号化 | AES-256-GCM。鍵は同期パスワードから PBKDF2-HMAC-SHA256（20 万回）で導出され、ソルトはクライアントに固定され、アップロードされません。 |
| フィンガープリント確認 | 設定ページに鍵フィンガープリント（例: `A1B2 C3D4 ...`）を表示し、両端で目視で突き合わせられます。 |
| 最小権限 | ブラウザやファイルシステムは読み取らず、クリップボード、アクセシビリティ（クリップボード書き込み用）、ネットワークのみを使用します。 |
| 本番運用の推奨 | Nginx / Caddy でリバースプロキシして TLS を有効化し、`wss://` を利用してください。 |

---

## 🐛 トラブルシューティング

| 症状 | 確認事項 |
|------|------|
| メニューバーアイコンが表示されない | macOS 14 以降であることを確認し、「アクティビティモニタ」で `ClipSync` プロセスが残っていないか確認してください。 |
| サーバーに接続できない | アドレス/ポート、ファイアウォール、サーバーの起動状態を確認し、`localhost` ではなく `ws://IP:ポート` の使用を推奨します。 |
| メッセージは届くが復号に失敗する | 両端の「同期パスワード」が一致しないか、片方が E2EE を有効にしていません。設定ページの鍵フィンガープリントを照合してください。 |
| コピー内容がアップロードされない | 設定の「クリップボードを自動アップロード」がオンか確認し、システム設定 → プライバシー → アクセシビリティで権限が許可されているか確認してください。 |
| リモート内容がクリップボードに書き込まれない | macOS では「アクセシビリティ」と「クリップボード」の両方の権限が必要です。設定ページの「権限」から各項目を確認してください。 |
| 認証コードボタンが表示されない | 一部の SMS テンプレートは認識ルールに一致しません。Toast の「全文をコピー」ボタンを代替として利用できます。 |
| ログイン時起動が機能しない | `SMAppService` で登録するため、アプリを先に `/Applications` へ移動する必要があります。システム設定 → 一般 → ログイン項目 で確認してください。 |
| 頻繁に切断/再接続する | メニューバーアイコンが黄色と緑の間で頻繁に切り替わっていないか確認し、Mac のネットワークプロキシ / VPN / スリープ設定を見直してください。 |

ログの場所：`~/Library/Logs/ClipSync/`  
設定の場所：`~/Library/Application Support/ClipSync/`

---

## 🤝 関連プロジェクト

| プロジェクト | 技術スタック | リンク |
|------|--------|------|
| サーバー | Go + gorilla/websocket | https://github.com/JH-Clipsync/ClipSync-Server |
| Windows クライアント | .NET 8 + WPF | https://github.com/JH-Clipsync/ClipSync-Windows |
| Android クライアント | Kotlin + OkHttp | https://github.com/JH-Clipsync/ClipSync-Android |
| 管理バックエンド | Go + Gin | https://github.com/JH-Clipsync/ClipSync-Admin |
| 管理フロントエンド | Vue 3 + Vite | https://github.com/JH-Clipsync/ClipSync-Admin-Web |

---

## 📄 License

個人利用のプロジェクトです。コードは自由に参照・改変いただけます。

---

**Made with ❤️ · 3 クライアントすべて自作 · プライバシーはあなたのもの**
