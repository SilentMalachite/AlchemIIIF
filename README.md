# AlchemIIIF

[![Elixir](https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.8+-E8562A?logo=phoenix-framework)](https://www.phoenixframework.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15+-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![IIIF](https://img.shields.io/badge/IIIF-v3.0-2873AB)](https://iiif.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

> **PDF 考古学報告書を IIIF アセットに変換する Elixir/Phoenix アプリケーション**

AlchemIIIF は、静的な PDF の考古学報告書を、国際的な画像相互運用フレームワーク [IIIF (International Image Interoperability Framework)](https://iiif.io/) に準拠したリッチなデジタルアセットに変換するためのツールです。

就労継続支援の現場で利用されることを想定し、**認知アクセシビリティ**を最優先にした UI 設計を採用しています。

---

## ✨ 主な特徴

### 🧙 ウィザード型インスペクタ (Lab)

![Lab Wizard Interface](priv/static/images/lab_wizard.png)

直感的な 4 ステップのウィザード形式で、PDF から IIIF アセットを作成します。

| ステップ | 内容 |
|:---:|:---|
| **1. アップロード** | PDF をアップロードすると、全ページが自動的に高解像度 PNG に変換されます |
| **2. ページ選択** | サムネイルグリッドから図版を含むページを選択します |
| **3. クロップ** | Cropper.js を使って図版の範囲を指定します。方向ボタンで微調整も可能です |
| **4. 保存** | PTIF を生成し、メタデータを PostgreSQL に保存します |

### 🏛️ Stage-Gate ワークフロー (Lab → Museum)

品質管理のため、内部作業と公開を明確に分離しています。

| ステージ | 説明 |
|:---:|:---|
| **Lab (内部)** | 作業者が PDF をアップロード・クロップ・注釈を付ける内部ワークスペース |
| **承認** | 管理者が内容を確認し、公開を承認します |
| **Museum (公開)** | 承認されたアセットのみが表示される公開ギャラリー |

### 🔍 検索・発見

- **全文検索**: キャプションの PostgreSQL FTS (tsvector + GIN インデックス)
- **ファセット検索**: 遺跡名・時代・遺物種別によるフィルタリング

### ♿ 認知アクセシビリティ

- **大きなボタン**: 全ての操作ボタンは最小 60×60px
- **高コントラスト**: WCAG 準拠のカラーパレット
- **線形フロー**: ウィザードパターンで迷わない操作
- **Nudge コントロール**: 方向ボタンによるクロップ範囲の微調整（精密なドラッグ操作が不要）
- **即時フィードバック**: 明確な成功・エラーメッセージ
- **手動入力**: AI による自動抽出は行わず、全ての選択は人が行います

### 🖼️ IIIF v3.0 準拠

- **Image API v3.0**: PTIF からの動的タイル生成 + キャッシュ
- **Presentation API v3.0**: JSON-LD 形式の Manifest（英語/日本語対応）

---

## 🛠️ 技術スタック

| カテゴリ | 技術 |
|:---|:---|
| 言語 / フレームワーク | Elixir 1.15+ / Phoenix 1.8+ (LiveView) |
| データベース | PostgreSQL 15+ (JSONB メタデータ) |
| 画像処理 | [vix](https://github.com/akash-akya/vix) (libvips ラッパー) |
| PDF 変換 | [poppler-utils](https://poppler.freedesktop.org/) (pdftoppm) |
| フロントエンド | Phoenix LiveView + [Cropper.js](https://github.com/fengyuanchen/cropperjs) |
| コンテナ | Docker (マルチステージビルド) |

---

## 🚀 セットアップ

### 前提条件

以下のソフトウェアがインストールされている必要があります：

- **Elixir** 1.15 以上
- **Erlang/OTP** 24 以上
- **PostgreSQL** 15 以上
- **libvips** (画像処理)
- **poppler-utils** (PDF 変換)
- **Node.js** / npm (アセットビルド)

#### macOS (Homebrew)

```bash
brew install elixir postgresql@15 vips poppler node
```

#### Ubuntu / Debian

```bash
sudo apt install elixir erlang postgresql libvips-dev poppler-utils nodejs npm
```

### インストール手順

```bash
# 1. リポジトリをクローン
git clone https://github.com/SilentMalachite/AlchemIIIF.git
cd AlchemIIIF

# 2. 依存パッケージをインストール
mix setup

# 3. （必要に応じて）データベース設定を編集
#    config/dev.exs の username / password を環境に合わせてください

# 4. 開発サーバーを起動
mix phx.server
```

ブラウザで [`http://localhost:4000/lab`](http://localhost:4000/lab) にアクセスしてください。

---

## 📖 使い方

### 1. PDF をアップロード

`/lab` にアクセスし、考古学報告書の PDF ファイルをアップロードします。
アップロードされた PDF は自動的に 300 DPI の PNG 画像に変換されます。

### 2. ページを選択

変換されたページがサムネイルグリッドとして表示されます。
図版や挿絵を含むページをクリックして選択してください。

### 3. 図版をクロップ

Cropper.js を使用して、ページ上の図版の範囲を指定します。

- **ドラッグ操作**: 画像上でドラッグして範囲を選択
- **Nudge ボタン** (↑↓←→): 5px 単位で範囲を微調整

キャプション（図の説明）、ラベル（識別名）、メタデータ（遺跡名・時代・遺物種別）を入力してください。

### 4. 保存

確認画面で内容を確認し、「保存」を押します。
システムが以下を自動的に行います：

1. クロップ画像の生成
2. ピラミッド型 TIFF (PTIF) への変換
3. IIIF Manifest の登録

### 5. 承認・公開

`/lab/approval` で管理者が内容を確認し、承認すると `/gallery` に公開されます。

### 6. 検索

`/lab/search` で、遺跡名・時代・遺物種別・キャプションから画像を検索できます。

### IIIF エンドポイント

保存完了後、以下のエンドポイントからアクセスできます：

```
# Manifest (JSON-LD)
GET /iiif/manifest/{identifier}

# Image API (タイル)
GET /iiif/image/{identifier}/{region}/{size}/{rotation}/{quality}

# Image Info
GET /iiif/image/{identifier}/info.json
```

---

## 🐳 Docker デプロイ

```bash
# イメージをビルド
docker build -t alchem_iiif .

# コンテナを起動
docker run -d \
  -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/alchem_iiif_prod" \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST="your-domain.com" \
  alchem_iiif

# データベースマイグレーション
docker exec <container_id> /app/bin/migrate
```

詳細なデプロイ手順は [DEPLOYMENT.md](DEPLOYMENT.md) を参照してください。

---

## 📦 OTP リリースビルド

Docker を使わずにローカルでリリースビルドを作成できます。

### 前提条件

- Elixir 1.15+ / Erlang/OTP 24+
- PostgreSQL 15+
- libvips / poppler-utils
- Node.js / npm

### ビルド手順

```bash
# 1. 本番用依存を取得
MIX_ENV=prod mix deps.get

# 2. npm 依存をインストール
cd assets && npm install && cd ..

# 3. アプリケーションをコンパイル
MIX_ENV=prod mix compile

# 4. アセットをビルド・ダイジェスト
MIX_ENV=prod mix assets.deploy

# 5. OTP リリースを生成
MIX_ENV=prod mix release
```

> **⚠️ 注意**: Phoenix 1.8 の colocated hooks を使用しているため、`mix compile` を `mix assets.deploy` より先に実行する必要があります。

### 起動

```bash
# 環境変数を設定
export DATABASE_URL="ecto://user:pass@localhost/alchem_iiif_prod"
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
export PHX_HOST="localhost"

# データベースマイグレーション
_build/prod/rel/alchem_iiif/bin/migrate

# サーバー起動
_build/prod/rel/alchem_iiif/bin/server
```

---

## 📁 ディレクトリ構成

```
AlchemIIIF/
├── lib/
│   ├── alchem_iiif/
│   │   ├── ingestion/               # 取り込みパイプライン
│   │   │   ├── pdf_source.ex            # PDF 管理スキーマ
│   │   │   ├── extracted_image.ex       # 抽出画像スキーマ
│   │   │   ├── pdf_processor.ex         # PDF→PNG 変換
│   │   │   └── image_processor.ex       # PTIF 生成・タイル切り出し
│   │   ├── iiif/
│   │   │   └── manifest.ex             # IIIF Manifest スキーマ
│   │   ├── ingestion.ex               # 取り込みコンテキスト
│   │   ├── search.ex                  # 検索コンテキスト
│   │   └── release.ex                # 本番マイグレーション
│   └── alchem_iiif_web/
│       ├── components/
│       │   ├── core_components.ex       # Phoenix 標準コンポーネント
│       │   └── wizard_components.ex     # 共通ウィザードコンポーネント
│       ├── live/
│       │   ├── inspector_live/          # Lab ウィザード LiveView
│       │   │   ├── upload.ex                # Step 1: アップロード
│       │   │   ├── browse.ex                # Step 2: ページ選択
│       │   │   ├── crop.ex                  # Step 3: クロップ
│       │   │   └── finalize.ex              # Step 4: 保存
│       │   ├── search_live.ex           # 検索 LiveView
│       │   ├── approval_live.ex         # 承認 LiveView
│       │   └── gallery_live.ex          # 公開ギャラリー LiveView
│       └── controllers/iiif/           # IIIF API
│           ├── image_controller.ex      # Image API v3.0
│           └── manifest_controller.ex   # Presentation API v3.0
├── assets/js/hooks/
│   └── image_inspector_hook.js         # Cropper.js 統合フック
├── priv/repo/migrations/              # DB マイグレーション
├── test/                              # テストコード
├── Dockerfile                         # マルチステージビルド
├── IIIF_SPEC.md                      # 仕様書
├── ARCHITECTURE.md                   # アーキテクチャ設計
├── DEPLOYMENT.md                     # デプロイ手順書
└── CONTRIBUTING.md                   # 開発参加ガイドライン
```

---

## 📄 ドキュメント

| ドキュメント | 内容 |
|:---|:---|
| [IIIF_SPEC.md](IIIF_SPEC.md) | 開発仕様書 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | アーキテクチャ設計 |
| [DEPLOYMENT.md](DEPLOYMENT.md) | デプロイ手順書 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 開発参加ガイドライン |
| [CHANGELOG.md](CHANGELOG.md) | 変更履歴 |

---

## 📜 ライセンス

MIT License — 詳細は [LICENSE](LICENSE) を参照してください。

---

## 🙏 謝辞

- [IIIF (International Image Interoperability Framework)](https://iiif.io/)
- [Phoenix Framework](https://www.phoenixframework.org/)
- [vix (libvips Elixir wrapper)](https://github.com/akash-akya/vix)
- [Cropper.js](https://github.com/fengyuanchen/cropperjs)
