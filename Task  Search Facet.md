# Task: Search Facet Extension — material / site_code

## 目的

`material`（素材）と `site_code`（遺跡コード）を検索・絞り込みに反映する。

- `material`：ファセット選択肢として追加（`period` / `artifact_type` と同じ扱い）
- `site_code`：前方一致テキスト検索として追加（コード体系上、完全一致より有用）

---

## 変更スコープ

| ファイル | 変更内容 |
|---|---|
| `lib/alchem_iiif/search.ex` | `material` ファセット・`site_code` 前方一致検索を追加 |
| `lib/alchem_iiif_web/live/search_live.ex` | UI に `material` セレクト・`site_code` 入力欄を追加 |
| `test/alchem_iiif/search_test.exs` | 検索ロジックのユニットテスト追加 |
| `test/alchem_iiif_web/live/search_live_test.exs` | UI・絞り込み動作のテスト追加 |

**このセッションで触らないファイル：**

- `gallery_live.ex`（ギャラリー表示カードへの反映は別セッション）
- マイグレーション・スキーマ（変更不要）
- `manifest_controller.ex` / `presentation_controller.ex`（変更不要）

---

## Step 1：search.ex の更新

### 現状の確認（実装前に必ず行う）

`search.ex` の `search_images/1` または相当する関数を確認し、
`period` / `artifact_type` のファセット絞り込みがどのように実装されているかを把握する。
以下の実装はそのパターンに**必ず準拠**する。

### material ファセットの追加

`period` / `artifact_type` と同じパターンで `material` を追加する。

```elixir
# period の絞り込みが以下のようなパターンであれば
defp filter_by_period(query, nil), do: query
defp filter_by_period(query, period) do
  from q in query, where: q.period == ^period
end

# material も同じパターンで追加する
defp filter_by_material(query, nil), do: query
defp filter_by_material(query, material) do
  from q in query, where: q.material == ^material
end
```

### site_code 前方一致検索の追加

`site_code` はコード体系（例：`15206-27`）なのでテキスト全文検索ではなく
前方一致（`LIKE '15%'`）で実装する。
都道府県コード2桁だけを入力して絞り込むユースケースを想定。

```elixir
defp filter_by_site_code(query, nil), do: query
defp filter_by_site_code(query, ""), do: query
defp filter_by_site_code(query, site_code) do
  pattern = "#{site_code}%"
  from q in query, where: like(q.site_code, ^pattern)
end
```

### ファセット選択肢の取得関数

`material` の選択肢一覧を取得する関数を追加する。
`period` / `artifact_type` の選択肢取得関数と同じパターンで実装する。

```elixir
def list_materials do
  from(e in ExtractedImage,
    where: not is_nil(e.material) and e.status == "published",
    select: e.material,
    distinct: true,
    order_by: e.material
  )
  |> Repo.all()
end
```

---

## Step 2：search_live.ex の更新

### 現状の確認（実装前に必ず行う）

`period` / `artifact_type` のファセット UI がどのように実装されているかを確認し、
以下の変更は**そのパターンに準拠**する。

### assigns への追加

`mount/3` 内で以下を追加する：

```elixir
|> assign(:materials, Search.list_materials())
|> assign(:selected_material, nil)
|> assign(:site_code_query, "")
```

### イベントハンドラの追加

`period` / `artifact_type` の絞り込みイベントと同じパターンで追加する：

```elixir
# material ファセット選択
def handle_event("filter_material", %{"material" => material}, socket) do
  material = if material == "", do: nil, else: material
  {:noreply,
   socket
   |> assign(:selected_material, material)
   |> assign(:images, search_with_filters(socket, material: material))}
end

# site_code 前方一致検索
def handle_event("filter_site_code", %{"site_code" => site_code}, socket) do
  {:noreply,
   socket
   |> assign(:site_code_query, site_code)
   |> assign(:images, search_with_filters(socket, site_code: site_code))}
end
```

`search_with_filters/2` は既存の絞り込み関数に `material` / `site_code` を
追加したもの。既存の関数シグネチャを壊さないよう注意する。

### テンプレートへの追加

`period` / `artifact_type` のセレクトボックスの下に追加する。

**material セレクト：**

```heex
<label for="material-filter">素材</label>
<select id="material-filter"
        phx-change="filter_material"
        name="material">
  <option value="">すべて</option>
  <%= for material <- @materials do %>
    <option value={material}
            selected={@selected_material == material}>
      <%= material %>
    </option>
  <% end %>
</select>
```

**site_code テキスト入力：**

