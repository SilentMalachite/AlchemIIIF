defmodule AlchemIiifWeb.ApprovalLiveTest do
  use AlchemIiifWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  describe "mount/3" do
    test "承認ダッシュボードが正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      assert html =~ "承認ダッシュボード"
    end

    test "レビュー待ちの画像が表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/pending.tif",
        status: "pending_review",
        label: "レビュー待ちテスト"
      })

      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      assert html =~ "レビュー待ちテスト"
      assert html =~ "レビュー待ち: 1 件"
    end

    test "レビュー待ちがない場合はメッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      assert html =~ "レビュー待ちの図版はありません"
    end

    test "draft 画像は承認ダッシュボードに表示されない", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/draft.tif",
        status: "draft",
        label: "下書きの画像"
      })

      {:ok, _view, html} = live(conn, ~p"/lab/approval")

      refute html =~ "下書きの画像"
    end
  end

  describe "approve イベント" do
    test "画像を承認して公開する", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/pending.tif",
          status: "pending_review",
          label: "承認テスト画像"
        })

      {:ok, view, _html} = live(conn, ~p"/lab/approval")

      html = render_click(view, "approve", %{"id" => to_string(image.id)})

      # 承認後、レビュー待ちリストから消え、0件になる
      assert html =~ "レビュー待ち: 0 件"
      assert html =~ "レビュー待ちの図版はありません"
    end
  end

  describe "reject イベント" do
    test "画像を差し戻す", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/pending.tif",
          status: "pending_review",
          label: "差し戻しテスト画像"
        })

      {:ok, view, _html} = live(conn, ~p"/lab/approval")

      html = render_click(view, "reject", %{"id" => to_string(image.id)})

      # 差し戻し後、レビュー待ちリストから消え、0件になる
      assert html =~ "レビュー待ち: 0 件"
      assert html =~ "レビュー待ちの図版はありません"
    end
  end
end
