# Task: Manifest Completion + IIIF_SPEC.md Update

## 目的

以下の4点を完成させる。

1. `navDate` — `survey_year` を ISO 8601 形式で Manifest に出力する
2. `rendering` — 元 PDF への参照リンクを Manifest に追加する
3. `summary` — Manifest の概要フィールドを追加する
4. `IIIF_SPEC.md` — 実装と乖離しているドキュメントを現状に合わせて更新する

検索ファセットへの反映（`material` / `site_code`）は別セッションとする。

---

## 変更スコープ

| ファイル | 変更内容 |
|---|---|
| `lib/alchem_iiif_web/controllers/iiif/manifest_controller.ex` | `navDate` / `rendering` / `summary` 追加 |
| `lib/alchem_iiif_web/controllers/iiif/presentation_controller.ex` | 同上 |
| `IIIF_SPEC.md` | スキーマ・Manifest仕様を現状に合わせて全面更新 |
| `test/alchem_iiif_web/controllers/iiif/manifest_controller_test.exs` | 新プロパティのテスト追加 |
| `test/alchem_iiif_web/controllers/iiif/presentation_controller_test.exs` | 同上 |

**このセッションで触らないファイル：**

- `search.ex` / `gallery_live.ex`（検索・表示への反映は別セッション）
- スキーマ・マイグレーション（変更不要）
- LiveView（UI変更なし）

---

## Step 1：`navDate` の実装

### 仕様

IIIF Presentation API v3.0 の `navDate` は ISO 8601 形式の文字列。
Canvas レベルに設定することで、ビューアが時系列ナビゲーションを提供できる。

### 実装箇所

`manifest_controller.ex` と `presentation_controller.ex` の
Canvas 生成部分に追加する。

```elixir
defp format_nav_date(nil), do: nil
defp format_nav_date(year) when is_integer(year) do
  "#{year}-01-01T00:00:00Z"
end
```

Manifest のトップレベルと Canvas の両方に設定する：

```elixir
# Manifest トップレベル（survey_year が設定されている場合のみ）
"navDate" => format_nav_date(source.survey_year),

# Canvas レベル（同上）
"navDate" => format_nav_date(source.survey_year),
```

`nil` の場合はキーごと出力しない（`Enum.reject(&is_nil/1)` 等で除外）。

---

## Step 2：`rendering` の実装

### 仕様

元 PDF への参照。IIIF Presentation API v3.0 では以下の形式：

```json
"rendering": [
  {
    "id": "https://example.com/uploads/report.pdf",
    "type": "Text",
    "label": { "ja": ["原本PDF"], "en": ["Original PDF"] },
    "format": "application/pdf"
  }
]
```

### 実装

`pdf_sources` の `filename` フィールドからURLを構築する。
ファイルのパスは `priv/static/uploads/` 配下に保存されている前提で、
`AlchemIiifWeb.Endpoint.url()` と組み合わせてURLを生成する。

```elixir
defp build_rendering(source) do
  case source.filename do
    nil -> nil
    filename ->
      [%{
        "id"     => "#{AlchemIiifWeb.Endpoint.url()}/uploads/#{filename}",
        "type"   => "Text",
        "label"  => %{"ja" => ["原本PDF"], "en" => ["Original PDF"]},
        "format" => "application/pdf"
      }]
  end
end
```

実際のファイル保存パスが異なる場合は、既存の `image_path` 生成ロジックを参照して
URL構築方法を合わせること。

`nil` の場合はキーごと出力しない。

---

## Step 3：`summary` の実装

### 仕様

Manifest 全体の概要説明。`label` より詳しく、`metadata` より短い説明文。

### 生成ロジック

以下の優先順位で値を構築する：

1. `report_title` が設定されている場合：`"#{report_title}（#{investigating_org}）"` 形式
2. `report_title` のみの場合：`report_title` をそのまま使用
3. どちらも nil の場合：`summary` キー自体を出力しない

```elixir
defp build_summary(source) do
  case {source.report_title, source.investigating_org} do
    {nil, _} ->
      nil
    {title, nil} ->
      %{"ja" => [title], "en" => [title]}
    {title, org} ->
      %{"ja" => ["#{title}（#{org}）"], "en" => ["#{title} (#{org})"]}
  end
end
```

---

## Step 4：Manifest JSON の組み立て確認

`manifest_controller.ex` と `presentation_controller.ex` の
JSON出力部分が以下の構造になっていることを確認・修正する。

```elixir
manifest = %{
  "@context"          => "http://iiif.io/api/presentation/3/context.json",
  "id"                => manifest_url,
  "type"              => "Manifest",
  "label"             => build_label(image),
  "summary"           => build_summary(source),         # 今回追加
  "navDate"           => format_nav_date(source.survey_year), # 今回追加
  "requiredStatement" => build_required_statement(source),
  "rights"            => source.license_uri,
  "provider"          => build_provider(source),
  "rendering"         => build_rendering(source),        # 今回追加
  "metadata"          => build_metadata(image, source),
  "items"             => build_canvases(image, source),
}
|> Enum.reject(fn {_k, v} -> is_nil(v) end)
|> Map.new()
```

