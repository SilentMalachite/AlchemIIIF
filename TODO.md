# TODO

最終確認日: 2026-04-04 (v0.2.23 リリース整理済み)

## 現状の実装状況

- 認証と権限管理は実装済み。`phx.gen.auth` ベースのログイン導線に加え、`admin` / `user` の RBAC と、`PdfSource.user_id` / `ExtractedImage.owner_id` を使った所有権スコープが入っている。
- Lab 側の作業導線は実装済み。`/lab` 配下にプロジェクト一覧、プロジェクト詳細、Upload、Browse、Crop、Label、Finalize、Search、Pipeline の各画面があり、5 ステップのウィザードフローで作業できる。
- PDF 取り込みは非同期化済み。`UserWorker`、`Pipeline`、`PdfProcessor` により、PDF のチャンク分割変換、進捗通知、Browse 画面への遷移まで一連の処理が動く。
- クロップ機能はポリゴン対応まで実装済み。Lab のクロップ UI、プレビュー表示、PTIFF 生成パイプライン、Gallery / Admin 側の表示もポリゴン前提に対応している。
- ラベリング、レビュー提出、管理者レビュー、承認公開の流れは実装済み。`draft` / `pending_review` / `rejected` / `published` と、プロジェクト単位の `wip` / `pending_review` / `returned` / `approved` が併用されている。
- Gallery は実装済み。公開済み画像の検索、ファセットフィルター（公開済み画像由来の値のみ表示）、「もっと見る」ページネーション、モーダル拡大表示、IIIF ベースの閲覧導線がある。
- IIIF 配信は実装済み。Image API v3 と、個別画像 Manifest / PdfSource 単位 Manifest の Presentation API エンドポイントが揃っている。
- 公開済み画像の高解像度クロップ画像ダウンロードは実装済み。`/download/:id` からサーバー側でクロップした画像を配信できる。
- 管理画面は実装済み。`/admin/review`、`/admin/users`、`/admin/dashboard`、`/admin/trash` があり、レビュー、ユーザー管理、画像管理、ゴミ箱管理を行える。
- ソフトデリートと復元は実装済み。プロジェクト削除は `deleted_at` ベースで管理され、Admin から復元または完全削除できる。
- 品質ゲートも整備済み。`mix review` と GitHub Actions CI の導線が README / mix タスクに整備されている。

## 品質メモ

- `mix test` は確認時点で **411 tests, 0 failures, 4 skipped**。
- `mix.exs` のアプリバージョンは **0.2.23**。
- `CHANGELOG.md` の `[0.2.23] - 2026-04-04` セクションにリリース済み。`[Unreleased]` は空。

## 次にやった方がいいこと

- [済] ~~未テストの主要画面・コントローラーのテストを追加する。~~
  対象7件すべてのテストファイルが追加済み（`InspectorLive.Crop`、`LabLive.Index`、`LabLive.Show`、`Admin.DashboardLive`、`AdminUserLive.Index`、`AdminTrashLive.Index`、`DownloadController`）。411 tests, 0 failures, 4 skipped で通過確認済み。
- [済] ~~公開ギャラリーのフィルター候補を `published` 画像由来の値だけに絞る。~~
  `Search.list_filter_options/1` に `published_only` オプションを追加し、Gallery では公開済み+PTIF生成済みの画像由来の値のみ表示するようにした。回帰テスト 4 件追加済み（`17dd9df`）。
- [済] ~~`CHANGELOG.md` の `Unreleased` 内容を次回リリースとして確定する。~~
  `[Unreleased]` を `[0.2.23] - 2026-04-04` に変換し、フィルター候補変更・CLAUDE.md 新設も追記。`mix.exs` を `0.2.23` に更新。README との整合性も確認済み。
- [中] 古くなったコメントやモジュールドキュメントを整理する。
  特にクロップ画面まわりには、現状の実装とずれて見える Phase 注記が残っているため、読んだ人が迷わない状態にしたい。
- [低] 招待制移行後も skip のまま残っている登録テストの扱いを決める。
  `UserRegistrationControllerTest` は現状のルーティングとずれているため、削除するか、招待制前提の別テストに置き換えるかを決めたい。

## メモ

主要機能はほぼ揃っており、次の重点はテスト補強・公開面の整合性・リリース整理。
