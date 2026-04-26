# ZIPされた複数PNG対応の検討メモ

## 目的

ZIPで固められた複数のPNG画像ファイルを、このアプリの既存Labワークフローで読み込めるようにする。

対象は、既存の以下フローへの統合。

- `/lab/upload`
- `/lab/browse/:pdf_source_id`
- `/lab/crop/:pdf_source_id/:page_number`
- `/lab/label/:image_id`
- `/lab/finalize/:image_id`

## 現状把握

現在の取り込みフローは PDF 前提で構築されている。

- `AlchemIiifWeb.InspectorLive.Upload`
  - `allow_upload(:pdf, accept: ~w(.pdf), max_entries: 1, ...)`
  - PDFを `priv/static/uploads/pdfs` に保存
  - `Ingestion.create_pdf_source/1` で親レコードを作成
  - `PdfProcessingDispatcher` / `Pipeline.run_pdf_extraction/4` に委譲

- `AlchemIiif.Pipeline`
  - `PdfProcessor.convert_to_images/3` で PDF を PNG 群へ変換
  - 出力先は `priv/static/uploads/pages/<pdf_source.id>`
  - その後 `ExtractedImage` を bulk insert

- `InspectorLive.Browse`
  - `uploads/pages/<pdf_source.id>` 以下の `.png` を一覧表示
  - 各ページから Crop に進む

- `InspectorLive.Crop`
  - ページPNGを元画像としてクロップ
  - `ExtractedImage` の `image_path` を使う

- Gallery / IIIF
  - `pdf_source.filename` を元に原本PDFへのリンクや IIIF `rendering` を生成している
  - `MetadataHelper.build_rendering/1` や Gallery の PDF ダウンロードリンクは PDF 原本の存在を前提としている

## 今回ここまでで決めた前提

### 1. UI方針

ZIP対応は既存Labに統合する。

- `/lab/upload` で PDF と ZIP の両方を受け付ける
- 新しい専用フローは作らない
- 既存の Browse / Crop / Label / Finalize を再利用する

### 2. ZIP原本の扱い

ZIPは展開後に破棄する前提にする。

- ZIPファイル自体は原本として残さない
- Gallery や IIIF の `rendering` に ZIP へのリンクは出さない
- 再処理時に ZIP を再利用する前提は置かない

### 3. ZIP内ファイルの扱い

ZIP内の PNG は「ページ扱い」とする。

- 各 PNG を Browse 一覧に並べる
- 必要なら Crop してから Label / Finalize に進む
- 「すでに完成済み図版」として Crop を飛ばす設計にはしない

### 4. ZIP内の並び順ルール

ZIP内の PNG は以下のルールで取り込む。

- サブフォルダ内も含めて再帰的に拾う
- PNG 以外は無視する
- 相対パスの自然順で並べる
- その順で `page_number` を振る

## 取り得る実装方針

### 案A: 最小変更

既存の `pdf_source` / PDF 前提命名をほぼ維持したまま、ZIPを横入り対応する。

利点:
- 変更量が少ない
- 早く実装できる

懸念:
- `pdf_source` という名前と実態がズレる
- UI文言や IIIF 周辺で PDF 前提の特例分岐が増える
- 後から保守しづらい

### 案B: 中庸設計

`PdfSource` は当面維持しつつ、`source_type` などを追加して PDF/ZIP 両対応にする。

利点:
- 既存フローを活かせる
- PDF 前提の分岐を明示化できる
- 影響範囲と整合性のバランスがよい

懸念:
- `PdfSource` の名称自体は少し意味ずれが残る
- 各所で `source_type` 分岐が必要になる

### 案C: 本格整理

`PdfSource` をより汎用的な概念へ再編し、取り込みモデル全体を一般化する。

利点:
- 概念として最もきれい
- 今後 JPEG / TIFF / ZIP など拡張しやすい

懸念:
- 影響範囲が大きい
- 今回の目的に対してはオーバーになりやすい

## 現時点の推奨方針

案Bの中庸設計が最も妥当。

想定する骨子は以下。

- `pdf_sources` は当面維持
- ただし `source_type` を追加して `pdf` / `zip` を区別する
- PDF は既存の `PdfProcessor` を使う
- ZIP は新しい `ZipProcessor` で展開する
- 両者とも最終的には `page_count` と `image_paths` を返し、同じ登録処理へ流す
- 最終出力は従来どおり `priv/static/uploads/pages/<source.id>` に揃える

これにより、Browse/Crop/Label/Finalize 側はなるべく変更を小さくできる。

## 具体的な実装イメージ

### Upload

`InspectorLive.Upload` を拡張する。

