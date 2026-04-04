defmodule AlchemIiifWeb.LabLive.ShowTest do
  use AlchemIiifWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  setup %{conn: conn} do
    user = AlchemIiif.AccountsFixtures.user_fixture()
    conn = AlchemIiifWeb.ConnCase.log_in_user(conn, user)
    pdf = insert_pdf_source(%{user_id: user.id, filename: "show_test.pdf", page_count: 3})
    %{conn: conn, user: user, pdf: pdf}
  end

  describe "mount/3" do
    test "プロジェクト詳細が正常にマウントされる", %{conn: conn, pdf: pdf} do
      {:ok, _view, html} = live(conn, ~p"/lab/projects/#{pdf.id}")

      assert html =~ "show_test.pdf"
      assert html =~ "取り込み完了"
    end

    test "画像がない場合は空メッセージが表示される", %{conn: conn, pdf: pdf} do
      {:ok, _view, html} = live(conn, ~p"/lab/projects/#{pdf.id}")

      assert html =~ "画像がありません"
    end

    test "画像がある場合はグリッドが表示される", %{conn: conn, pdf: pdf} do
      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        label: "fig-90-1",
        status: "draft"
      })

      {:ok, _view, html} = live(conn, ~p"/lab/projects/#{pdf.id}")

      assert html =~ "fig-90-1"
      assert html =~ "下書き"
    end

    test "他ユーザーのプロジェクトにはアクセスできない", %{conn: conn} do
      other_user = AlchemIiif.AccountsFixtures.user_fixture()
      other_pdf = insert_pdf_source(%{user_id: other_user.id, filename: "other.pdf"})

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/lab/projects/#{other_pdf.id}")
      end
    end

    test "未認証ユーザーはリダイレクトされる", %{pdf: pdf} do
      conn = build_conn()

      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/lab/projects/#{pdf.id}")
    end
  end

  describe "画像ステータス表示" do
    test "各ステータスのラベルが正しく表示される", %{conn: conn, pdf: pdf} do
      insert_extracted_image(%{pdf_source_id: pdf.id, status: "draft", label: "fig-91-1"})

      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        status: "pending_review",
        label: "fig-92-1",
        page_number: 2
      })

      {:ok, _view, html} = live(conn, ~p"/lab/projects/#{pdf.id}")

      assert html =~ "下書き"
      assert html =~ "レビュー待ち"
    end
  end
end
