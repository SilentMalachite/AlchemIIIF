# Task: Manifest label Fix + Canvas Real Size

## 目的

Manifest JSON の以下3点を修正する。

1. Manifest トップレベルの `label` を `report_title` ベースの言語タグ付きに変更
2. Canvas の `label` を `"none"` から言語タグ付きに変更
3. Canvas の `width` / `height` を `1000` 固定から実サイズに変更

---

## 現状と期待値

### 問題1：Manifest label がファイル名 + `"none"`

```json
// 現状（誤り）
"label": {"none": ["黒姫洞窟遺跡-1775979589.pdf"]}

// 期待値
"label": {"ja": ["黒姫洞穴遺跡"], "en": ["黒姫洞穴遺跡"]}
```

### 問題2：Canvas label が `"none"`

```json
// 現状（誤り）
"label": {"none": ["fig-2-1"]}

// 期待値
"label": {"ja": ["fig-2-1"], "en": ["fig-2-1"]}
```

### 問題3：Canvas サイズが固定値

```json
// 現状（誤り）
"height": 1000, "width": 1000

// 期待値：geometry または画像ファイルの実サイズ
"height": 3508, "width": 2480
```

---

## 変更スコープ

| ファイル | 変更内容 |
|---|---|
| `lib/alchem_iiif_web/controllers/iiif/manifest_controller.ex` | label 言語タグ修正・Canvas サイズ実値化 |
| `lib/alchem_iiif_web/controllers/iiif/presentation_controller.ex` | 同上 |
| `lib/alchem_iiif/iiif/metadata_helper.ex` | `build_label` 系ヘルパーの修正（存在する場合） |
| `test/alchem_iiif_web/controllers/iiif/manifest_controller_test.exs` | label・サイズのテスト修正・追加 |
| `test/alchem_iiif_web/controllers/iiif/presentation_controller_test.exs` | 同上 |

**このセッションで触らないファイル：**

- スキーマ・マイグレーション（変更不要）
- LiveView（変更不要）

---

## 実装前の確認事項（必ず先に読む）

1. `manifest_controller.ex` と `presentation_controller.ex` で
   `label` を生成している箇所を特定する

2. Canvas のサイズ（`width` / `height`）をどこで設定しているか確認する

3. `geometry` フィールドの実際の構造を確認する：
   - `%{"width" => ..., "height" => ...}` が含まれるか
   - 含まれない場合、`vix` で画像ファイルから読む必要があるか

4. `MetadataHelper` に `build_label` 系の関数があるか確認し、
   あればそこを修正する（controller 側を直接修正しない）

---

## Step 1：Manifest トップレベルの label 修正

### 修正方針

`report_title` を優先し、なければ `filename` からタイムスタンプを除去して使う。

```elixir
defp build_manifest_label(source) do
  title = source.report_title || strip_timestamp(source.filename)
  %{"ja" => [title], "en" => [title]}
end

# "黒姫洞窟遺跡-1775979589.pdf" → "黒姫洞窟遺跡"
defp strip_timestamp(filename) do
  filename
  |> String.replace(~r/-\d+\.pdf$/, "")
  |> String.replace(".pdf", "")
end
```

`report_title` が設定されている場合は `strip_timestamp` を呼ばない。

---

## Step 2：Canvas label の言語タグ修正

### 修正方針

`label` / `caption` の組み合わせで日英バイリンガルにする。

```elixir
defp build_canvas_label(image) do
  # caption がある場合は "fig-2-1 縄文時代の深鉢形土器" のように結合
  # ない場合は label のみ
  value =
    case image.caption do
      nil     -> image.label
      ""      -> image.label
      caption -> "#{image.label} #{caption}"
    end

  %{"ja" => [value], "en" => [image.label]}
end
```

`"none"` キーは使わない。

---

## Step 3：Canvas の実サイズ化

### 確認手順

`geometry` フィールドに `width` / `height` が含まれるか確認する。

**ケースA：`geometry` に実サイズが含まれる場合**

```elixir
defp canvas_dimensions(image) do
  width  = get_in(image.geometry, ["width"])  || 1000
  height = get_in(image.geometry, ["height"]) || 1000
  {width, height}
end
```