`nil` のキーを一括除去する `Enum.reject` を必ず通すこと。

---

## Step 5：テスト（TDD — 実装より先に書く）

### manifest_controller_test.exs に追加

```elixir
describe "navDate" do
  test "survey_year が設定されている場合、navDate が ISO 8601 形式で出力される" do
    # setup: survey_year: 2014 の pdf_source
    # assert: JSON に "navDate" => "2014-01-01T00:00:00Z" が存在する
  end

  test "survey_year が nil の場合、navDate キーが存在しない" do
    # setup: survey_year: nil
    # assert: JSON に "navDate" キーが存在しない
  end
end

describe "rendering" do
  test "filename が設定されている場合、rendering 配列が出力される" do
    # assert: "rendering" の最初の要素の "format" が "application/pdf"
  end

  test "rendering の type が 'Text' である" do
    # assert: "type" => "Text"
  end
end

describe "summary" do
  test "report_title と investigating_org が両方ある場合、両方を含む summary が出力される" do
    # assert: summary の "ja" 値に report_title と investigating_org が含まれる
  end

  test "report_title のみの場合、summary にその値が出力される" do
  end

  test "report_title が nil の場合、summary キーが存在しない" do
  end
end
```

`presentation_controller_test.exs` にも同様のテストを追加する。

---

## Step 6：IIIF_SPEC.md の更新

### 更新箇所1：§3 Data Schema

`pdf_sources` のテーブル定義に追加済みフィールドを反映する：

| フィールド | 型 | 説明 |
|---|---|---|
| `investigating_org` | `:string` | 発掘調査機関名 |
| `survey_year` | `:integer` | 調査年度（西暦） |
| `report_title` | `:string` | 報告書正式名称 |
| `license_uri` | `:string` | ライセンスURI（デフォルト: InC-1.0） |
| `site_code` | `:string` | 全国遺跡地図コード |

`extracted_images` のテーブル定義に追加：

| フィールド | 型 | 説明 |
|---|---|---|
| `material` | `:string` | 素材（例：土器、石器） |

### 更新箇所2：§6 IIIF Server Implementation

Presentation API の出力仕様に以下を追記する：

```
#### Manifest プロパティ（v3.0 recommended 対応状況）

| プロパティ | 実装状態 | 値の源泉 |
|---|---|---|
| label | ✅ | extracted_images.label + caption |
| summary | ✅ | report_title + investigating_org |
| metadata | ✅ | 遺跡名・時代・遺物種別・素材・調査機関・調査年度・報告書名・遺跡コード |
| requiredStatement | ✅ | investigating_org |
| rights | ✅ | license_uri |
| provider | ✅ | investigating_org |
| navDate | ✅ | survey_year（ISO 8601形式） |
| rendering | ✅ | filename（元PDF参照） |
| homepage | 未実装 | — |
| thumbnail | 未実装 | — |
```

### 更新箇所3：§3.1 Strict Validation Rules

以下を追記する：

```
- **Site Code Format:** `site_code` は `^\d{5,6}-\d{1,4}$` 形式
  （全国遺跡地図コード。例: 15206-27）
- **Survey Year Range:** `survey_year` は 1900 以上・現在年以下の整数
- **License URI Format:** `license_uri` は http:// または https:// で始まる文字列
```

---

## 実装順序

1. テストを書いて `mix test` で RED を確認する
2. `manifest_controller.ex` に `navDate` / `rendering` / `summary` を追加する
3. `presentation_controller.ex` に同様の変更を加える
4. テストを GREEN にする
5. `IIIF_SPEC.md` を更新する
6. `mix review` で全件 PASS を確認する

---

## 完了条件

- [ ] `mix test` 全件 GREEN
- [ ] `mix review` 全件 PASS
- [ ] `GET /iiif/manifest/:identifier` のレスポンスに以下が含まれること（curl で確認）
  - `navDate`（survey_year 設定済みレコードで）
  - `rendering`（filename 設定済みレコードで）
  - `summary`（report_title 設定済みレコードで）
- [ ] nil フィールドに対応するキーが JSON に現れないこと
- [ ] `IIIF_SPEC.md` の §3 テーブルが実際のスキーマと一致していること

---

## 注意事項

- `rendering` の URL 構築は既存の `image_path` 生成ロジックを必ず参照すること
  （ファイル保存先が `priv/static/uploads/` でない可能性がある）
- `nil` キーの除去は `Enum.reject` を使い、手動の `if` 分岐を増やさない
- `IIIF_SPEC.md` は英語で記述されているので更新も英語で行う
- `presentation_controller.ex` では Canvas ループ内で `source` を参照できるよう
  クエリに `pdf_sources` の JOIN が含まれていることを確認してから実装する