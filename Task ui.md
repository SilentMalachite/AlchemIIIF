# Task: Labeling UI — Bibliographic Fields (upload.ex) + Material Field (label.ex)

## 目的

前セッションでDBとスキーマに追加済みのフィールドを
入力フォームに反映する。

- `upload.ex`（Step 1）：報告書情報セクション（書誌フィールド群）
- `label.ex`（Step 4）：素材（`material`）入力欄

バックエンドの変更は不要。フロントエンド（LiveView テンプレート・イベントハンドラ）のみ。

---

## 変更スコープ

| ファイル | 変更内容 |
|---|---|
| `lib/alchem_iiif_web/live/inspector_live/upload.ex` | 報告書情報セクション追加 |
| `lib/alchem_iiif_web/live/inspector_live/label.ex` | `material` 入力欄追加 |
| `test/alchem_iiif_web/live/inspector_live/upload_test.exs` | フォーム表示・保存テスト |
| `test/alchem_iiif_web/live/inspector_live/label_test.exs` | `material` 入力テスト |

**このセッションで触らないファイル：**

- controller 層（Manifest 生成は完了済み）
- スキーマ・マイグレーション（変更不要）
- `gallery_live.ex`（カード表示への反映は別セッション）

---

## Step 1：upload.ex — 報告書情報セクション

### 配置

既存の「PDF アップロード」フォームの**下部**に
「報告書情報（任意）」セクションとして追加する。
変換モード選択（モノクロ／カラー）より上に配置する。

### 追加する入力欄

| フィールド | ラベル（日本語） | input type | プレースホルダー |
|---|---|---|---|
| `report_title` | 報告書名 | `text` | 例：令和6年度 ○○遺跡発掘調査報告書 |
| `investigating_org` | 調査機関名 | `text` | 例：○○市教育委員会 |
| `survey_year` | 調査年度（西暦） | `number` | 例：2024 |
| `site_code` | 遺跡コード | `text` | 例：15-201-001 |
| `license_uri` | ライセンス URI | `text` | （後述のヘルプテキストを参照） |

### UI 仕様

**セクション折りたたみ：**
- `<details>` / `<summary>` で実装する
- デフォルトは `open`（展開状態）
- `<summary>` のラベル：「📋 報告書情報（任意）」

**survey_year の制約：**
```heex
<input type="number" min="1900" max={Date.utc_today().year}
       name="pdf_source[survey_year]" />
```

**license_uri のヘルプテキスト：**
入力欄の下に以下を表示する：
```
未入力の場合は「転載不可（InC-1.0）」が自動設定されます。
CC BY 4.0 の場合は https://creativecommons.org/licenses/by/4.0/ を入力してください。
```

**site_code のヘルプテキスト：**
```
全国遺跡地図のコード（都道府県2桁-市区町村3〜4桁-連番3〜4桁）
```

**アクセシビリティ基準（既存ルールを維持）：**
- すべての入力欄に `<label>` を紐付ける（`for` 属性必須）
- エラーメッセージは入力欄の直下に表示する
- ボタンは min 60×60px（既存の `wizard_components` のスタイルを流用）

### イベントハンドラ

既存の PDF アップロード処理のフォーム送信イベント内で
書誌フィールドも合わせて `PdfSource` の changeset に渡す。

`Ingestion.create_pdf_source/1` または相当する関数の引数に
書誌フィールドのパラメータが含まれるよう修正する。

変換処理（`pdftoppm` の起動）は書誌フィールドの保存後に行う
（順序を変えない）。

---

## Step 2：label.ex — material 入力欄

### 配置

既存の `artifact_type`（遺物種別）入力欄の**直下**に追加する。
レイアウトは `artifact_type` と同じスタイルを踏襲する。

### 追加する入力欄

| フィールド | ラベル（日本語） | input type | プレースホルダー |
|---|---|---|---|
| `material` | 素材 | `text` | 例：土師器、黒曜石、鉄製品 |

### イベントハンドラ

`label.ex` の既存の自動保存イベント（`phx-change` または `phx-blur`）に
`:material` を追加する。

`Ingestion.update_extracted_image/2` の呼び出し箇所で
`:material` パラメータが渡るよう確認する。

---

## Step 3：テスト（TDD — 実装より先に書く）

### upload_test.exs に追加

```elixir
describe "報告書情報フォーム" do
  test "報告書情報セクションが表示される" do
    # assert: ページに「報告書情報」のテキストが存在する
  end

  test "report_title を入力して送信すると pdf_source に保存される" do
    # setup: フォームに report_title を入力して送信
    # assert: PdfSource レコードの report_title に値が入っている
  end

  test "survey_year に範囲外の値を入力するとエラーが表示される" do
    # setup: survey_year に 1800 を入力
    # assert: エラーメッセージが表示される
  end

  test "site_code に不正な形式を入力するとエラーが表示される" do
    # setup: site_code に "abc" を入力
    # assert: エラーメッセージが表示される
  end

  test "書誌フィールドが空でも PDF アップロードは成功する" do
    # assert: 全書誌フィールド未入力でも正常にアップロードできる
  end
end
```

### label_test.exs に追加

```elixir
describe "material 入力欄" do
  test "material 入力欄が表示される" do
    # assert: ページに「素材」のラベルが存在する
  end

  test "material を入力すると ExtractedImage に保存される" do
    # setup: material フィールドに "土器" を入力してイベント発火
    # assert: ExtractedImage レコードの material が "土器" になっている
  end

  test "material が 101 文字の場合はエラーが表示される" do
    # setup: 101文字の文字列を入力
    # assert: エラーメッセージが表示される
  end
end
```

---

## 実装順序

1. テストを書いて `mix test` で RED を確認する
2. `upload.ex` のテンプレートにセクションを追加する
3. `upload.ex` のイベントハンドラに書誌パラメータを追加する
4. `upload_test.exs` を GREEN にする
5. `label.ex` のテンプレートに `material` 欄を追加する
6. `label.ex` のイベントハンドラに `:material` を追加する
7. `label_test.exs` を GREEN にする
8. `mix review` で全件 PASS を確認する

---

## 完了条件

- [ ] `mix test` 全件 GREEN
- [ ] `mix review` 全件 PASS
- [ ] アップロード画面に「報告書情報」セクションが表示される（手動確認）
- [ ] 書誌フィールドを入力してアップロードすると DB に保存される（手動確認）
- [ ] 書誌フィールドが空でもアップロードが正常に完了する（手動確認）
- [ ] ラベリング画面に「素材」欄が表示される（手動確認）
- [ ] `material` を入力すると自動保存される（手動確認）

---

## 注意事項

- `<details>` / `<summary>` 以外の折りたたみ実装（JS制御など）は使わない
- 既存の `wizard_components.ex` のコンポーネントを積極的に流用する
- `survey_year` の `max` 値はテンプレート内で `Date.utc_today().year` を使う
  （ハードコードしない）
- PDF 変換処理の起動順序を変えない
  （書誌フィールド保存 → 変換開始、の順を維持する）
- `upload.ex` のフォーム送信イベント名を変更しない