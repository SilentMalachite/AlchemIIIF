# Security Best Practices Report

作成日: 2026-04-27
対象: AlchemIIIF Phoenix/LiveView web application

## Executive Summary

重大度の高い懸念は 2 件です。第一に、公開 IIIF Image API が `ExtractedImage.status` を確認せず、レビュー前に生成された Manifest の識別子から非公開画像を配信できます。第二に、アップロードされた PDF と変換後ページ画像が `priv/static/uploads` 配下に保存され、`Plug.Static` で認証なしに配信されます。

Phoenix/Elixir 向けの専用参照資料は今回使用した `security-best-practices` スキル内にはありませんでした。そのため、Phoenix/LiveView の一般的なセキュリティ観点、リポジトリ内の実装、JS フロントエンド向け参照資料を照合しました。補助確認として `mix sobelow --config` と `mix sobelow --format txt --exit low` を実行し、Sobelow からの追加指摘はありませんでした。

## High

### S1. IIIF Image API が公開ステータスを確認せず、レビュー前画像を配信できる

- Severity: High
- Location: `lib/alchem_iiif_web/router.ex:74-86`, `lib/alchem_iiif_web/controllers/iiif/image_controller.ex:122-131`, `lib/alchem_iiif/pipeline/pipeline.ex:330-333`, `lib/alchem_iiif/pipeline/pipeline.ex:443-459`, `lib/alchem_iiif_web/live/inspector_live/finalize.ex:60-70`
- Evidence: `/iiif` は `:api` pipeline の公開スコープです。`ImageController.get_ptif_path/1` は Manifest から `ExtractedImage` を取得し、`ptif_path` の存在だけで配信します。`Pipeline.run_single_finalize/2` は管理者承認前でも Manifest を作成します。
- Impact: 認証済みユーザーが `/lab/finalize/:image_id` で Manifest 識別子を生成すると、管理者レビュー前でも `/iiif/image/:identifier/info.json` やタイル URL を共有でき、外部の未認証ユーザーが画像を閲覧できます。Manifest Controller は `published` を確認していますが、Image API 側が独立して配信するため承認ゲートを迂回します。
- Fix: `get_ptif_path/1` を Manifest と ExtractedImage の join クエリにし、`e.status == "published"` を必須にしてください。あわせて `run_single_finalize/2` で Manifest を作る流れを廃止または内部用に限定し、公開 Manifest は `approve_and_publish/1` のみで作成するのが安全です。
- Mitigation: draft/pending/rejected の identifier で `info.json` とタイルが 404/403 になる LiveView/Controller テストを追加してください。

### S2. アップロード成果物が静的公開配下に置かれ、未公開 PDF/ページ画像が認証なしで届く

- Severity: High
- Location: `lib/alchem_iiif_web.ex:20`, `lib/alchem_iiif_web/endpoint.ex:23-27`, `lib/alchem_iiif_web/live/inspector_live/upload.ex:81-92`, `lib/alchem_iiif/pipeline/pipeline.ex:67-86`, `lib/alchem_iiif_web/controllers/iiif/metadata_helper.ex:80-99`, `lib/alchem_iiif_web/live/gallery_live.ex:658-663`
- Evidence: `static_paths` に `uploads` が含まれ、`Plug.Static` が `/uploads/...` を配信します。アップロード PDF は `priv/static/uploads/pdfs` にコピーされ、変換後ページ画像も `priv/static/uploads/pages/:pdf_source_id` に保存されます。
- Impact: 下書き、変換中、差し戻し、レビュー待ちの PDF やページ画像でも、URL を知っていれば認証なしで取得できます。ファイル名は元ファイル名と秒単位タイムスタンプ、ページ画像は連番 ID とページ名で構成されるため、内部ユーザー、ログ閲覧者、参照ヘッダー、ブラウザ履歴などから URL が漏れるとそのまま公開になります。
- Fix: 元 PDF と作業用ページ画像は `priv/static` の外に保存し、所有者確認または公開ステータス確認を行う Controller から `send_download`/`send_file` してください。公開が必要な成果物だけを別の公開ディレクトリへコピーするか、署名付き短期 URL を使ってください。
- Mitigation: すぐに移動できない場合でも、少なくとも未公開用と公開用の保存先を分け、ファイル名には推測しにくい UUID/ランダム値を使ってください。

## Medium

### S3. PdfSource 単位の公開 Manifest が未公開ソースの書誌メタデータを返す

