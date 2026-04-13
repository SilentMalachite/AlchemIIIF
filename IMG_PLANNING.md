# 画像ファイル取り込み機能の実装計画

## Context

AlchemIIIF は現在 PDF のみを受け付けている。考古学報告書のスキャン画像（TIFF, JPEG 等）を直接取り込めるようにする。変換には外部 Go バイナリ `pdf2png`（PDF→PNG、MuPDF ベース）と `img2png`（画像→PNG）を使用し、いずれも PNG を出力する。PNG 以降のパイプライン（クロップ、PTIFF 生成、IIIF 配信）は変更不要。

### 外部ツール仕様

| ツール | 入力 | CLI | 出力 |
|--------|------|-----|------|
| `pdf2png` | PDF | `./pdf2png report.pdf` | `report.zip`（`page_01.png, page_02.png, ...`） |
| `img2png` | 単体画像 | `./img2png photo.jpg` | `photo.png`（同ディレクトリ） |
| `img2png` | フォルダ | `./img2png photos/` | `photos.zip`（フラット化 PNG） |

`img2png` 対応形式: TIFF, JPEG, WebP, BMP, GIF（初フレーム）

---

## 設計方針

### テーブル名の維持

`pdf_sources` テーブルのリネームは行わない。リネームすると全コンテキスト関数・LiveView・テスト・マイグレーションに波及する。代わりに `source_type` カラムを追加し、既存レコードは `"pdf"` デフォルトで互換性を保つ。

### pdf2png による pdftoppm 置換

現行の `pdftoppm` チャンク処理を `pdf2png` に置換する。`pdf2png` は MuPDF ベースで高速かつ日本語フォントに強い。ZIP 出力のため、チャンク分割ロジックは不要になる。安全のため設定フラグでフォールバック可能にする。

### 統一出力ディレクトリ

PDF・画像どちらのソースも `priv/static/uploads/pages/{source_id}/` に PNG を配置する。下流（Browse, Crop, Label, Finalize, PTIFF, IIIF API）は変更不要。

---

## 実装ステップ

### Step 1: DB マイグレーション

**新規ファイル**: `priv/repo/migrations/TIMESTAMP_add_source_type_to_pdf_sources.exs`

```elixir
alter table(:pdf_sources) do
  add :source_type, :string, null: false, default: "pdf"
  add :original_file_count, :integer  # 画像ソース: アップロード数
end
```

既存データは `source_type: "pdf"` で自動補完。

### Step 2: PdfSource スキーマ更新

**変更ファイル**: `lib/alchem_iiif/ingestion/pdf_source.ex`

- `field :source_type, :string, default: "pdf"` 追加
- `field :original_file_count, :integer` 追加
- `changeset/2` の cast に `:source_type`, `:original_file_count` 追加
- `validate_inclusion(:source_type, ["pdf", "image"])` 追加

### Step 3: バイナリパス解決モジュール

**新規ファイル**: `lib/alchem_iiif/ingestion/binary_paths.ex`

- `pdf2png_path/0`, `img2png_path/0` を提供
- 優先順位: 環境変数 `PDF2PNG_PATH` / `IMG2PNG_PATH` → `config :alchem_iiif, :binaries` → `priv/bin/{arch}/` → `System.find_executable/1`
- `:os.type()` + `:erlang.system_info(:system_architecture)` でプラットフォーム検出

**設定追加** (`config/config.exs`):
```elixir
config :alchem_iiif, :binaries, pdf2png: nil, img2png: nil
```

**テスト設定** (`config/test.exs`):
```elixir
config :alchem_iiif, :binaries,
  pdf2png: "test/support/stubs/pdf2png",
  img2png: "test/support/stubs/img2png"
```

### Step 4: ZIP 展開ヘルパー

**新規ファイル**: `lib/alchem_iiif/ingestion/zip_helper.ex`

