defmodule AlchemIiifWeb.IIIF.ImageControllerTest do
  use AlchemIiifWeb.ConnCase, async: true

  import AlchemIiif.Factory

  describe "GET /iiif/image/:identifier/info.json" do
    test "存在しない identifier で 404 を返す", %{conn: conn} do
      conn = get(conn, ~p"/iiif/image/nonexistent/info.json")
      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "未公開画像の identifier は PTIF が存在しても 404 を返す", %{conn: conn} do
      ptif_path =
        Path.join(System.tmp_dir!(), "alchemiiif-pending-#{System.unique_integer()}.tif")

      File.write!(ptif_path, "not a real ptif")
      on_exit(fn -> File.rm(ptif_path) end)

      image = insert_extracted_image(%{status: "pending_review", ptif_path: ptif_path})

      manifest =
        insert_manifest(%{identifier: "img-pending-review-test", extracted_image_id: image.id})

      conn = get(conn, ~p"/iiif/image/#{manifest.identifier}/info.json")

      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end
  end

  describe "GET /iiif/image/:identifier/:region/:size/:rotation/:quality" do
    test "存在しない identifier で 404 を返す", %{conn: conn} do
      conn = get(conn, "/iiif/image/nonexistent/full/max/0/default.jpg")
      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "Manifest はあるが PTIF ファイルがない場合 404 を返す", %{conn: conn} do
      # PTIF パスは存在しないパスを設定
      manifest =
        insert_manifest(%{
          identifier: "img-no-ptif-test"
        })

      # ptif_path は関連する extracted_image に自動設定されるが、ファイルは存在しない
      conn = get(conn, "/iiif/image/#{manifest.identifier}/full/max/0/default.jpg")
      assert json_response(conn, 404)
    end

    test "未公開画像のタイルは PTIF が存在しても 404 を返す", %{conn: conn} do
      ptif_path = Path.join(System.tmp_dir!(), "alchemiiif-draft-#{System.unique_integer()}.tif")
      File.write!(ptif_path, "not a real ptif")
      on_exit(fn -> File.rm(ptif_path) end)

      image = insert_extracted_image(%{status: "draft", ptif_path: ptif_path})

      manifest =
        insert_manifest(%{identifier: "img-draft-tile-test", extracted_image_id: image.id})

      conn = get(conn, "/iiif/image/#{manifest.identifier}/full/max/0/default.jpg")

      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end
  end
end
