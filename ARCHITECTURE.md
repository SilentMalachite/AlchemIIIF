# アーキテクチャ設計書

## 概要

AlchemIIIF は **モジュラー・モノリス** アーキテクチャを採用した Elixir/Phoenix アプリケーションです。
「取り込み (Ingestion)」「検索 (Search)」「配信 (Delivery)」を明確なモジュール境界で分離しつつ、
単一コードベースの運用効率を維持します。

**Stage-Gate モデル** により、内部作業空間 (Lab) と公開空間 (Museum) を分離し、
承認フローを通じて品質を管理します。

---

## モジュール構成

```
┌──────────────────────────────────────────────────────────────────┐
│                         AlchemIIIF                               │
├──────────────────┬──────────────────┬────────────────────────────┤
│  取り込みモジュール │  検索モジュール   │       配信モジュール        │
│  (Ingestion)     │  (Search)        │    (IIIF Delivery)        │
├──────────────────┼──────────────────┼────────────────────────────┤
│ • PDF アップロード │ • 全文検索 (FTS) │ • Image API v3.0          │
│ • pdftoppm 変換   │ • ファセット検索  │ • Presentation API v3.0   │
│ • 手動クロップ    │ • メタデータ検索  │ • タイルキャッシュ          │
│ • PTIF 生成       │                  │ • JSON-LD Manifest        │
│ • メタデータ入力  │                  │                            │
└────────┬─────────┴────────┬─────────┴──────────────┬─────────────┘
         │                  │                        │
         ▼                  ▼                        ▼
┌──────────────────────────────────────────────────────────────────┐
│                     PostgreSQL (JSONB)                            │
│  pdf_sources | extracted_images | iiif_manifests                  │
└──────────────────────────────────────────────────────────────────┘
```

### パイプラインモジュール

```
┌───────────────────────────────────────────────────────┐
│              並列処理パイプライン (Pipeline)              │
├──────────────────────────┬────────────────────────────┤
│  Pipeline               │  ResourceMonitor             │
│  (オーケストレーター)    │  (GenServer)                 │
├──────────────────────────┼────────────────────────────┤
│ • Task.async_stream     │ • CPU コア数検出            │
│ • PubSub 進捗通知     │ • メモリガード (20%)       │
│ • バッチ PDF 抽出      │ • 動的並列度計算          │
│ • バッチ PTIF 生成    │ • UI 用 1コア予約         │
└──────────────────────────┴────────────────────────────┘
```

### Stage-Gate フロー

```
Lab (内部)                 承認ゲート              Museum (公開)
────────────                ──────────              ──────────────
Upload → Browse →          ApprovalLive            GalleryLive
Crop → Finalize            (pending_review →       (published のみ表示)
(status: draft)             published)
       ↓                       ↓                       ↓
  SearchLive               ステータス変更          IIIF API 配信
  (Lab 内検索)
```

---

## データフロー

### 取り込みパイプライン (Ingestion)

```
PDF ファイル
    │  ① アップロード (/lab)
    ▼
[pdftoppm] ──── 300 DPI PNG 生成
    │
    ▼
サムネイルグリッド (/lab/browse/:id)
    │  ② ユーザーがページ選択
    ▼
Cropper.js ──── 手動クロップ + Nudge 調整 (/lab/crop/:id)
    │  ③ メタデータ手入力 (caption, label, site, period, artifact_type)
    ▼
[vix/libvips] ── クロップ画像 → PTIF 生成 (/lab/finalize/:id)
    │
    ▼
PostgreSQL ──── geometry(JSONB) + metadata 保存
                IIIF Manifest レコード登録
                status: draft
```

### 承認パイプライン (Stage-Gate)

```
Lab (draft) → 承認申請 (pending_review) → 承認 (published) → Museum
                                         ↗
                 差し戻し → (draft に戻る)
```

### 配信パイプライン (Delivery)

```
IIIF クライアント (Mirador, Universal Viewer 等)
    │
    ▼
/iiif/manifest/{id} ──── JSON-LD Manifest 返却 (published のみ)
    │
    ▼
/iiif/image/{id}/{region}/{size}/{rotation}/{quality}
    │
    ├── キャッシュあり → priv/static/iiif_cache から配信
    │
    └── キャッシュなし → [vix] PTIF からタイル生成
                              → キャッシュ保存
                              → レスポンス返却
```

---

## データスキーマ

### Entity-Relationship 図

```
┌──────────────┐    1:N    ┌────────────────────────┐    1:1    ┌────────────────┐
│ pdf_sources  │ ────────> │   extracted_images     │ ────────> │ iiif_manifests │
├──────────────┤           ├────────────────────────┤           ├────────────────┤
│ id           │           │ id                     │           │ id             │
│ filename     │           │ pdf_source_id(FK)      │           │ extracted_     │
│ page_count   │           │ page_number            │           │   image_id(FK) │
│ status       │           │ image_path             │           │ identifier     │
│ inserted_at  │           │ geometry (JSONB)       │           │ metadata(JSONB)│
│ updated_at   │           │ caption                │           │ inserted_at    │
└──────────────┘           │ label                  │           │ updated_at     │
                           │ ptif_path              │           └────────────────┘
                           │ status                 │
                           │ site                   │
                           │ period                 │
                           │ artifact_type          │
                           │ inserted_at            │
                           │ updated_at             │
                           └────────────────────────┘
```

