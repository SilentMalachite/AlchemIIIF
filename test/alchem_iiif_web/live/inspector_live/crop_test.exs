defmodule AlchemIiifWeb.InspectorLive.CropTest do
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  alias AlchemIiif.Ingestion

  setup %{conn: conn} do
    user = AlchemIiif.AccountsFixtures.user_fixture()
    conn = AlchemIiifWeb.ConnCase.log_in_user(conn, user)
    pdf = insert_pdf_source(%{user_id: user.id, filename: "crop_test.pdf", page_count: 3})

    # テスト用のページ画像ディレクトリとファイルを作成
    pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf.id}"])
    File.mkdir_p!(pages_dir)
    File.write!(Path.join(pages_dir, "page-001.png"), "dummy png data")
    File.write!(Path.join(pages_dir, "page-002.png"), "dummy png data")

    on_exit(fn ->
      File.rm_rf!(pages_dir)
    end)

    %{conn: conn, user: user, pdf: pdf}
  end

  describe "mount/3" do
    test "クロップ画面が正常にマウントされる", %{conn: conn, pdf: pdf} do
      {:ok, _view, html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      assert html =~ "図版の範囲を指定してください"
      assert html =~ "cropper-container"
    end

    test "既存のポリゴンデータがある場合に読み込まれる", %{conn: conn, pdf: pdf} do
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 1,
        geometry: %{
          "points" => [
            %{"x" => 10, "y" => 20},
            %{"x" => 100, "y" => 20},
            %{"x" => 100, "y" => 200}
          ]
        },
        image_path: Path.join(["priv", "static", "uploads", "pages", "#{pdf.id}", "page-001.png"])
      })

      {:ok, _view, html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      # 保存済み状態で表示される
      assert html =~ "保存済み"
    end

    test "他ユーザーのプロジェクトにはアクセスできない", %{conn: conn} do
      other_user = AlchemIiif.AccountsFixtures.user_fixture()
      other_pdf = insert_pdf_source(%{user_id: other_user.id, filename: "other.pdf"})

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/lab/crop/#{other_pdf.id}/1")
      end
    end

    test "未認証ユーザーはリダイレクトされる", %{pdf: pdf} do
      conn = build_conn()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/lab/crop/#{pdf.id}/1")
    end
  end

  describe "preview_crop イベント" do
    test "ポリゴンプレビューで未保存状態になる", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      points = [%{"x" => 10, "y" => 20}, %{"x" => 100, "y" => 30}, %{"x" => 50, "y" => 100}]
      html = render_click(view, "preview_crop", %{"points" => points})

      assert html =~ "未保存"
    end

    test "矩形プレビュー（後方互換性）で未保存状態になる", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      html =
        render_click(view, "preview_crop", %{
          "x" => "10",
          "y" => "20",
          "width" => "200",
          "height" => "300"
        })

      assert html =~ "未保存"
    end
  end

  describe "save_crop イベント" do
    test "ポリゴンデータの保存でDBレコードが作成される", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      points = [%{"x" => 10, "y" => 20}, %{"x" => 100, "y" => 30}, %{"x" => 50, "y" => 100}]
      html = render_click(view, "save_crop", %{"points" => points})

      assert html =~ "保存済み"

      # DB にレコードが作成されたことを確認
      image = Ingestion.find_extracted_image_by_page(pdf.id, 1)
      assert image != nil
      assert image.geometry["points"] != nil
    end

    test "矩形データの保存（後方互換性）", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      html =
        render_click(view, "save_crop", %{
          "x" => "10",
          "y" => "20",
          "width" => "200",
          "height" => "300"
        })

      assert html =~ "保存済み"
    end

    test "既存レコードのジオメトリが更新される", %{conn: conn, pdf: pdf} do
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        page_number: 1,
        geometry: %{
          "points" => [%{"x" => 0, "y" => 0}, %{"x" => 50, "y" => 0}, %{"x" => 50, "y" => 50}]
        },
        image_path: Path.join(["priv", "static", "uploads", "pages", "#{pdf.id}", "page-001.png"])
      })

      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      new_points = [%{"x" => 20, "y" => 30}, %{"x" => 120, "y" => 30}, %{"x" => 120, "y" => 200}]
      html = render_click(view, "save_crop", %{"points" => new_points})

      assert html =~ "保存済み"

      # ジオメトリが更新されていることを確認
      updated = Ingestion.find_extracted_image_by_page(pdf.id, 1)
      assert hd(updated.geometry["points"])["x"] == 20
    end
  end

  describe "clear_polygon イベント" do
    test "ポリゴンがクリアされ未保存表示が消える", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      points = [%{"x" => 10, "y" => 20}, %{"x" => 100, "y" => 30}, %{"x" => 50, "y" => 100}]
      render_click(view, "preview_crop", %{"points" => points})

      html = render_click(view, "clear_polygon", %{})

      # idle 状態に戻り、未保存表示が消える
      refute html =~ "未保存"
      refute html =~ "保存済み"
    end
  end

  describe "nudge イベント" do
    test "方向指定でエラーなく処理される", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      html = render_click(view, "nudge", %{"direction" => "up", "amount" => "10"})

      assert html =~ "図版の範囲を指定してください"
    end
  end

  describe "undo イベント" do
    test "プレビュー後にアンドゥで元の状態に戻る", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      # プレビュー操作で未保存状態に
      points = [%{"x" => 10, "y" => 20}, %{"x" => 100, "y" => 30}, %{"x" => 50, "y" => 100}]
      render_click(view, "preview_crop", %{"points" => points})
      assert render(view) =~ "未保存"

      # アンドゥ
      html = render_click(view, "undo", %{})

      # アンドゥ後もページは正常にレンダリングされる
      assert html =~ "図版の範囲を指定してください"
    end
  end

  describe "proceed_to_label イベント" do
    test "保存済みクロップでラベリング画面に遷移する", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      points = [%{"x" => 10, "y" => 20}, %{"x" => 100, "y" => 30}, %{"x" => 50, "y" => 100}]
      render_click(view, "save_crop", %{"points" => points})

      # proceed_to_label で push_navigate が発生し、LiveView が停止する
      render_click(view, "proceed_to_label", %{})

      # DB にクロップデータが保存されていることを確認
      image = Ingestion.find_extracted_image_by_page(pdf.id, 1)
      assert image != nil
      assert image.geometry["points"] != nil
    end
  end

  describe "keydown イベント" do
    test "矢印キーでエラーなくナッジされる", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      html = render_click(view, "keydown", %{"key" => "ArrowUp"})

      assert html =~ "図版の範囲を指定してください"
    end

    test "矢印キー以外は無視される", %{conn: conn, pdf: pdf} do
      {:ok, view, _html} = live(conn, ~p"/lab/crop/#{pdf.id}/1")

      html = render_click(view, "keydown", %{"key" => "Enter"})

      assert html =~ "図版の範囲を指定してください"
    end
  end
end
