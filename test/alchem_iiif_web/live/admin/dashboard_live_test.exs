defmodule AlchemIiifWeb.Admin.DashboardLiveTest do
  use AlchemIiifWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  # Admin ロール必須
  setup %{conn: conn} do
    admin = AlchemIiif.AccountsFixtures.admin_fixture()
    conn = AlchemIiifWeb.ConnCase.log_in_user(conn, admin)
    %{conn: conn, admin: admin}
  end

  describe "mount/3" do
    test "Dashboard が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/dashboard")

      assert html =~ "Admin Dashboard"
    end

    test "非 Admin ユーザーはリダイレクトされる", %{conn: _conn} do
      user = AlchemIiif.AccountsFixtures.user_fixture()
      conn = build_conn() |> AlchemIiifWeb.ConnCase.log_in_user(user)

      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/dashboard")
    end

    test "画像がない場合は空メッセージが表示される", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      # 非同期ロード完了を待つ
      html = render(view)

      assert html =~ "アップロードされた画像はまだありません"
    end

    test "画像一覧が非同期で表示される", %{conn: conn} do
      image = insert_extracted_image(%{status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")

      # 非同期ロード完了後に再レンダリング
      html = render(view)

      assert html =~ "image-row-#{image.id}"
    end
  end

  describe "toggle_selection イベント" do
    test "画像を選択・解除できる", %{conn: conn} do
      image = insert_extracted_image(%{status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")
      render(view)

      # 選択
      html = render_click(view, "toggle_selection", %{"id" => to_string(image.id)})

      assert html =~ "1 件選択中"

      # 解除
      html = render_click(view, "toggle_selection", %{"id" => to_string(image.id)})

      refute html =~ "件選択中"
    end
  end

  describe "toggle_all イベント" do
    test "全選択・全解除が動作する", %{conn: conn} do
      insert_extracted_image(%{status: "draft"})
      insert_extracted_image(%{status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")
      render(view)

      # 全選択
      html = render_click(view, "toggle_all", %{})

      assert html =~ "2 件選択中"

      # 全解除
      html = render_click(view, "toggle_all", %{})

      refute html =~ "件選択中"
    end
  end

  describe "delete イベント" do
    test "下書き画像を削除するとテーブルから消える", %{conn: conn} do
      image = insert_extracted_image(%{status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")
      render(view)

      html = render_click(view, "delete", %{"id" => to_string(image.id)})

      # テーブルから行が消える
      refute html =~ "image-row-#{image.id}"
    end

    test "公開済み画像は通常削除で行が残る", %{conn: conn} do
      image =
        insert_extracted_image(%{
          status: "published",
          ptif_path: "/path/to/pub.tif",
          site: "テスト市遺跡"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")
      render(view)

      html = render_click(view, "delete", %{"id" => to_string(image.id)})

      # 公開済みのため行は残る
      assert html =~ "image-row-#{image.id}"
    end
  end

  describe "force_delete イベント" do
    test "公開済み画像を強制削除するとテーブルから消える", %{conn: conn} do
      image =
        insert_extracted_image(%{
          status: "published",
          ptif_path: "/path/to/force.tif",
          site: "テスト市遺跡"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")
      render(view)

      html = render_click(view, "force_delete", %{"id" => to_string(image.id)})

      refute html =~ "image-row-#{image.id}"
    end
  end

  describe "delete_selected イベント" do
    test "選択した画像を一括削除するとテーブルから消える", %{conn: conn} do
      img1 = insert_extracted_image(%{status: "draft"})
      img2 = insert_extracted_image(%{status: "draft"})

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")
      render(view)

      render_click(view, "toggle_selection", %{"id" => to_string(img1.id)})
      render_click(view, "toggle_selection", %{"id" => to_string(img2.id)})

      html = render_click(view, "delete_selected", %{})

      refute html =~ "image-row-#{img1.id}"
      refute html =~ "image-row-#{img2.id}"
    end

    test "公開済み画像はスキップされる", %{conn: conn} do
      img_draft = insert_extracted_image(%{status: "draft"})

      img_pub =
        insert_extracted_image(%{
          status: "published",
          ptif_path: "/path/to/batch.tif",
          site: "テスト市遺跡"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/dashboard")
      render(view)

      render_click(view, "toggle_selection", %{"id" => to_string(img_draft.id)})
      render_click(view, "toggle_selection", %{"id" => to_string(img_pub.id)})

      html = render_click(view, "delete_selected", %{})

      # draft は削除、published は残る
      refute html =~ "image-row-#{img_draft.id}"
      assert html =~ "image-row-#{img_pub.id}"
    end
  end
end
