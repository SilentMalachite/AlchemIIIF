# 変更履歴 (Changelog)

このプロジェクトは [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

---

## [0.2.3] - 2026-02-14

### 🎨 UI & レンダリング改善
- **SVG `viewBox` 方式による精密なクロップ表示を採用**
  - 公開ギャラリー (`/gallery`) および管理画面 (`/admin/review`) のカードにおいて、アスペクト比を維持した精密なプレビューを実現。
  - 背景をダークネイビーに統一し、余白が発生した場合も視覚的な整合性を維持。
- **ナッジコントロール（D-Pad）のスタイル刷新**
  - ゴールド枠＋透明背景のデザインに変更し、視認性とモダンな操作感を向上。
  - ホバー時にゴールドで塗りつぶされるインタラクティブなフィードバックを追加。

### 🛠️ 機能追加
- **管理画面での図版削除機能の実装**
  - `/admin/review` に「削除（ソフトデリート）」ボタンを追加。誤登録エントリの論理削除が可能に。
- **PTIF 生成の自動化プロセス改善**
  - ラベリング完了（Step 4: Save & Finish）時に、PTIF 生成ジョブをバックグラウンドで自動開始するよう改善。
- **ラベルのユニーク制約バリデーションの実装**
  - 同一 PDF 内でのラベル（図番号等）の重複をリアルタイムで検出し、警告を表示。
  - 重複がある場合は既存レコードへの編集リンクを表示し、データの整合性をサポート。
- **高解像度クロップ画像のダウンロード機能**
  - 公開ギャラリーに「ダウンロード」ボタンを追加。
  - 遺跡名とラベルを組み合わせたセマンティックな日本語ファイル名で保存可能。

### 🎮 操作性向上
- **クロップ保存のダブルクリック操作を導入**
  - クロップ範囲の決定（Step 3）において、選択範囲のダブルクリック（またはダブルタップ）による明示的な保存操作を導入。
  - 意図しない座標の保存を防止し、より確実な操作体験を提供。

---

## [0.2.2] - 2026-02-13

### 🎨 UI & テーマ
- **Admin Review Dashboard (`/admin/review`) を「新潟インディゴ＆ハーベストゴールド」テーマに対応**
  - 公開ギャラリーと視覚的に統一されたダークテーマ環境
  - ステータスに応じたカードボーダー（Pending: Gold, Approved: Green）
  - 高コントラストな Approve/Reject ボタン（60×60px）
  - ダークテーマに最適化された Inspector Panel とモーダル

### 🎮 操作性改善 (D-Pad)
- **Nudge コントロールを D-Pad (Directional Pad) レイアウトに刷新**
  - 3×3 CSS Grid による直感的な配置
  - ボタンサイズを 64×64px に拡大し、誤操作を防止
  - ナッジ量を 5px → 10px に変更
  - キーボードの矢印キーによる操作に対応（`phx-window-keydown`）
  - Undo ボタンを D-Pad 中央に統合

### ✂️ クロップ & レンダリング改善
- **Label 画面でのクロップ表示を SVG 方式に移行**
  - CSS スケールに依存しない、より精密なクロッププレビューを実現
- **提出プロセスの改善**
  - 保存・提出時にアイテムのステータスを自動的に `pending_review` へ更新

### 🛡️ セキュリティ & 品質
- **セキュリティ脆弱性の修正 (Sobelow)**
  - `pdf_processor`, `pipeline`, `image_controller`, `upload` におけるディレクトリトラバーサルおよび XSS リスクの低減
- **`mix review` パイプラインのパス**
  - 全チェック（Compile, Credo, Sobelow, Dialyzer）を通過

---

## [0.2.1] - 2026-02-13 (Retrospective)

### ✂️ クロップ機能の基礎改善

#### 変更

- **Cropper.js を廃止し、オリジナルの JavaScript Hook (`ImageSelection`) に移行**
  - CSS スケール（`object-fit: contain`）を考慮した正確な座標計算の実装
  - SVG オーバーレイの表示制御を JS 側に移行し、LiveView 更新時のチラつきや座標の跳びを解消
  - Harvest Gold テーマに合わせた選択範囲の視覚的フィードバックの強化

---

## [0.2.0] - 2026-02-11

### 🏛️ ランディングページ刷新 — デジタルミュージアムの入口

#### 追加

- **ランディングページ（`/`）を「新潟インディゴ＆ハーベストゴールド」テーマに全面刷新**
  - Deep Navy/Indigo (`#001f3f`) 背景 + Harvest Gold (`#d4af37`) アクセント
  - CTA ボタン「Enter the Digital Gallery」→ `/gallery` への一本道ナビゲーション
  - 最小 60×60px タッチターゲット（WM 70 認知アクセシビリティ対応）
  - ミニマリストフッターに `/lab`・`/admin` リンクを控えめ配置

#### 変更

- **ルーター構成の整理**
  - 公開スコープ（`/`, `/gallery`）と 内部スコープ（`/lab/*`）を分離
  - 将来の認証プラグ追加に備えた構造化
- **Tailwind CSS v4 `@source` ディレクティブ追加**
  - `.heex` テンプレートの自動スキャン対応

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
  - Lab (内部) / Gallery (公開) の分離
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
