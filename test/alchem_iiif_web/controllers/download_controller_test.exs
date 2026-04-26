defmodule AlchemIiifWeb.DownloadControllerTest do
  use AlchemIiifWeb.ConnCase, async: true

  import AlchemIiif.Factory

  describe "GET /download/:id" do
    test "存在しない画像は 404 を返す", %{conn: conn} do
      conn = get(conn, ~p"/download/999999")

      assert response(conn, 404) =~ "画像が見つかりません"
    end

    test "非公開画像は 403 を返す", %{conn: conn} do
      image = insert_extracted_image(%{status: "draft"})

      conn = get(conn, ~p"/download/#{image.id}")

      assert response(conn, 403) =~ "この画像はダウンロードできません"
    end

    test "pending_review 画像は 403 を返す", %{conn: conn} do
      image = insert_extracted_image(%{status: "pending_review"})

      conn = get(conn, ~p"/download/#{image.id}")

      assert response(conn, 403) =~ "この画像はダウンロードできません"
    end

    test "rejected 画像は 403 を返す", %{conn: conn} do
      image = insert_extracted_image(%{status: "rejected"})

      conn = get(conn, ~p"/download/#{image.id}")

      assert response(conn, 403) =~ "この画像はダウンロードできません"
    end
  end

  describe "GET /download/pdf/:id" do
    test "公開済み画像を含む PDF だけを配信する", %{conn: conn} do
      filename = "published-source-#{System.unique_integer([:positive])}.pdf"
      write_pdf_fixture(filename, "%PDF-1.7 published")

      source = insert_pdf_source(%{filename: filename})
      insert_extracted_image(%{pdf_source_id: source.id, status: "published"})

      conn = get(conn, "/download/pdf/#{source.id}")

      assert response(conn, 200) == "%PDF-1.7 published"
      assert ["application/pdf" <> _] = get_resp_header(conn, "content-type")
    end

    test "公開済み画像がない PDF は配信しない", %{conn: conn} do
      filename = "draft-source-#{System.unique_integer([:positive])}.pdf"
      write_pdf_fixture(filename, "%PDF-1.7 draft")

      source = insert_pdf_source(%{filename: filename})
      insert_extracted_image(%{pdf_source_id: source.id, status: "draft"})

      conn = get(conn, "/download/pdf/#{source.id}")

      assert response(conn, 404)
    end
  end

  describe "build_filename (間接テスト)" do
    test "公開済み画像のダウンロードはセマンティックファイル名を含む", %{conn: conn} do
      # 実際のダウンロードには画像ファイルが必要なので、
      # ファイルがない場合のエラーハンドリングを確認
      image =
        insert_extracted_image(%{
          status: "published",
          ptif_path: "/path/to/test.tif",
          site: "テスト市遺跡",
          label: "fig-99-1",
          artifact_type: "土器",
          image_path: "/nonexistent/path.png",
          geometry: %{"x" => 0, "y" => 0, "width" => 100, "height" => 100}
        })

      conn = get(conn, ~p"/download/#{image.id}")

      # 画像ファイルが存在しないため 500 エラーになることを確認
      assert conn.status == 500
      assert response(conn, 500) =~ "画像の処理に失敗しました"
    end
  end

  defp write_pdf_fixture(filename, contents) do
    dir = Path.join(["priv", "uploads", "pdfs"])
    path = Path.join(dir, filename)

    File.mkdir_p!(dir)
    File.write!(path, contents)

    on_exit(fn -> File.rm(path) end)

    path
  end
end