- `extract_pngs(zip_path, output_dir)` — Erlang `:zip.unzip/2` で展開、PNG のみ抽出・ソート
- ファイル名サニタイズ（パストラバーサル防止）
- ネスト展開・重複名のハンドリング

### Step 5: PdfProcessor の pdf2png 対応

**変更ファイル**: `lib/alchem_iiif/ingestion/pdf_processor.ex`

現行フロー: `pdfinfo` → `pdftoppm` チャンク → PNG
新フロー: `pdf2png {pdf_path}` → ZIP → `ZipHelper.extract_pngs` → PNG

- `convert_to_images/3` の内部実装を分岐:
  - `config :alchem_iiif, :pdf_converter` が `:pdf2png`（デフォルト）→ 新ロジック
  - `:pdftoppm` → 既存ロジック（フォールバック）
- 新 private 関数 `run_pdf2png(pdf_path, output_dir, opts)`:
  1. `BinaryPaths.pdf2png_path()` でバイナリパス取得
  2. `System.cmd(binary, [abs_pdf_path])` 実行
  3. 生成された ZIP を `ZipHelper.extract_pngs/2` で展開
  4. `collect_and_rename_images/1`（既存）でタイムスタンプ付与
- チャンク関連関数（`build_chunks`, `run_pdftoppm_chunk`, `broadcast_chunk_progress`）は `:pdftoppm` フォールバック用に残す
- `get_page_count/1` は ZIP 内のファイル数から導出

### Step 6: ImageConverter モジュール（新規）

**新規ファイル**: `lib/alchem_iiif/ingestion/image_converter.ex`

```elixir
@doc """
画像ファイルを PNG に変換します。
戻り値は PdfProcessor.convert_to_images/3 と同じ形式。
"""
def convert_images(file_paths, output_dir, opts \\ %{})
```

ロジック:
- 単一ファイル: `img2png {file_path}` → `{basename}.png` を `output_dir` に移動
- 複数ファイル: 一時ディレクトリにコピー → `img2png {tmp_dir}/` → ZIP 展開 → `output_dir` に移動
- `collect_and_rename_images` パターンでタイムスタンプ付与
- 戻り値: `{:ok, %{page_count: N, image_paths: [...]}}` | `{:error, reason}`
- 進捗: `opts[:user_id]` があれば PubSub でファイル単位の進捗をブロードキャスト

### Step 7: Pipeline に画像抽出関数追加

**変更ファイル**: `lib/alchem_iiif/pipeline/pipeline.ex`

新規公開関数:
```elixir
def run_image_extraction(source, file_paths, pipeline_id, opts \\ %{})
```

`run_pdf_extraction/4` と同じ構造:
1. `broadcast_progress` — 開始通知
2. 一時ディレクトリ作成 → `ImageConverter.convert_images/3`
3. PNG を `priv/static/uploads/pages/{source.id}/` に移動
4. PdfSource ステータス `"ready"` に更新、`page_count` 設定
5. `bulk_create_extracted_images` で一括 DB 登録
6. 完了通知 → PubSub ブロードキャスト
7. `after` ブロックで一時ディレクトリ削除

### Step 8: UserWorker に画像処理関数追加

**変更ファイル**: `lib/alchem_iiif/workers/user_worker.ex`

```elixir
def process_images(user_id, source, file_paths, pipeline_id)
```

内部で `Pipeline.run_image_extraction/4` を Task で非同期実行。完了時に `pdf_pipeline_topic(user_id)` へブロードキャスト。

### Step 9: Upload LiveView の画像対応

**変更ファイル**: `lib/alchem_iiif_web/live/inspector_live/upload.ex`

#### mount 変更
```elixir
|> allow_upload(:images,
  accept: ~w(.tiff .tif .jpeg .jpg .webp .bmp .gif),
  max_entries: 100,
  max_file_size: 100_000_000  # 100MB/ファイル
)
```

#### タブ追加
3タブ構成: 「PDF アップロード」「画像アップロード」「要修正」

