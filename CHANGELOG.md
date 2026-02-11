# 変更履歴 (Changelog)

このプロジェクトは [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

---

## [0.1.2] - 2026-02-10

### 🛡️ Admin Review Dashboard

#### 追加

- **管理者レビュー機能 (`/admin/review`)**
  - 公開前の最終品質ゲートとして機能
  - Nudge Inspector による詳細確認とクロップ微調整
  - Validation Badge による自動チェック結果表示
  - 承認 (`published`) / 差し戻し (`draft`) のステータス管理
  - Optimistic UI によるスムーズな操作体験

## [0.1.1] - 2026-02-10

### 🎨 UI テーマ更新

#### 追加

- **公開ギャラリーテーマ: 新潟インディゴ＆ハーベストゴールド**
  - Deep Sea Indigo (`#1A2C42`) 背景によるダークテーマ化
  - Harvest Gold (`#E6B422`) アクセントカラーで操作フィードバック
  - Mist Grey (`#E0E0E0`) テキストで WCAG AAA 準拠のコントラスト比 (≈ 10.4:1)
  - ギャラリー専用カード・検索バー・フィルターチップスのダークスタイル適用
  - フィルターチップの `min-height` を 48px → 60px に引き上げ (WM 70 対応)
  - Hover/Active に Gold パレットの非言語フィードバック実装
  - CSS 変数 + `.gallery-container` スコープで Lab/Admin 画面に影響なし (Zero-Regression)

---

## [0.1.0] - 2026-02-09

### 🎉 初回リリース

#### 追加

- **Manual Inspector ウィザード（全5ステップ）**
  - Step 1: PDF アップロード + 自動 PNG 変換 (pdftoppm 300 DPI)
  - Step 2: サムネイルグリッドによるページ選択
  - Step 3: Cropper.js によるマニュアルクロップ + Nudge コントロール
  - Step 4: ラベリング（キャプション・ラベル・遺跡名・時代・遺物種別の手入力）
  - Step 5: レビュー提出（PTIF 自動生成 + IIIF Manifest 登録）
  - 共通ウィザードコンポーネント (`wizard_components.ex`)

- **IIIF サーバー**
  - Image API v3.0 (`/iiif/image/:identifier/...`)
  - Presentation API v3.0 (`/iiif/manifest/:identifier`)
  - info.json エンドポイント
  - タイルキャッシュ機構

- **検索機能**
  - 全文検索コンテキスト (`AlchemIiif.Search`)
  - 検索用 LiveView (`SearchLive`)
  - `extracted_images` への検索フィールド追加マイグレーション

- **Stage-Gate ワークフロー**
  - Lab (内部) / Museum (公開) の分離
  - 承認ワークフロー LiveView (`ApprovalLive`)
  - ギャラリー LiveView (`GalleryLive`)
  - `extracted_images` へのステータスカラム追加マイグレーション

- **データベース**
  - PostgreSQL + JSONB メタデータ
  - `pdf_sources`, `extracted_images`, `iiif_manifests` テーブル

- **認知アクセシビリティ**
  - 最小 60×60px のタッチターゲット
  - 高コントラストカラーパレット
  - ウィザードパターンによる線形フロー
  - 即時フィードバック

- **テスト**
  - コンテキスト・スキーマ・コントローラ・LiveView のテスト
  - テスト用ファクトリ (`test/support/factory.ex`)

- **並列処理パイプライン**
  - リソース適応型並列処理 (`AlchemIiif.Pipeline`)
  - CPU/メモリ自動検出・動的並列度調整 (`AlchemIiif.Pipeline.ResourceMonitor`)
  - メモリガード（空きメモリ 20% 未満で並列度縮小）
  - PubSub リアルタイム進捗通知

- **品質チェック (`mix review`)**
  - Credo コードスタイル検査 (`--strict`)
  - Sobelow セキュリティ解析
  - Dialyzer 型チェック
  - PASS/FAIL サマリータスク (`mix review.summary`)

- **デプロイ**
  - マルチステージ Dockerfile (libvips + poppler-utils)
  - OTP リリースサポート
  - ヘルスチェックエンドポイント (`/api/health`)
