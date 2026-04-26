defmodule AlchemIiifWeb.MediaControllerTest do
  use AlchemIiifWeb.ConnCase, async: false

  import AlchemIiif.Factory

  describe "static uploads" do
    test "priv/static/uploads 配下のファイルは直接公開されない", %{conn: conn} do
      path =
        Application.app_dir(
          :alchem_iiif,
          "priv/static/uploads/security-static/private-#{System.unique_integer([:positive])}.txt"
        )

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "private upload")

      on_exit(fn -> File.rm(path) end)

      conn = get(conn, "/uploads/security-static/#{Path.basename(path)}")

      assert response(conn, 404)
    end
  end

  describe "GET /media/images/:id/source" do
    test "公開済み画像の元ファイルだけを配信する", %{conn: conn} do
      path = write_upload_fixture("published-image.png", "published image")
      image = insert_extracted_image(%{status: "published", image_path: path})

      conn = get(conn, "/media/images/#{image.id}/source")

      assert response(conn, 200) == "published image"
      assert get_resp_header(conn, "content-type") == ["image/png"]
    end

    test "未公開画像の元ファイルは公開ルートから配信しない", %{conn: conn} do
      path = write_upload_fixture("draft-image.png", "draft image")
      image = insert_extracted_image(%{status: "draft", image_path: path})

      conn = get(conn, "/media/images/#{image.id}/source")

      assert response(conn, 404)
    end
  end

  describe "GET /lab/media/images/:id/source" do
    test "所有者は Lab ルートから元画像を参照できる", %{conn: conn} do
      owner = insert_user()
      source = insert_pdf_source(%{user_id: owner.id})
      path = write_upload_fixture("owner-image.png", "owner image")

      image =
        insert_extracted_image(%{
          pdf_source_id: source.id,
          owner_id: owner.id,
          status: "draft",
          image_path: path
        })

      conn =
        conn
        |> log_in_user(owner)
        |> get("/lab/media/images/#{image.id}/source")

      assert response(conn, 200) == "owner image"
      assert get_resp_header(conn, "content-type") == ["image/png"]
    end

    test "別ユーザーは Lab ルートから元画像を参照できない", %{conn: conn} do
      owner = insert_user()
      other_user = insert_user()
      source = insert_pdf_source(%{user_id: owner.id})
      path = write_upload_fixture("other-user-image.png", "owner only")

      image =
        insert_extracted_image(%{
          pdf_source_id: source.id,
          owner_id: owner.id,
          status: "draft",
          image_path: path
        })

      conn =
        conn
        |> log_in_user(other_user)
        |> get("/lab/media/images/#{image.id}/source")

      assert response(conn, 404)
    end
  end

  defp write_upload_fixture(filename, contents) do
    dir = Path.join(["priv", "uploads", "test_media", "#{System.unique_integer([:positive])}"])
    path = Path.join(dir, filename)

    File.mkdir_p!(dir)
    File.write!(path, contents)

    on_exit(fn -> File.rm_rf(dir) end)

    path
  end
end
