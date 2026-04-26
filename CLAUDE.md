# CLAUDE.md

Claude Code (claude.ai/code) がこのリポジトリで作業するときの指示書。

## プロジェクト概要

**AlchemIIIF** — 考古学 PDF レポートを IIIF 準拠デジタル資産へ変換する Elixir/Phoenix 1.8 アプリ。
PDF → 画像化、ポリゴンクロップ、PTIFF タイル生成（libvips）、IIIF Image / Presentation API 配信を行う。

## 必須コマンド

| 用途 | コマンド |
|------|---------|
| 初期セットアップ | `mix setup` |
| 開発サーバ | `mix phx.server` (localhost:4000) |
| テスト全実行 | `mix test` |
| 単一ファイル | `mix test path/to/test.exs` |
| 行指定 | `mix test path/to/test.exs:42` |
| 失敗のみ再実行 | `mix test --failed` |
| フォーマット | `mix format` |
| 品質ゲート | `mix review`（compile `--warnings-as-errors` + credo `--strict` + sobelow + dialyzer）|
| プリコミット | `mix precommit`（compile + `deps.unlock --unused` + format + test）|

## ツール選択方針（最優先で守る）

1. **コード探索・読解は Serena MCP を優先** — `get_symbols_overview` → `find_symbol` → `find_referencing_symbols` → `search_for_pattern`。`Read` 全文読みはコンテキスト浪費なので最終手段。
2. **シンボル単位の編集は Serena の `replace_symbol_body` / `insert_after_symbol`** — 行ベースの `Edit` より安全で、Credo の構造制約に違反しにくい。
3. **広域探索（3 クエリ以上）は `Agent(subagent_type=Explore)`** — メインコンテキストを汚さない。
4. **新機能・大規模変更の前に `superpowers:brainstorming` → `writing-plans` → `executing-plans`** をこの順で。
5. **バグ・想定外挙動は `superpowers:systematic-debugging`** を経由してから修正。
6. **完了宣言の前に `superpowers:verification-before-completion`** で検証コマンドを実行。

## アーキテクチャ

### ドメイン層 `lib/alchem_iiif/`

| モジュール | 役割 |
|-----------|------|
| `Ingestion` | PDF→PNG 変換（poppler `pdftoppm` 300 DPI）、画像抽出 |
| `IIIF` | JSON-LD マニフェスト生成、PTIFF タイル生成（`vix`/libvips）|
| `Pipeline` | バッチ処理オーケストレータ。`ResourceMonitor` が CPU/メモリに応じて並列度を調整 |
| `Workers` | ユーザ単位 `GenServer`。`DynamicSupervisor` + `Registry` で管理 |
| `Search` | PostgreSQL FTS（tsvector + GIN）、ファセット絞り込み |
| `Accounts` | `phx.gen.auth` ベース、`:admin` / `:user` RBAC、`current_scope` 経由 |

### Web 層 `lib/alchem_iiif_web/`

- **LiveView**: Lab（内部作業）, Inspector（5 ステップウィザード）, Gallery（公開）, Search, Admin
- **Controller**: IIIF API、Download、Auth
- **JS Hooks** (`assets/js/hooks/`): `image_selection_hook.js`（ポリゴン描画）、`openseadragon_hook.js`（ズームビューア）

### 中核パターン

- **Stage-Gate**: WIP → Pending Review → Approved / Returned（Lab → Gallery）
- **OTP 監督**: `DynamicSupervisor` + `Registry` でユーザスコープ Worker
- **PubSub**: `AlchemIiif.PubSub` 経由で進捗をリアルタイム配信
- **Lazy PTIFF**: 公開用 PTIF は admin 承認時にのみ生成
- **Soft Delete**: Projects は `deleted_at` タイムスタンプ

## 技術スタック

- Elixir 1.18+ / OTP 27 / Phoenix 1.8 / LiveView 1.1
- PostgreSQL 15+（JSONB、tsvector FTS）
- libvips（`vix` 経由）+ poppler-utils（`pdftoppm`）
- Tailwind CSS 4 + DaisyUI 5 + esbuild
- CropperJS、OpenSeadragon 4.1
- HTTP は **`Req` 専用**（`httpoison` / `tesla` は使用禁止）

## コード規約

### 言語・コミット

- コメント・ドキュメントは **日本語**
- Conventional Commits: `feat(scope):`, `fix(scope):`, `docs:`, `refactor(scope):` …
- Credo strict: 行幅 120、ネスト深度 4、循環的複雑度 12

### Phoenix / LiveView 規約（違反禁止）

| やる | やらない |
|------|---------|
| `@current_scope.user` | `@current_user` |
| プログラム設定フィールド（`user_id` 等）は `cast` から除外 | `cast` に含める |
| フォームは `to_form/2` | 生 `Ecto.Changeset` を assign |
| 入力は `<.input>`、アイコンは `<.icon>` | 自前 HTML |
| コレクションは LiveView streams | 通常リスト assign |
| `<.link navigate={...}>` | `live_redirect` / `live_patch` / `Phoenix.View` |
| JS は `assets/js/` の hook | HEEx 内 `<script>` |
| 関数コンポーネント | LiveComponent（強い理由がない限り）|

### アクセシビリティ

- ボタン最小 60×60px、WCAG AA コントラスト、操作要素に `aria-label`

## ブランチ戦略

- `main` — 安定版、直接 push 禁止
- `develop` — 統合ブランチ
- `feature/*`, `fix/*`, `docs/*` — 作業ブランチ

## システム依存

- ホストに **libvips** と **poppler-utils** が必要（詳細は `Dockerfile`）
- ヘルスチェック: `GET /api/health`
