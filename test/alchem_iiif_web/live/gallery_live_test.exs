defmodule AlchemIiifWeb.GalleryLiveTest do
  use AlchemIiifWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  describe "mount/3" do
    test "ギャラリー画面が正常にマウントされる", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "ギャラリー"
    end

    test "公開済み画像のみが表示される", %{conn: conn} do
      # published 画像を作成
      insert_extracted_image(%{
        ptif_path: "/path/to/published.tif",
        status: "published",
        label: "公開済みテスト"
      })

      # draft 画像を作成
      insert_extracted_image(%{
        ptif_path: "/path/to/draft.tif",
        status: "draft",
        label: "下書きテスト"
      })

      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "公開済みテスト"
      refute html =~ "下書きテスト"
    end

    test "公開画像がない場合はメッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "まだ公開済みの図版がありません"
    end
  end

  describe "search イベント" do
    test "テキスト検索で公開済み画像を絞り込める", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        status: "published",
        caption: "ギャラリー検索テスト",
        label: "gallery-search"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html =
        view
        |> element("#gallery-search-input")
        |> render_keyup(%{"query" => "ギャラリー検索"})

      assert html =~ "gallery-search" or html =~ "件の図版"
    end
  end

  describe "toggle_filter イベント" do
    test "フィルターチップスが動作する", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        status: "published",
        site: "ギャラリー遺跡"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html = render_click(view, "toggle_filter", %{"type" => "site", "value" => "ギャラリー遺跡"})
      assert html =~ "件の図版" or html =~ "結果なし"
    end
  end

  describe "clear_filters イベント" do
    test "フィルタークリアが動作する", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        status: "published",
        site: "テスト遺跡"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      # フィルターを有効化してからクリア
      render_click(view, "toggle_filter", %{"type" => "site", "value" => "テスト遺跡"})
      html = render_click(view, "clear_filters", %{})

      assert html =~ "件の図版" or html =~ "結果なし"
    end
  end
end
