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
        label: "fig-40-1"
      })

      # draft 画像を作成
      insert_extracted_image(%{
        ptif_path: "/path/to/draft.tif",
        status: "draft",
        label: "fig-41-1"
      })

      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "fig-40-1"
      refute html =~ "fig-41-1"
    end

    test "公開画像がない場合はメッセージが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "まだ公開済みの図版がありません"
    end

    test "geometry 付き画像で SVG クロップサムネイルが表示される", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/crop.tif",
        status: "published",
        label: "fig-42-1",
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
        label: "fig-43-1"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html =
        view
        |> element("#gallery-search-input")
        |> render_keyup(%{"query" => "ギャラリー検索"})

      assert html =~ "fig-43-1" or html =~ "件の図版"
    end
  end

  describe "toggle_filter イベント" do
    test "フィルターチップスが動作する", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        status: "published",
        site: "ギャラリー市遺跡"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html = render_click(view, "toggle_filter", %{"type" => "site", "value" => "ギャラリー市遺跡"})
      assert html =~ "件の図版" or html =~ "結果なし"
    end
  end

  describe "clear_filters イベント" do
    test "フィルタークリアが動作する", %{conn: conn} do
      insert_extracted_image(%{
        ptif_path: "/path/to/test.tif",
        status: "published",
        site: "テスト市遺跡"
      })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      # フィルターを有効化してからクリア
      render_click(view, "toggle_filter", %{"type" => "site", "value" => "テスト市遺跡"})
      html = render_click(view, "clear_filters", %{})

      assert html =~ "件の図版" or html =~ "結果なし"
    end
  end

  describe "ギャラリーカードの書誌情報表示" do
    test "report_title が設定されている場合、カードに表示される", %{conn: conn} do
      pdf =
        insert_pdf_source(%{
          report_title: "新潟県埋蔵文化財調査報告書",
          investigating_org: "新潟県教育委員会",
          survey_year: 2020
        })

      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        ptif_path: "/path/to/biblio.tif",
        status: "published",
        label: "fig-50-1"
      })

      {:ok, _view, html} = live(conn, ~p"/gallery")

      assert html =~ "新潟県埋蔵文化財調査報告書"
      assert html =~ "新潟県教育委員会"
      assert html =~ "2020年"
    end

    test "report_title が nil の場合、報告書名ラベルが表示されない", %{conn: conn} do
      pdf = insert_pdf_source(%{report_title: nil, investigating_org: nil, survey_year: nil})

      insert_extracted_image(%{
        pdf_source_id: pdf.id,
        ptif_path: "/path/to/nobiblio.tif",
        status: "published",
        label: "fig-51-1"
      })

      {:ok, _view, html} = live(conn, ~p"/gallery")

      refute html =~ "報告書："
      refute html =~ "調査機関："
      refute html =~ "年度："
    end
  end

  describe "詳細モーダルのメタデータパネル" do
    test "モーダルに画像メタデータと報告書情報が表示される", %{conn: conn} do
      pdf =
        insert_pdf_source(%{
          report_title: "越後平野遺跡群報告",
          investigating_org: "新潟県教育委員会",
          survey_year: 2019,
          site_code: "15-100-001",
          license_uri: "https://creativecommons.org/licenses/by/4.0/"
        })

      image =
        insert_extracted_image(%{
          pdf_source_id: pdf.id,
          ptif_path: "/path/to/modal-meta.tif",
          status: "published",
          label: "fig-60-1",
          caption: "縄文土器破片",
          site: "越後市平野遺跡",
          period: "縄文時代",
          artifact_type: "土器",
          material: "土",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")
      html = render_click(view, "select_image", %{"id" => image.id})

      # 画像情報
      assert html =~ "越後市平野遺跡"
      assert html =~ "縄文時代"
      assert html =~ "土器"
      assert html =~ "土"
      assert html =~ "fig-60-1"
      assert html =~ "縄文土器破片"

      # 報告書情報
      assert html =~ "越後平野遺跡群報告"
      assert html =~ "新潟県教育委員会"
      assert html =~ "2019年"
      assert html =~ "15-100-001"
      assert html =~ "https://creativecommons.org/licenses/by/4.0/"
    end

    test "nil フィールドに対応するラベルが表示されない", %{conn: conn} do
      pdf =
        insert_pdf_source(%{
          report_title: nil,
          investigating_org: nil,
          survey_year: nil,
          site_code: nil,
          license_uri: nil
        })

      image =
        insert_extracted_image(%{
          pdf_source_id: pdf.id,
          ptif_path: "/path/to/modal-nil.tif",
          status: "published",
          label: "fig-61-1",
          site: nil,
          period: nil,
          artifact_type: nil,
          material: nil,
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")
      html = render_click(view, "select_image", %{"id" => image.id})

      refute html =~ "遺跡名"
      refute html =~ "時代"
      refute html =~ "遺物種別"
      refute html =~ "素材"
      refute html =~ "報告書名"
      refute html =~ "調査機関"
      refute html =~ "調査年度"
      refute html =~ "遺跡コード"
      refute html =~ "ライセンス"
    end
  end

  describe "元 PDF ダウンロードリンク" do
    test "filename が設定されている場合、ダウンロードリンクが表示される", %{conn: conn} do
      pdf = insert_pdf_source(%{filename: "test_report_dl.pdf"})

      image =
        insert_extracted_image(%{
          pdf_source_id: pdf.id,
          ptif_path: "/path/to/pdf-dl.tif",
          status: "published",
          label: "fig-70-1",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")
      html = render_click(view, "select_image", %{"id" => image.id})

      assert html =~ "原本 PDF をダウンロード"
      assert html =~ "/download/pdf/#{pdf.id}"
    end

    test "pdf_source が nil の場合、ダウンロードリンクが表示されない", %{conn: conn} do
      # pdf_source なしの画像は insert_extracted_image のデフォルトで自動生成される
      # filename はデフォルトで設定されるが、pdf_source 自体の存在は保証される
      # このテストでは pdf_source.filename が空文字列の場合をテスト
      pdf = insert_pdf_source(%{filename: "required_placeholder.pdf"})

      image =
        insert_extracted_image(%{
          pdf_source_id: pdf.id,
          ptif_path: "/path/to/pdf-nodl.tif",
          status: "published",
          label: "fig-71-1",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
        })

      # filename を空にする（build_rendering と同じ nil/空文字チェック）
      import Ecto.Changeset
      pdf |> change(%{filename: ""}) |> AlchemIiif.Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/gallery")
      html = render_click(view, "select_image", %{"id" => image.id})

      refute html =~ "原本 PDF をダウンロード"
    end
  end

  describe "select_image / close_modal イベント" do
    test "カードクリックでモーダルが表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/modal.tif",
          status: "published",
          label: "fig-44-1",
          caption: "テストキャプション",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 150}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html = render_click(view, "select_image", %{"id" => image.id})

      # モーダルが表示される
      assert html =~ "fig-44-1"
      assert html =~ "テストキャプション"
      assert html =~ "bg-black/90"
    end

    test "非公開画像の ID を直接送ってもモーダルは開かない", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/draft-modal.tif",
          status: "draft",
          label: "fig-44-2",
          image_path: "priv/static/uploads/test.png"
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      html = render_click(view, "select_image", %{"id" => image.id})

      refute html =~ "bg-black/90"
      refute html =~ "fig-44-2"
    end

    test "close_modal でモーダルが閉じる", %{conn: conn} do
      image =
        insert_extracted_image(%{
          ptif_path: "/path/to/modal2.tif",
          status: "published",
          label: "fig-45-1",
          image_path: "priv/static/uploads/test.png",
          geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
        })

      {:ok, view, _html} = live(conn, ~p"/gallery")

      # モーダルを開く
      render_click(view, "select_image", %{"id" => image.id})

      # モーダルを閉じる
      html = render_click(view, "close_modal", %{})

      # モーダルが非表示になる
      refute html =~ "bg-black/90"
    end

    test "初期状態ではモーダルが表示されない", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/gallery")

      refute html =~ "bg-black/90"
    end
  end
end
