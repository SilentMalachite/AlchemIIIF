defmodule AlchemIiifWeb.Admin.AdminTrashLive.IndexTest do
  use AlchemIiifWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  setup %{conn: conn} do
    admin = AlchemIiif.AccountsFixtures.admin_fixture()
    conn = AlchemIiifWeb.ConnCase.log_in_user(conn, admin)
    %{conn: conn, admin: admin}
  end

  describe "mount/3" do
    test "ゴミ箱画面が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/trash")

      assert html =~ "ゴミ箱"
    end

    test "非 Admin ユーザーはリダイレクトされる", %{conn: _conn} do
      user = AlchemIiif.AccountsFixtures.user_fixture()
      conn = build_conn() |> AlchemIiifWeb.ConnCase.log_in_user(user)

      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/trash")
    end

    test "ゴミ箱が空の場合はメッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/trash")

      assert html =~ "ゴミ箱は空です"
    end

    test "削除済みプロジェクトが表示される", %{conn: conn, admin: admin} do
      pdf = insert_pdf_source(%{user_id: admin.id, filename: "trashed.pdf"})
      AlchemIiif.Ingestion.soft_delete_pdf_source(pdf)

      {:ok, _view, html} = live(conn, ~p"/admin/trash")

      assert html =~ "trashed.pdf"
    end
  end

  describe "restore イベント" do
    test "削除済みプロジェクトを復元できる", %{conn: conn, admin: admin} do
      pdf = insert_pdf_source(%{user_id: admin.id, filename: "restore_me.pdf"})
      AlchemIiif.Ingestion.soft_delete_pdf_source(pdf)

      {:ok, view, _html} = live(conn, ~p"/admin/trash")

      html = render_click(view, "restore", %{"id" => to_string(pdf.id)})

      assert html =~ "復元しました"
      # テーブル行からは消えている
      refute html =~ "trash-row-#{pdf.id}"
    end
  end

  describe "destroy イベント" do
    test "プロジェクトを完全削除できる", %{conn: conn, admin: admin} do
      pdf = insert_pdf_source(%{user_id: admin.id, filename: "destroy_me.pdf"})
      AlchemIiif.Ingestion.soft_delete_pdf_source(pdf)

      {:ok, view, _html} = live(conn, ~p"/admin/trash")

      html = render_click(view, "destroy", %{"id" => to_string(pdf.id)})

      assert html =~ "完全に削除しました"
      refute html =~ "trash-row-#{pdf.id}"
    end
  end
end
