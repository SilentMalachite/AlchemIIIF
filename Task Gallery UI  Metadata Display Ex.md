# Task: Gallery UI — Metadata Display Extension

## 目的

Manifest JSON には出力済みだがギャラリー UI に表示されていないフィールドを
人が見てわかる形で画面に反映する。

対象：
1. ギャラリーカードへの書誌情報表示（`investigating_org` / `survey_year` / `report_title`）
2. 詳細モーダルへのメタデータパネル追加（全フィールド）
3. 元 PDF ダウンロードリンクの追加（`rendering` に対応する UI）

---

## 変更スコープ

| ファイル | 変更内容 |
|---|---|
| `lib/alchem_iiif_web/live/gallery_live.ex` | カード表示・モーダルのメタデータパネル追加 |
| `test/alchem_iiif_web/live/gallery_live_test.exs` | 表示テスト追加 |

**このセッションで触らないファイル：**

- `search_live.ex`（検索ファセットは別セッション完了済み）
- `manifest_controller.ex` / `presentation_controller.ex`（変更不要）
- スキーマ・マイグレーション（変更不要）

---

## 実装前の確認事項（必ず先に読む）

1. `gallery_live.ex` のカードコンポーネントの HTML 構造
2. 詳細モーダルの実装方法（LiveView の `phx-click` / JS コマンド / 別コンポーネントか）
3. カードに渡されている assigns の内容（`extracted_images` に `pdf_sources` が
   JOIN / preload されているか）
4. 既存の CSS クラス・テーマ（「新潟インディゴ＆ハーベストゴールド」）

---

## Step 1：クエリの確認と修正

### preload の確認

`gallery_live.ex` の `mount/3` または `handle_params/3` で
`ExtractedImage` を取得するクエリを確認する。

`pdf_sources` の書誌フィールド（`investigating_org` / `survey_year` /
`report_title` / `license_uri` / `site_code` / `filename`）を
カードとモーダルで表示するには、`PdfSource` が preload または JOIN
されている必要がある。

**preload されていない場合：**

```elixir
# Repo.preload を追加する
images = Repo.preload(images, :pdf_source)
```

既存のクエリ構造を壊さないよう、追加箇所は最小限にする。

---

## Step 2：ギャラリーカードへの書誌情報追加

### 表示するフィールド

カードには情報を絞り込む。認知負荷を増やさないよう**3項目まで**とする。

| フィールド | 表示形式 | nil 時 |
|---|---|---|
| `report_title` | テキスト（細字） | 非表示 |
| `investigating_org` | テキスト（細字） | 非表示 |
| `survey_year` | `"YYYY年"` 形式 | 非表示 |

### UI 仕様

- 既存の `caption` / `site` / `period` / `artifact_type` の表示スタイルを踏襲する
- フィールドが nil のときはその要素ごと非表示にする（空欄を残さない）
- カードの高さが大きく変わる場合は既存の masonry レイアウトへの影響を確認する

### 実装例（既存スタイルに合わせること）

```heex
<%= if image.pdf_source.report_title do %>
  <p class="既存の細字テキストクラス">
    <%= image.pdf_source.report_title %>
  </p>
<% end %>

<%= if image.pdf_source.investigating_org do %>
  <p class="既存の細字テキストクラス">
    <%= image.pdf_source.investigating_org %>
  </p>
<% end %>

<%= if image.pdf_source.survey_year do %>
  <p class="既存の細字テキストクラス">
    <%= image.pdf_source.survey_year %>年
  </p>
<% end %>
```

---

## Step 3：詳細モーダルへのメタデータパネル追加

### モーダルの確認

詳細モーダルの実装パターン（LiveView コンポーネント / JS モーダル / 
`phx-click` トグル）を先に確認し、既存の構造を把握してから追加する。

### 表示するフィールド

モーダルでは全フィールドを表示する。nil のフィールドは非表示。

**画像情報（`ExtractedImage` から）：**

| ラベル | フィールド | 表示形式 |
|---|---|---|
| 遺跡名 | `site` | テキスト |
| 時代 | `period` | テキスト |
| 遺物種別 | `artifact_type` | テキスト |
| 素材 | `material` | テキスト |
| 図版番号 | `label` | テキスト |
| キャプション | `caption` | テキスト |

**報告書情報（`PdfSource` から）：**

