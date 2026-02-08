# 変更履歴 (Changelog)

このプロジェクトは [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

---

## [0.1.0] - 2026-02-08

### 🎉 初回リリース

#### 追加

- **Manual Inspector ウィザード**
  - PDF アップロード + 自動 PNG 変換 (pdftoppm 300 DPI)
  - サムネイルグリッドによるページ選択
  - Cropper.js によるマニュアルクロップ
  - Nudge コントロール (方向ボタンによる微調整)
  - キャプション・ラベル手入力
  - PTIF 自動生成 (vix/libvips)
  - IIIF Manifest 自動登録

- **IIIF サーバー**
  - Image API v3.0 (`/iiif/image/:identifier/...`)
  - Presentation API v3.0 (`/iiif/manifest/:identifier`)
  - info.json エンドポイント
  - タイルキャッシュ機構

- **データベース**
  - PostgreSQL + JSONB メタデータ
  - `pdf_sources`, `extracted_images`, `iiif_manifests` テーブル

- **認知アクセシビリティ**
  - 最小 60×60px のタッチターゲット
  - 高コントラストカラーパレット
  - ウィザードパターンによる線形フロー
  - 即時フィードバック

- **デプロイ**
  - マルチステージ Dockerfile (libvips + poppler-utils)
  - OTP リリースサポート
  - ヘルスチェックエンドポイント (`/api/health`)
