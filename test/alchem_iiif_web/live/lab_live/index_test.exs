defmodule AlchemIiifWeb.LabLive.IndexTest do
  use AlchemIiifWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  setup %{conn: conn} do
    user = AlchemIiif.AccountsFixtures.user_fixture()
    conn = AlchemIiifWeb.ConnCase.log_in_user(conn, user)
    %{conn: conn, user: user}
  end

  describe "mount/3" do
    test "プロジェクト一覧が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab")

      assert html =~ "プロジェクト一覧"
    end

    test "プロジェクトがない場合は空メッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab")

      assert html =~ "プロジェクトがまだありません"
    end

    test "ユーザーのプロジェクトが表示される", %{conn: conn, user: user} do
      _pdf = insert_pdf_source(%{user_id: user.id, filename: "test_report.pdf", page_count: 5})

      {:ok, _view, html} = live(conn, ~p"/lab")

      assert html =~ "test_report.pdf"
      assert html =~ "5 ページ"
    end

    test "他ユーザーのプロジェクトは表示されない", %{conn: conn} do
      other_user = AlchemIiif.AccountsFixtures.user_fixture()
      insert_pdf_source(%{user_id: other_user.id, filename: "other_report.pdf"})

      {:ok, _view, html} = live(conn, ~p"/lab")

      refute html =~ "other_report.pdf"
    end

    test "未認証ユーザーはリダイレクトされる", %{conn: _conn} do
      conn = build_conn()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/lab")
    end
  end

  describe "delete_project イベント" do
    test "プロジェクトをゴミ箱に移動できる", %{conn: conn, user: user} do
      pdf = insert_pdf_source(%{user_id: user.id, filename: "delete_target.pdf"})

      {:ok, view, _html} = live(conn, ~p"/lab")

      html = render_click(view, "delete_project", %{"id" => to_string(pdf.id)})

      # 削除後、プロジェクト一覧からカードが消える
      refute html =~ "delete_target.pdf"
    end

    test "公開中のプロジェクトには削除ボタンが表示されない", %{conn: conn, user: user} do
      pdf = insert_pdf_source(%{user_id: user.id, filename: "published_project.pdf"})

      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        status: "published",
        ptif_path: "/path/to/pub.tif",
        site: "テスト市遺跡"
      })

      {:ok, _view, html} = live(conn, ~p"/lab")

      # 公開中バッジが表示される
      assert html =~ "公開中"
      # 削除ボタンの代わりにロックバッジが表示される
      assert html =~ "lock-badge"
    end
  end

  describe "submit_project イベント" do
    test "WIP プロジェクトを提出できる", %{conn: conn, user: user} do
      pdf =
        insert_pdf_source(%{
          user_id: user.id,
          filename: "submit_target.pdf",
          workflow_status: "wip"
        })

      {:ok, view, _html} = live(conn, ~p"/lab")

      html = render_click(view, "submit_project", %{"id" => to_string(pdf.id)})

      # 提出後にステータスが「審査待ち」に変わる
      assert html =~ "審査待ち"
    end

    test "pending_review のプロジェクトには提出ボタンが表示されない", %{conn: conn, user: user} do
      _pdf =
        insert_pdf_source(%{
          user_id: user.id,
          filename: "already_submitted.pdf",
          workflow_status: "pending_review"
        })

      {:ok, _view, html} = live(conn, ~p"/lab")

      # 審査待ちバッジが表示される
      assert html =~ "審査待ち"

      # 提出ボタンは表示されない（pending_review は wip/returned に含まれない）
      refute html =~ "btn-submit-workflow"
    end
  end

  describe "Admin ユーザーの場合" do
    setup %{conn: _conn} do
      admin = AlchemIiif.AccountsFixtures.admin_fixture()
      conn = build_conn() |> AlchemIiifWeb.ConnCase.log_in_user(admin)
      %{conn: conn, admin: admin}
    end

    test "全プロジェクトが表示される", %{conn: conn} do
      other_user = AlchemIiif.AccountsFixtures.user_fixture()
      insert_pdf_source(%{user_id: other_user.id, filename: "admin_visible.pdf"})

      {:ok, _view, html} = live(conn, ~p"/lab")

      assert html =~ "admin_visible.pdf"
    end
  end
end