| ラベル | フィールド | 表示形式 |
|---|---|---|
| 報告書名 | `report_title` | テキスト |
| 調査機関 | `investigating_org` | テキスト |
| 調査年度 | `survey_year` | `"YYYY年"` |
| 遺跡コード | `site_code` | テキスト |
| ライセンス | `license_uri` | リンク（別タブ） |

### パネルの HTML 構造

`<dl>` / `<dt>` / `<dd>` を使った定義リスト形式を推奨する。
既存モーダルに類似のパターンがある場合はそれに合わせる。

```heex
<dl class="既存のテーブル・リストスタイルに合わせる">
  <%= if @selected_image.site do %>
    <dt>遺跡名</dt>
    <dd><%= @selected_image.site %></dd>
  <% end %>
  <%# ... 他のフィールドも同様 %>
</dl>
```

**セクション分け：**
画像情報と報告書情報を視覚的に分ける（見出しまたは区切り線）。
既存モーダルの視覚スタイルを壊さないようにする。

---

## Step 4：元 PDF ダウンロードリンクの追加

### 配置

詳細モーダルの下部に配置する。

### URL 構築

`rendering` の実装（`manifest_controller.ex`）で使った URL パターンと
**必ず一致させる**。

```elixir
# manifest_controller.ex の build_rendering/1 を確認して同じパスを使う
# 例："/uploads/pdfs/#{source.filename}"
```

### HTML

```heex
<%= if @selected_image.pdf_source.filename do %>
  <a href={pdf_url(@selected_image.pdf_source.filename)}
     target="_blank"
     rel="noopener noreferrer"
     class="既存のボタンスタイル">
    📄 原本 PDF をダウンロード
  </a>
<% end %>
```

ヘルパー関数：

```elixir
defp pdf_url(filename) do
  # manifest_controller.ex の build_rendering/1 と同じ URL 構築ロジックを使う
  "#{AlchemIiifWeb.Endpoint.url()}/uploads/pdfs/#{filename}"
end
```

---

## Step 5：テスト（TDD — 実装より先に書く）

### gallery_live_test.exs に追加

```elixir
describe "ギャラリーカードの書誌情報表示" do
  test "report_title が設定されている場合、カードに表示される"
  test "investigating_org が設定されている場合、カードに表示される"
  test "survey_year が設定されている場合、'YYYY年' 形式で表示される"
  test "report_title が nil の場合、その要素が表示されない"
end

describe "詳細モーダルのメタデータパネル" do
  test "カードクリックでモーダルが開く"
  test "モーダルに遺跡名・時代・遺物種別が表示される"
  test "モーダルに素材が表示される（material が設定されている場合）"
  test "モーダルに報告書名・調査機関・調査年度が表示される"
  test "モーダルに遺跡コードが表示される（site_code が設定されている場合）"
  test "nil フィールドに対応するラベルが表示されない"
end

describe "元 PDF ダウンロードリンク" do
  test "filename が設定されている場合、ダウンロードリンクが表示される"
  test "filename が nil の場合、ダウンロードリンクが表示されない"
  test "リンクの href が正しい URL 形式になっている"
end
```

---

## 実装順序

1. `gallery_live.ex` の現在の実装（クエリ・カード・モーダル）を読む
2. `PdfSource` の preload が必要か確認し、必要なら追加する
3. テストを書いて RED を確認する
4. カードに書誌情報を追加してテストを GREEN にする
5. モーダルにメタデータパネルを追加してテストを GREEN にする
6. PDF ダウンロードリンクを追加してテストを GREEN にする
7. `mix review` で全件 PASS を確認する

---

## 完了条件

- [ ] `mix test` 全件 GREEN
- [ ] `mix review` 全件 PASS
- [ ] ギャラリーカードに `report_title` / `investigating_org` / `survey_year` が
      表示される（手動確認）
- [ ] nil フィールドが空欄として残らない（手動確認）
- [ ] モーダルに全メタデータが整理されて表示される（手動確認）
- [ ] PDF ダウンロードリンクが機能する（手動確認）
- [ ] masonry レイアウトが崩れていない（手動確認）

---

## 注意事項

- **`build_rendering/1` と PDF URL のパスを必ず一致させる**
  manifest_controller.ex を参照してから実装すること
- `PdfSource` の preload は既存クエリへの影響を最小限にする
- nil チェックは `if` を使い、空欄・ゼロ幅スペースを残さない
- モーダルの既存スタイル（インディゴ＆ハーベストゴールドテーマ）を壊さない
- カードへの追加は**3項目まで**に抑える（認知アクセシビリティ）