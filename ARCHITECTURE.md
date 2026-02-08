# アーキテクチャ設計書

## 概要

AlchemIIIF は **モジュラー・モノリス** アーキテクチャを採用した Elixir/Phoenix アプリケーションです。
「取り込み (Ingestion)」と「配信 (Delivery)」を明確なモジュール境界で分離しつつ、
単一コードベースの運用効率を維持します。

---

## モジュール構成

```
┌─────────────────────────────────────────────────────────┐
│                    AlchemIIIF                           │
├──────────────────────┬──────────────────────────────────┤
│   取り込みモジュール │         配信モジュール            │
│   (Ingestion)       │         (IIIF Delivery)          │
├──────────────────────┼──────────────────────────────────┤
│ • PDF アップロード    │ • Image API v3.0                │
│ • pdftoppm 変換      │ • Presentation API v3.0         │
│ • 手動クロップ       │ • タイルキャッシュ               │
│ • PTIF 生成          │ • JSON-LD Manifest              │
│ • メタデータ入力     │                                  │
└──────────┬───────────┴──────────────┬───────────────────┘
           │                          │
           ▼                          ▼
┌──────────────────────────────────────────────────────────┐
│                  PostgreSQL (JSONB)                      │
│  pdf_sources | extracted_images | iiif_manifests         │
└──────────────────────────────────────────────────────────┘
```

---

## データフロー

### 取り込みパイプライン (Ingestion)

```
PDF ファイル
    │  ① アップロード
    ▼
[pdftoppm] ──── 300 DPI PNG 生成
    │
    ▼
サムネイルグリッド
    │  ② ユーザーがページ選択
    ▼
Cropper.js ──── 手動クロップ + Nudge 調整
    │  ③ メタデータ手入力
    ▼
[vix/libvips] ── クロップ画像 → PTIF 生成
    │
    ▼
PostgreSQL ──── geometry(JSONB) + metadata 保存
                IIIF Manifest レコード登録
```

### 配信パイプライン (Delivery)

```
IIIF クライアント (Mirador, Universal Viewer 等)
    │
    ▼
/iiif/manifest/{id} ──── JSON-LD Manifest 返却
    │
    ▼
/iiif/image/{id}/{region}/{size}/{rotation}/{quality}.{format}
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
┌──────────────┐    1:N    ┌───────────────────┐    1:1    ┌────────────────┐
│ pdf_sources  │ ────────> │ extracted_images  │ ────────> │ iiif_manifests │
├──────────────┤           ├───────────────────┤           ├────────────────┤
│ id           │           │ id                │           │ id             │
│ filename     │           │ pdf_source_id(FK) │           │ extracted_     │
│ page_count   │           │ page_number       │           │   image_id(FK) │
│ status       │           │ image_path        │           │ identifier     │
│ inserted_at  │           │ geometry (JSONB)  │           │ metadata(JSONB)│
│ updated_at   │           │ caption           │           │ inserted_at    │
└──────────────┘           │ label             │           │ updated_at     │
                           │ ptif_path         │           └────────────────┘
                           │ inserted_at       │
                           │ updated_at        │
                           └───────────────────┘
```

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