- Severity: Medium
- Location: `lib/alchem_iiif_web/router.ex:74-86`, `lib/alchem_iiif_web/controllers/iiif/presentation_controller.ex:25-41`, `lib/alchem_iiif_web/controllers/iiif/presentation_controller.ex:48-64`, `lib/alchem_iiif_web/controllers/iiif/metadata_helper.ex:40-61`, `lib/alchem_iiif_web/controllers/iiif/metadata_helper.ex:80-99`
- Evidence: `/iiif/presentation/:source_id/manifest` は公開 API です。Controller は `Repo.get(PdfSource, source_id)` が成功すれば Manifest を返し、画像だけを `list_published_images_by_source/1` で絞っています。PdfSource 自体の `workflow_status` や公開画像の有無は公開判定に使われていません。
- Impact: 連番 `source_id` を列挙すると、公開画像がないプロジェクトでも `report_title`, `investigating_org`, `survey_year`, `site_code`, `license_uri`, 原本 PDF URL などのメタデータが露出します。S2 と組み合わさると、未公開 PDF の URL も到達可能になります。
- Fix: 少なくとも公開済み画像が 1 件以上ある場合のみ Manifest を返してください。より明確には `workflow_status == "approved"` などの公開条件を PdfSource 側にも持たせ、未公開ソースは 404 にするのが安全です。
- Mitigation: 外部公開 ID は DB の連番ではなくランダムな public id にしてください。

### S4. PDF 変換処理にページ数・時間・同時実行の上限がなく、認証済みユーザーによる DoS に弱い

- Severity: Medium
- Location: `lib/alchem_iiif_web/live/inspector_live/upload.ex:45`, `lib/alchem_iiif/ingestion/pdf_processor.ex:62-72`, `lib/alchem_iiif/ingestion/pdf_processor.ex:89-102`, `lib/alchem_iiif/ingestion/pdf_processor.ex:139-155`, `lib/alchem_iiif/workers/user_worker.ex:52-69`
- Evidence: LiveView upload は 500MB PDF を許可します。`pdfinfo` でページ数は取得していますが上限チェックがなく、`Task.async_stream` は `timeout: :infinity` です。`UserWorker` は cast ごとに `Task.start` するため、同一ユーザーや複数セッションから重い変換を並列起動できます。
- Impact: 悪意ある、または侵害された認証済みアカウントが巨大 PDF、多ページ PDF、細工された PDF を投入すると、CPU、メモリ、ディスク、外部コマンドプロセスを長時間占有できます。
- Fix: PDF サイズ上限を再検討し、ページ数上限、変換時間上限、ユーザー単位/全体のジョブ上限、ディスク使用量上限を入れてください。PDF 処理はキューに載せ、同時実行を明示的に制御するのが安全です。
- Mitigation: `pdfinfo` 後に上限超過を即エラーにし、`pdftoppm` 実行にも OS レベルの timeout/rlimit を付けてください。

## Low

### S5. CSP がリポジトリ上で確認できず、Sobelow 設定でも CSP/HTTPS 警告が抑制されている

- Severity: Low
- Location: `lib/alchem_iiif_web/router.ex:12`, `.sobelow-conf:8-19`
- Evidence: browser pipeline では `put_secure_browser_headers` を使用していますが、検索範囲内に Content-Security-Policy の明示設定はありません。`.sobelow-conf` では `Config.CSP` と `Config.HTTPS` が ignore されています。
- Impact: 現時点で明確な DOM XSS sink は見つかりませんでしたが、将来 XSS が混入した場合の緩和層が弱くなります。HTTPS はデプロイ先のプロキシで担保している可能性があるため、本報告では TLS 不備としては扱いません。
- Fix: Phoenix 側またはリバースプロキシで CSP を設定してください。LiveView を考慮し、`default-src 'self'`, `script-src 'self'`, `connect-src 'self' ws: wss:`, `img-src 'self' data: blob:` などから始め、必要な外部リソースだけを追加してください。
- Mitigation: レポート専用の CSP report-only を本番相当環境で先に観測すると導入しやすいです。

### S6. LiveView event の `String.to_existing_atom/1` が不正値でプロセスクラッシュを起こせる

- Severity: Low
- Location: `lib/alchem_iiif_web/live/inspector_live/upload.ex:69-70`, `lib/alchem_iiif_web/live/inspector_live/label.ex:127-145`, `lib/alchem_iiif_web/live/inspector_live/label.ex:151-161`, `lib/alchem_iiif_web/live/inspector_live/label.ex:269-296`
- Evidence: クライアントから送られる `tab` や `field` を `String.to_existing_atom/1` に渡しています。存在しない atom 名を送ると例外になります。
- Impact: atom leak ではありませんが、認証済みユーザーが LiveView プロセスをクラッシュさせられます。通常は接続単位の影響に留まりますが、ログノイズや supervisor restart を誘発します。
- Fix: `case field do "caption" -> :caption ... end` のような allowlist 変換に置き換え、未許可値は `{:noreply, socket}` または validation error にしてください。

## Positive Observations

- SQL は Ecto のパラメータ化されたクエリが中心で、検索の `fragment` も bind parameter を使用しています。
- first-party JS では `innerHTML`, `document.write`, `eval`, `new Function`, `postMessage`, browser storage の危険な使い方は見つかりませんでした。
- `DownloadController` は公開ダウンロード前に `status == "published"` を確認しています。
- `mix sobelow --config` と `mix sobelow --format txt --exit low` は追加指摘なしで完了しました。

