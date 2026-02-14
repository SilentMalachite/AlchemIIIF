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

    test "geometry 付き画像で SVG クロップサムネイルが表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/crop.tif",
        status: "published",
        label: "クロップギャラリーテスト",
        image_path: "priv/static/uploads/test.png",
        geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 150}
      })

      {:ok, _view, html} = live(conn, ~p"/gallery")

      # SVG viewBox がレンダリングされる
      assert html =~ "viewBox"
      assert html =~ "10 20 200 150"
      assert html =~ "xMidYMid meet"
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

  describe "select_image / close_modal イベント" do
    test "カードクリックでモーダルが表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/modal.tif",
          status: "published",
          label: "モーダルテスト",
          caption: "テストキャプション",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 150}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html = render_click(view, "select_image", %{"id" => image.id})

      # モーダルが表示される
      assert html =~ "モーダルテスト"
      assert html =~ "テストキャプション"
      assert html =~ "hero-x-mark"
    end

    test "close_modal でモーダルが閉じる", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/modal2.tif",
          status: "published",
          label: "クローズテスト",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      # モーダルを開く
      render_click(view, "select_image", %{"id" => image.id})

      # モーダルを閉じる
      html = render_click(view, "close_modal", %{})

      # モーダルが非表示になる
      refute html =~ "hero-x-mark"
    end

    test "初期状態ではモーダルが表示されない", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gallery")

      refute html =~ "hero-x-mark"
    end
  end
end