#### 新イベント `"upload_images"`
1. `consume_uploaded_entries(socket, :images, ...)` で各ファイルを `priv/static/uploads/originals/{source_id}/` に保存
2. `Ingestion.create_pdf_source(%{source_type: "image", ...})` でレコード作成
3. `UserWorker.process_images/4` に委譲

#### 画像アップロード UI
- マルチファイルドラッグ&ドロップゾーン
- ファイルリスト + 個別プログレスバー
- カラーモード切替は非表示（画像には不要）

#### 進捗ハンドラ
既存の `handle_info({:extraction_progress, ...})` と `handle_info({:extraction_complete, ...})` をそのまま流用。

### Step 10: Ingestion コンテキスト更新

**変更ファイル**: `lib/alchem_iiif/ingestion.ex`

- `create_image_source/1`: `source_type: "image"` をマージして `create_pdf_source/1` を呼ぶヘルパー
- `hard_delete_pdf_source/1`: 画像ソースの場合 `uploads/originals/{id}/` も削除

### Step 11: 下流 LiveView の軽微な UI 調整

- `lab_live/index.ex`: ソースタイプに応じたアイコン表示（PDF/画像）
- `inspector_live/browse.ex`: 見出しをソースタイプで切り替え

---

## ファイルストレージ全体像

```
priv/static/uploads/
  pdfs/                         # 元 PDF（既存）
  originals/                    # 元画像ファイル（新規）
    {source_id}/
      scan_001.tiff
      scan_002.jpg
  pages/                        # 変換後 PNG（共通出力先）
    {source_id}/
      page-001-{ts}.png
      page-002-{ts}.png
```

---

## 変更対象ファイル一覧

| 区分 | ファイル |
|------|---------|
| 新規 | `priv/repo/migrations/..._add_source_type_to_pdf_sources.exs` |
| 新規 | `lib/alchem_iiif/ingestion/binary_paths.ex` |
| 新規 | `lib/alchem_iiif/ingestion/zip_helper.ex` |
| 新規 | `lib/alchem_iiif/ingestion/image_converter.ex` |
| 新規 | `test/support/stubs/pdf2png` (シェルスクリプト) |
| 新規 | `test/support/stubs/img2png` (シェルスクリプト) |
| 変更 | `lib/alchem_iiif/ingestion/pdf_source.ex` |
| 変更 | `lib/alchem_iiif/ingestion/pdf_processor.ex` |
| 変更 | `lib/alchem_iiif/pipeline/pipeline.ex` |
| 変更 | `lib/alchem_iiif/workers/user_worker.ex` |
| 変更 | `lib/alchem_iiif_web/live/inspector_live/upload.ex` |
| 変更 | `lib/alchem_iiif/ingestion.ex` |
| 変更 | `config/config.exs` |
| 変更 | `config/test.exs` |

---

## 検証方法

1. **ユニットテスト**: `mix test` — 各新規モジュールのテスト（バイナリスタブ使用）
2. **手動テスト（PDF）**: PDF アップロード → `pdf2png` で変換 → Browse 画面で PNG 確認
3. **手動テスト（画像）**: TIFF/JPEG をアップロード → `img2png` で変換 → Browse 画面確認
4. **E2E**: Upload → Label → Crop → Finalize の全フロー（PDF・画像両方）
5. **品質ゲート**: `mix review`（compile --warnings-as-errors + credo + sobelow + dialyzer）

---

## リスクと緩和策

| リスク | 緩和策 |
|--------|--------|
| pdf2png 置換で既存 PDF パイプライン破損 | `:pdf_converter` 設定フラグで pdftoppm にフォールバック可能 |
| Go バイナリの配布・プラットフォーム差異 | 環境変数 → config → priv/bin → PATH の4段フォールバック |
| 大量画像（100枚）のアップロード UX | LiveView 組み込みの per-entry プログレスで対応 |
| ZIP 展開時のパストラバーサル | ZipHelper でファイル名サニタイズ・絶対パス拒否 |
