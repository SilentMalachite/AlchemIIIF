# Task: Add site_code / material Fields + Labeling UI Update

## 目的
遺跡コードと素材を追加し、前セッションで保留していた
書誌フィールドのUI反映（Step 4 ラベリング画面）も今回完成させる。

---

## 変更スコープ

| ファイル | 変更内容 |
|---|---|
| `priv/repo/migrations/YYYYMMDDHHMMSS_add_site_code_to_pdf_sources.exs` | 新規 |
| `priv/repo/migrations/YYYYMMDDHHMMSS_add_material_to_extracted_images.exs` | 新規 |
| `lib/alchem_iiif/ingestion/pdf_source.ex` | `site_code` 追加 |
| `lib/alchem_iiif/ingestion/extracted_image.ex` | `material` 追加 |
| `lib/alchem_iiif_web/live/inspector_live/upload.ex` | 書誌フィールド入力UI |
| `lib/alchem_iiif_web/live/inspector_live/label.ex` | `material` 入力UI |
| `lib/alchem_iiif_web/controllers/iiif/manifest_controller.ex` | metadata に追記 |
| `lib/alchem_iiif_web/controllers/iiif/presentation_controller.ex` | 同上 |
| `test/alchem_iiif/ingestion/pdf_source_test.exs` | site_code バリデーション |
| `test/alchem_iiif/ingestion/extracted_image_test.exs` | material バリデーション |
| `test/alchem_iiif_web/controllers/iiif/manifest_controller_test.exs` | metadata 出力確認 |

**このセッションで触らないファイル：**
- `search.ex`（ファセット検索への反映は別セッション）
- `gallery_live.ex`（表示カードへの反映は別セッション）

---

## Step 1：マイグレーション（2本）

### 1-A：pdf_sources へ site_code 追加
```elixir
add :site_code, :string
# 例："01-001-001"（都道府県コード-市区町村コード-連番）
# null: true で既存レコードへの影響なし
```

### 1-B：extracted_images へ material 追加
```elixir
add :material, :string
# 例："土器", "石器", "金属", "木製品", "紙"
# null: true
```

---

## Step 2：スキーマ更新

### pdf_source.ex

フィールド追加：
```elixir
field :site_code, :string
```

バリデーション：
- 入力された場合、`site_code` は `^\d{2}-\d{3,4}-\d{3,4}$` にマッチすること
  （都道府県コード2桁-市区町村コード3〜4桁-連番3〜4桁）
- 文字数上限：30文字
- `required` には含めない

### extracted_image.ex

フィールド追加：
```elixir
field :material, :string
```

バリデーション：
- 文字数上限：100文字
- `required` には含めない

---

## Step 3：UI更新（前セッション保留分の解放）

### 3-A：upload.ex（Step 1 アップロード画面）に書誌フィールドを追加

プロジェクト作成時に一度だけ入力する項目をまとめて配置する。
既存の「PDFアップロード」フォームの下部に「報告書情報」セクションとして追加する。

追加する入力欄（すべて任意入力、プレースホルダーあり）：

| フィールド | ラベル | プレースホルダー例 |
|---|---|---|
| `report_title` | 報告書名 | 令和○年度 ○○遺跡発掘調査報告書 |
| `investigating_org` | 調査機関名 | ○○市教育委員会 |
| `survey_year` | 調査年度（西暦） | 2024 |
| `site_code` | 遺跡コード | 15-201-001 |
| `license_uri` | ライセンスURI | （デフォルト値を表示） |

**UI上の注意点（認知アクセシビリティ）：**
- セクションは折りたたみ可能にする（デフォルト展開）
- `survey_year` は `type="number"` `min="1900"` `max="現在年"`
- `site_code` はプレースホルダーに書式例を明示する
- `license_uri` は空欄の場合に `InC-1.0` のデフォルト値を説明するヘルプテキストを表示する

### 3-B：label.ex（Step 4 ラベリング画面）に material を追加

既存の `site` / `period` / `artifact_type` フィールドの下に追加する。

| フィールド | ラベル | プレースホルダー例 |
|---|---|---|
| `material` | 素材 | 土師器、黒曜石、鉄製品 など |

**既存フィールドのレイアウトは変更しない。**

---

## Step 4：Manifest 生成の更新

`manifest_controller.ex` と `presentation_controller.ex` の
`build_metadata/2` に以下を追記する（nil の場合はエントリを省く）：
```elixir
label_value("遺跡コード", "Site Code", source.site_code),
label_value("素材", "Material", image.material),
```

前セッションで追加済みの `survey_year` / `report_title` が
実際に metadata に出力されているか確認し、抜けていれば追記する。

`format_survey_year/1` が未実装であれば今回実装する：
```elixir
defp format_survey_year(nil), do: nil
defp format_survey_year(year), do: "#{year}年"
```

---

## Step 5：テスト（TDD）

### pdf_source_test.exs

describe "changeset/2 site_code validation" do

"15-201-001" → valid
"01-1234-5678" → valid（4桁含む）
"abc-def-ghi" → invalid（数字以外）
"1-2-3" → invalid（桁数不足）
nil → valid（任意項目）
31文字の文字列 → invalid（上限超過）
end

### extracted_image_test.exs

describe "changeset/2 material validation" do

"土器" → valid
nil → valid（任意項目）
101文字の文字列 → invalid（上限超過）
end

### manifest_controller_test.exs

describe "metadata completeness" do

site_code が設定されている場合、
metadata 配列に "Site Code" エントリが存在すること
material が設定されている場合、
metadata 配列に "Material" エントリが存在すること
survey_year が設定されている場合、
metadata の値が "2024年" 形式になっていること
end


---

## 実装順序

1. テストを書いて RED を確認する
2. 2本のマイグレーションを作成・実行する
3. `pdf_source.ex` / `extracted_image.ex` を更新してスキーマテストを GREEN にする
4. `upload.ex` / `label.ex` の UI を更新する
5. controller を更新して Manifest テストを GREEN にする
6. `mix review` で全件 PASS を確認する

---

## 完了条件

- [ ] `mix test` 全件 GREEN
- [ ] `mix review` 全件 PASS
- [ ] アップロード画面に報告書情報セクションが表示されること（手動確認）
- [ ] ラベリング画面に「素材」入力欄が表示されること（手動確認）
- [ ] Manifest の `metadata` に新フィールドが出力されること（手動確認）

---

## 注意事項

- `site_code` の正規表現は `Regex.match?/2` で実装する
- `survey_year` の上限は `Date.utc_today().year` で動的に取得する
- UI の大ボタン基準（min 60×60px）は維持する
- upload.ex の書誌フィールドは PDF 変換処理の開始前に保存する
  （変換が始まってから入力欄が消えないよう注意）

ひとつ設計上の判断を補足します。
site_code を pdf_sources に置いた理由：遺跡コードは日本の全国遺跡地図で報告書単位に付番されるもので、1枚の図版に対してではなく調査対象遺跡に対して一つ与えられます。ただし1冊の報告書が複数遺跡を扱う場合（複合遺跡など）は将来的に配列型への拡張が必要になります。今の段階では string の単一値で十分ですが、IIIF_SPEC.md のコメントとして残しておくと後で役立ちます。