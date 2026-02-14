defmodule AlchemIiifWeb.InspectorLive.BrowseTest do
  @moduledoc """
  Browse LiveView のテスト。

  ウィザード Step 2 のページ閲覧・選択画面をテストします。
  マウント時の初期表示、select_page イベントの安全なパース、
  crop 画面への遷移、エラーハンドリングを検証します。

  ## Write-on-Action ポリシー
  select_page はレコードを作成せず、selected_page の assign のみ更新します。
  proceed_to_crop は pdf_source_id と page_number のみで Crop に遷移します。
  """
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  describe "マウント" do
    test "正常な PDF Source でステップ2が表示される", %{conn: conn} do
      pdf_source = insert_pdf_source(%{status: "ready"})

      # テスト用ページ画像ディレクトリを作成
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)

      # ダミーのページ画像ファイルを作成
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # ステップ2（ページ選択）が表示される
      assert html =~ "ページを選択してください"
      assert html =~ "ページ 1"
    after
      # テスト用ファイルをクリーンアップ
      File.rm_rf!("priv/static/uploads/pages")
    end

    test "存在しない PDF Source でリダイレクトされる", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/lab", flash: flash}}} =
               live(conn, ~p"/lab/browse/999999")

      assert flash["error"] =~ "指定されたPDFソースが見つかりません"
    end

    test "ページ画像がない場合に警告が表示される", %{conn: conn} do
      pdf_source = insert_pdf_source(%{status: "ready"})

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      assert html =~ "画像が見つかりませんでした"
    end

    test "エラーステータスの PDF Source でエラー画面が表示される", %{conn: conn} do
      pdf_source = insert_pdf_source(%{status: "error"})

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      assert html =~ "PDFの処理中にエラーが発生しました"
    end
  end

  describe "select_page イベント（Write-on-Action）" do
    test "有効なページ番号で selected_page のみ更新（レコード作成なし）", %{conn: conn} do
      pdf_source = insert_pdf_source(%{status: "ready"})

      # テスト用ページ画像ディレクトリ・ファイルを作成
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, view, _html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # サムネイルクリック → ページ遷移ではなく、selected_page の更新のみ
      html =
        view
        |> element("button.page-thumbnail", "ページ 1")
        |> render_click()

      # ページは遷移せず同じ画面に留まる（selected クラスが付与される）
      assert html =~ "selected"
      assert html =~ "ページを選択してください"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end

    test "proceed_to_crop で crop 画面（pdf_source_id/page_number）に遷移する", %{conn: conn} do
      pdf_source = insert_pdf_source(%{status: "ready"})

      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, view, _html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # まずページを選択
      view
      |> element("button.page-thumbnail", "ページ 1")
      |> render_click()

      # proceed_to_crop で crop 画面に遷移
      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element("button.btn-primary", "次へ: クロップ")
               |> render_click()

      assert to =~ "/lab/crop/#{pdf_source.id}/1"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end

    test "無効なページ番号でエラーがハンドリングされる", %{conn: conn} do
      pdf_source = insert_pdf_source(%{status: "ready"})
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, view, _html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # 無効なページ番号を直接イベント送信 — クラッシュしないことを確認
      assert render_hook(view, "select_page", %{"page" => "invalid"}) =~ "ページを選択してください"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end

    test "存在しないページ番号でエラーがハンドリングされる", %{conn: conn} do
      pdf_source = insert_pdf_source(%{status: "ready"})
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, view, _html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      # 存在しないページ番号（999）を送信 — クラッシュしないことを確認
      assert render_hook(view, "select_page", %{"page" => "999"}) =~ "ページを選択してください"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end
  end

  describe "ナビゲーション" do
    test "戻るリンクが Lab トップを指す", %{conn: conn} do
      pdf_source = insert_pdf_source(%{status: "ready"})
      pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
      File.mkdir_p!(pages_dir)
      File.write!(Path.join(pages_dir, "page-001.png"), "dummy")

      {:ok, _view, html} = live(conn, ~p"/lab/browse/#{pdf_source.id}")

      assert html =~ "← 戻る"
      assert html =~ "/lab"
    after
      File.rm_rf!("priv/static/uploads/pages")
    end
  end
end