### status カラムのライフサイクル

| 値 | 説明 |
|:---|:---|
| `draft` | 初期状態（Lab で作成直後） |
| `pending_review` | 承認申請済み |
| `published` | 承認済み・公開中 |

### JSONB カラムの詳細

**`extracted_images.geometry`** — クロップ座標

```json
{
  "x": 150,
  "y": 200,
  "width": 800,
  "height": 600
}
```

**`iiif_manifests.metadata`** — IIIF メタデータ (多言語)

```json
{
  "label": {
    "en": ["Figure 3: Pottery excavation"],
    "ja": ["第3図: 土器出土状況"]
  },
  "summary": {
    "en": ["Archaeological report figure"],
    "ja": ["考古学報告書の図版"]
  }
}
```

---

## ルーティング構成

| パス | モジュール | 説明 |
|:---|:---|:---|
| `/` | `PageController` | トップページ |
| `/gallery` | `GalleryLive` | 公開ギャラリー (Museum) |
| `/lab` | `InspectorLive.Upload` | Lab: PDF アップロード |
| `/lab/browse/:id` | `InspectorLive.Browse` | Lab: ページ選択 |
| `/lab/crop/:id` | `InspectorLive.Crop` | Lab: クロップ |
| `/lab/finalize/:id` | `InspectorLive.Finalize` | Lab: 保存 |
| `/lab/search` | `SearchLive` | Lab: 検索 |
| `/lab/approval` | `ApprovalLive` | Lab: 承認管理 |
| `/iiif/image/:id/...` | `ImageController` | IIIF Image API v3.0 |
| `/iiif/manifest/:id` | `ManifestController` | IIIF Presentation API v3.0 |
| `/api/health` | `HealthController` | ヘルスチェック |

---

## IIIF API 仕様

### Image API v3.0

| パラメータ | 説明 | 例 |
|:---|:---|:---|
| `identifier` | 画像の一意識別子 | `img-42-12345` |
| `region` | 切り出し領域 | `full`, `0,0,500,500` |
| `size` | 出力サイズ | `max`, `800,` |
| `rotation` | 回転角度 | `0`, `90`, `180`, `270` |
| `quality` | 画質 | `default`, `color`, `gray` |
| `format` | 出力フォーマット (拡張子) | `jpg`, `png`, `webp` |

**info.json レスポンス例:**

```json
{
  "@context": "http://iiif.io/api/image/3/context.json",
  "id": "https://example.com/iiif/image/img-42-12345",
  "type": "ImageService3",
  "protocol": "http://iiif.io/api/image",
  "width": 4000,
  "height": 3000,
  "profile": "level1"
}
```

### Presentation API v3.0

IIIF 3.0 仕様に準拠した JSON-LD Manifest を返却します。
Canvas、AnnotationPage、Annotation の階層構造を含みます。

---

## フロントエンドアーキテクチャ

### LiveView + JS Hook 統合

```
LiveView (Elixir)              JS Hook (JavaScript)
────────────────               ──────────────────────
  ↓ push_event                   ↓ Cropper.js 初期化
  "nudge_crop"  ─────────────>  setData() で位置調整
                                   ↓ cropend イベント
  handle_event  <─────────────  pushEvent("update_crop_data")
  "update_crop_data"           getData(true) を送信
```

### 認知アクセシビリティの設計原則

1. **最小認知負荷**: 一画面で一つのタスクのみ
2. **大きなタッチターゲット**: 全ボタン最小 60×60px
3. **明確なフィードバック**: 全操作に視覚的確認
4. **破壊的操作の保護**: 確認ダイアログ必須
5. **線形ナビゲーション**: 前後のみの移動（ジャンプ不可）

### ギャラリーテーマ: 新潟インディゴ＆ハーベストゴールド

公開ギャラリー (`/gallery`) には専用のダークテーマを適用しています。
CSS 変数で `.gallery-container` スコープにのみ適用し、Lab / Admin 画面に影響しません。

| 役割 | 変数名 | HEX | 用途 |
|:---|:---|:---|:---|
| Base Layer | `--gallery-bg` | `#1A2C42` | ギャラリー背景 |
| Accent | `--gallery-accent` | `#E6B422` | ボタン、アクティブボーダー、ホバー |
| Typography | `--gallery-text` | `#E0E0E0` | 本文テキスト (コントラスト比 ≈ 10.4:1) |
| Surface | `--gallery-surface` | `#243B55` | カード背景 |
| Muted | `--gallery-text-muted` | `#A0AEC0` | 補助テキスト、メタ情報 |

---

## 品質チェックパイプライン

`mix review` コマンドで以下を4ステップで逐次実行します：

```
① mix compile --warnings-as-errors    → コンパイル警告ゼロ
② mix credo --strict                  → コードスタイル検査
③ mix sobelow --config                → セキュリティ解析
④ mix dialyzer                        → 型チェック
⑤ mix review.summary                  → PASS/FAIL サマリー
```

各ステップは失敗時に即座に停止し、サマリータスクが実行されることが全チェック通過を意味します。

### 設定ファイル

| ファイル | 役割 |
|:---|:---|
| `.credo.exs` | コードスタイルルール・ノイズ抑制 |
| `.sobelow-conf` | セキュリティチェック設定・除外ルール |
| `.dialyzer_ignore.exs` | 既知の型警告除外 |