```heex
<label for="site-code-filter">遺跡コード（前方一致）</label>
<input id="site-code-filter"
       type="text"
       name="site_code"
       value={@site_code_query}
       placeholder="例：15（新潟県）、15206（新発田市）"
       phx-change="filter_site_code"
       phx-debounce="300" />
```

**アクセシビリティ基準（既存ルールを維持）：**

- すべての入力要素に `<label>` を紐付ける（`for` 属性必須）
- ボタン・選択要素は min 60×60px（既存スタイルを流用）
- `phx-debounce="300"` を site_code 入力に設定し、入力のたびにクエリが走らないようにする

---

## Step 3：テスト（TDD — 実装より先に書く）

### search_test.exs に追加

```elixir
describe "filter_by_material/2" do
  test "material を指定すると該当レコードのみ返る" do
    # setup: material: "土器" のレコードと "石器" のレコードを作成
    # assert: material: "土器" で絞り込むと土器のみ返る
  end

  test "material が nil の場合は全件返る" do
  end

  test "存在しない material を指定すると空配列が返る" do
  end
end

describe "filter_by_site_code/2" do
  test "都道府県コードの前方一致で絞り込める" do
    # setup: site_code: "15206-27" のレコードを作成
    # assert: "15" で検索すると該当レコードが返る
  end

  test "より詳細なコードでも絞り込める" do
    # assert: "15206" で検索すると該当レコードが返る
  end

  test "マッチしないコードでは空配列が返る" do
    # assert: "99" で検索すると空配列が返る
  end

  test "空文字の場合は全件返る" do
  end
end

describe "list_materials/0" do
  test "published 状態の material のみ返る" do
    # setup: published と draft のレコードを作成
    # assert: draft のレコードの material は含まれない
  end

  test "重複なしで返る" do
    # setup: 同じ material を持つ複数レコード
    # assert: material の値は1件のみ
  end

  test "nil の material は含まれない" do
  end
end
```

### search_live_test.exs に追加

```elixir
describe "material ファセット" do
  test "素材セレクトボックスが表示される" do
    # assert: ページに「素材」ラベルが存在する
  end

  test "material を選択すると絞り込まれる" do
    # setup: material: "土器" のレコードを published 状態で作成
    # action: セレクトで "土器" を選択
    # assert: 該当レコードが表示される
  end

  test "「すべて」を選択すると絞り込みが解除される" do
  end
end

describe "site_code 検索" do
  test "遺跡コード入力欄が表示される" do
    # assert: ページに「遺跡コード」ラベルが存在する
  end

  test "都道府県コードを入力すると絞り込まれる" do
    # setup: site_code: "15206-27" のレコードを published で作成
    # action: "15" を入力
    # assert: 該当レコードが表示される
  end

  test "マッチしないコードを入力すると結果が空になる" do
  end
end
```

---

## 実装順序

1. `search.ex` の `period` / `artifact_type` 実装パターンを読んで把握する
2. テストを書いて `mix test` で RED を確認する
3. `search.ex` に `filter_by_material/2` / `filter_by_site_code/2` / `list_materials/0` を追加する
4. `search_test.exs` を GREEN にする
5. `search_live.ex` の `period` / `artifact_type` UI パターンを読んで把握する
6. `search_live.ex` に assigns・イベントハンドラ・テンプレートを追加する
7. `search_live_test.exs` を GREEN にする
8. `mix review` で全件 PASS を確認する

---

## 完了条件

- [ ] `mix test` 全件 GREEN
- [ ] `mix review` 全件 PASS
- [ ] 検索画面に「素材」セレクトが表示される（手動確認）
- [ ] 検索画面に「遺跡コード」入力欄が表示される（手動確認）
- [ ] `material` で絞り込むと該当レコードのみ表示される（手動確認）
- [ ] `site_code` の前方一致で絞り込める（手動確認：`15` で新潟県のレコードが出ること）
- [ ] 絞り込みを解除すると全件に戻る（手動確認）

---

## 注意事項

- `period` / `artifact_type` の既存実装パターンを必ず先に読んでから実装する
  （パターンを統一することで将来のファセット追加が容易になる）
- `site_code` は `LIKE` クエリのため、入力値に `%` や `_` が含まれる場合は
  エスケープが必要。Ecto の `like/2` はエスケープを自動処理しないので、
  入力値を `String.replace(site_code, "%", "\\%")` で前処理すること
- `phx-debounce="300"` は site_code 入力に必須（300ms待機でクエリ数を抑制）
- `list_materials/0` は `mount/3` 時に一度だけ呼び、結果を assigns に保持する
  （フィルタ変更のたびに呼ばない）
- `published` 状態のレコードのみをファセット選択肢に含めること