**ケースB：`geometry` に実サイズが含まれない場合**

画像ファイルから `vix` で読む：

```elixir
defp canvas_dimensions(image) do
  path = Path.join([:code.priv_dir(:alchem_iiif), "static", image.image_path])

  case File.exists?(path) do
    true ->
      {:ok, img} = Vix.Vips.Image.new_from_file(path)
      width  = Vix.Vips.Image.width(img)
      height = Vix.Vips.Image.height(img)
      {width, height}

    false ->
      {1000, 1000}  # ファイルが存在しない場合のフォールバック
  end
end
```

**ケースBの注意点：**
`vix` での画像読み込みはリクエストのたびに発生するためコストがかかる。
`geometry` への実サイズ保存が将来タスクとして望ましい（`IIIF_SPEC.md` に注記する）。

### Canvas JSON への反映

```elixir
{width, height} = canvas_dimensions(image)

%{
  "id"     => canvas_id,
  "type"   => "Canvas",
  "label"  => build_canvas_label(image),
  "width"  => width,
  "height" => height,
  "items"  => build_annotation_page(image, canvas_id)
}
```

---

## Step 4：テスト修正・追加

### manifest_controller_test.exs

```elixir
describe "Manifest label" do
  test "report_title が設定されている場合、label に report_title が使われる" do
    # assert: label["ja"] == [report_title の値]
  end

  test "report_title が nil の場合、filename からタイムスタンプを除去した値が使われる" do
    # setup: report_title: nil, filename: "test-1234567890.pdf"
    # assert: label["ja"] == ["test"]
  end

  test "label のキーが 'none' ではなく 'ja' / 'en' である" do
    # assert: label に "none" キーが存在しない
  end
end

describe "Canvas label" do
  test "Canvas label のキーが 'ja' / 'en' である" do
    # assert: items[0]["label"] に "none" キーが存在しない
  end

  test "caption がある場合、Canvas label の ja 値に caption が含まれる" do
    # setup: caption: "縄文時代の深鉢形土器"
    # assert: label["ja"][0] に "縄文時代の深鉢形土器" が含まれる
  end
end

describe "Canvas サイズ" do
  test "Canvas の width / height が 1000 固定ではない（geometry に実サイズがある場合）"
  # または
  test "Canvas の width / height がフォールバック値を返す（geometry にサイズがない場合）"
end
```

`presentation_controller_test.exs` にも同様のテストを追加する。

---

## 実装順序

1. `geometry` の実際の構造を `iex -S mix` で確認する：
   ```elixir
   AlchemIiif.Repo.all(AlchemIiif.Ingestion.ExtractedImage)
   |> List.first()
   |> Map.get(:geometry)
   ```
2. `label` 生成箇所を特定する（`MetadataHelper` か controller か）
3. テストを修正・追加して RED を確認する
4. Manifest label を修正する
5. Canvas label を修正する
6. Canvas サイズを実値化する
7. `mix review` で全件 PASS を確認する

---

## 完了条件

- [ ] `mix test` 全件 GREEN
- [ ] `mix review` 全件 PASS
- [ ] `GET /iiif/presentation/1/manifest` の `label` に `"none"` が含まれない
- [ ] Manifest `label` の値が `report_title`（または整形済みファイル名）になっている
- [ ] Canvas `label` の値が `"ja"` / `"en"` キーを持つ
- [ ] Canvas `width` / `height` が `1000` 固定でない
  （geometry に実サイズがある場合）

---

## 注意事項

- `"none"` キーを使うのは言語が本当に不明な場合のみ（IIIF v3.0 仕様）。
  日本語の報告書名は `"ja"` を使う
- `strip_timestamp` は正規表現 `~r/-\d+\.pdf$/` で対応する。
  タイムスタンプの桁数が変わっても動作するよう `\d+`（1桁以上）にする
- Canvas サイズを `vix` で読む場合、ファイルが存在しない場合の
  フォールバック（`{1000, 1000}`）を必ず実装する
- `geometry` に実サイズが含まれない場合、
  `IIIF_SPEC.md` に「Canvas サイズの実値保存は将来タスク」と注記する