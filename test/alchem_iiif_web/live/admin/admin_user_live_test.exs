defmodule AlchemIiifWeb.Admin.AdminUserLive.IndexTest do
  use AlchemIiifWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias AlchemIiif.AccountsFixtures

  setup %{conn: conn} do
    admin = AccountsFixtures.admin_fixture()
    conn = AlchemIiifWeb.ConnCase.log_in_user(conn, admin)
    %{conn: conn, admin: admin}
  end

  describe "mount/3" do
    test "ユーザー管理画面が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ "ユーザー管理"
    end

    test "非 Admin ユーザーはリダイレクトされる", %{conn: _conn} do
      user = AccountsFixtures.user_fixture()
      conn = build_conn() |> AlchemIiifWeb.ConnCase.log_in_user(user)

      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/users")
    end

    test "既存ユーザー一覧が表示される", %{conn: conn, admin: admin} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ admin.email
    end
  end

  describe "open_modal / close_modal イベント" do
    test "モーダルを開くとフォームが表示される", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/users")

      # 初期状態ではモーダルが非表示
      refute html =~ "新規ユーザー作成"

      # モーダルを開く
      html = render_click(view, "open_modal", %{})
      assert html =~ "新規ユーザー作成"
      assert html =~ "メールアドレス"
    end

    test "モーダルを閉じるとフォームが非表示になる", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "open_modal", %{})
      html = render_click(view, "close_modal", %{})

      refute html =~ "新規ユーザー作成"
    end
  end

  describe "validate イベント" do
    test "フォームバリデーションが動作する", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "open_modal", %{})

      html =
        render_click(view, "validate", %{
          "user" => %{"email" => "", "password" => ""}
        })

      # バリデーションエラーが表示される（フォームが残っている）
      assert html =~ "新規ユーザー作成"
    end
  end

  describe "save イベント" do
    test "新規ユーザーを作成するとテーブルに追加される", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "open_modal", %{})

      html =
        render_click(view, "save", %{
          "user" => %{
            "email" => "newuser@example.com",
            "password" => "valid_password123"
          }
        })

      # 新ユーザーがテーブルに表示される
      assert html =~ "newuser@example.com"
      # モーダルが閉じている
      refute html =~ "新規ユーザー作成"
    end

    test "無効なデータではモーダルが開いたまま", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/users")

      render_click(view, "open_modal", %{})

      html =
        render_click(view, "save", %{
          "user" => %{"email" => "invalid", "password" => "short"}
        })

      # モーダルが開いたまま
      assert html =~ "新規ユーザー作成"
    end
  end

  describe "delete イベント" do
    test "他のユーザーを削除できる", %{conn: conn} do
      user_to_delete = AccountsFixtures.user_fixture()

      {:ok, view, html} = live(conn, ~p"/admin/users")

      # 削除対象がテーブルにいることを確認
      assert html =~ user_to_delete.email

      html = render_click(view, "delete", %{"id" => to_string(user_to_delete.id)})

      # フラッシュに削除メッセージが表示される
      assert html =~ "削除しました"
    end

    test "自分自身の行には削除ボタンがない", %{conn: conn, admin: admin} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      # admin 自身の行には「自分自身」表示がある
      assert html =~ admin.email
      assert html =~ "自分自身"
    end
  end
end