- PDF/ZIP の両方を受け付ける
- 文言も「PDFファイル」固定から一般化する
- 保存先は source_type ごとに整理する
  - PDF: `priv/static/uploads/pdfs`
  - ZIP: 一時保存 or 専用保存領域
- `create_pdf_source/1` 相当の親レコード作成時に `source_type` を持たせる

### Pipeline

`Pipeline.run_pdf_extraction/4` 相当を整理し、入力ソースの種別で処理を分ける。

- `pdf`:
  - 既存 `PdfProcessor.convert_to_images/3`
- `zip`:
  - `ZipProcessor.extract_pngs/2` のような新処理

共通化したい出口:

- `page_count`
- `image_paths`
- `uploads/pages/<source.id>` に正規化済みPNGが並ぶこと
- `ExtractedImage` を bulk insert すること

### ZIP展開

`ZipProcessor` では以下を満たす必要がある。

- `:zip` を使って一時ディレクトリへ展開
- Zip Slip 対策
  - `..` を含む危険パスは拒否
  - 絶対パスも拒否
- PNGのみ採用
- 再帰的に収集
- 相対パスの自然順でソート
- 最終的に `page-001-<timestamp>.png` のような命名へ正規化
- PNGが1件もなければエラー

### Browse / Crop

既存の挙動を極力維持する。

- Browse は `uploads/pages/<source.id>` のPNG一覧を見るだけなので、大きな変更は不要そう
- ZIP由来でも「ページ一覧」として表示できる
- Crop は個々のPNGを元画像として扱えるため、そのまま流用できる見込み

### Gallery / IIIF / Metadata

PDF原本リンクは `source_type == "pdf"` のときだけ出す。

対象候補:

- `MetadataHelper.build_rendering/1`
- Gallery の原本PDFリンク
- PDF由来であることを前提にした文言

ZIP由来の source では:

- `rendering` を出さない
- Gallery 上の原本リンクも出さない

### 再処理 / 削除

ZIPは破棄前提なので、PDFと同じ再処理はできない。

- PDF:
  - 既存の再処理を維持
- ZIP:
  - 再処理不可
  - 必要なら再アップロード

削除処理も種別で考慮が必要。

- PDF:
  - PDF本体 + 展開ページ群 + 画像群の削除
- ZIP:
  - 展開ページ群 + 画像群の削除
  - ZIP原本は残さない前提

## 影響が大きい箇所

- `lib/alchem_iiif_web/live/inspector_live/upload.ex`
- `lib/alchem_iiif/pipeline/pipeline.ex`
- `lib/alchem_iiif/ingestion/pdf_source.ex`
- `lib/alchem_iiif/ingestion.ex`
- `lib/alchem_iiif_web/controllers/iiif/metadata_helper.ex`
- `lib/alchem_iiif_web/live/gallery_live.ex`

加えて、新規の ZIP 展開モジュールが必要になる可能性が高い。

## テスト観点

最低限、以下は必要。

### Upload / LiveView

- ZIP を受け付けられる
- PDF も従来どおり受け付けられる
- source_type が正しく保存される
- ZIP由来でも完了後に Browse へ遷移する

### ZIP展開

- PNG を再帰収集できる
- 非PNGを無視する
- 相対パスの自然順で並ぶ
- PNGが1件もない ZIP はエラー
- 危険パスを含む ZIP は拒否される

### Pipeline

- ZIP成功時に `ExtractedImage` が正しく作成される
- ZIP失敗時に source の status が error になる
- PDF 既存挙動が壊れていない

### Gallery / IIIF

- PDF source は従来どおり `rendering` が出る
- ZIP source は `rendering` が出ない
- Gallery でも ZIP 由来 source に原本リンクが出ない

## 残っている検討ポイント

いまの前提で大きな方向性は固まっているが、次の実装前には最終確認が必要。

- `source_type` を `pdf_sources` に追加するか、別のモデリングにするか
- ZIP保存を完全にスキップするか、一時保存して即削除するか
- ZIP由来 source の UI 表示名をどうするか
  - `pdf_source.filename` のまま使うか
  - より中立な表示文言へ寄せるか
- ZIP由来 source の再処理ボタンや導線をどう見せるか

## 現時点の結論

最も現実的なのは、既存Labフローを維持しながら `source_type` 導入で PDF/ZIP 両対応にする中庸案。

この案なら、

- 既存の Browse / Crop / Label / Finalize を再利用できる
- ZIP内PNGを「ページ扱い」で自然に流せる
- Gallery / IIIF では PDF にだけ原本リンクを残せる
- 変更量を抑えつつ、PDF前提の歪みを最小限にできる

今後はこの内容をベースに、実装計画へ落とし込むのがよさそう。
