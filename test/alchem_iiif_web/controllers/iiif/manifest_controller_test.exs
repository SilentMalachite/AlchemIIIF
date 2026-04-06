defmodule AlchemIiifWeb.IIIF.ManifestControllerTest do
  use AlchemIiifWeb.ConnCase, async: true

  import AlchemIiif.Factory

  alias AlchemIiif.Iiif.Manifest
  alias AlchemIiif.Repo

  describe "GET /iiif/manifest/:identifier" do
    test "存在しない identifier で 404 を返す", %{conn: conn} do
      conn = get(conn, ~p"/iiif/manifest/nonexistent")
      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "published 画像の Manifest を JSON-LD で返す", %{conn: conn} do
      # published 画像と Manifest を作成
      image = insert_extracted_image(%{status: "published", ptif_path: "/tmp/test.tif"})

      identifier = "manifest-test-#{System.unique_integer([:positive])}"

      %Manifest{}
      |> Manifest.changeset(%{
        extracted_image_id: image.id,
        identifier: identifier,
        metadata: %{
          "label" => %{"en" => ["Test Image"], "ja" => ["テスト画像"]},
          "summary" => %{"en" => ["Summary"], "ja" => ["概要"]}
        }
      })
      |> Repo.insert!()

      conn = get(conn, "/iiif/manifest/#{identifier}")
      response = json_response(conn, 200)

      # IIIF 3.0 準拠の構造を検証
      assert response["@context"] == "http://iiif.io/api/presentation/3/context.json"
      assert response["type"] == "Manifest"
      assert is_list(response["items"])
      assert length(response["items"]) == 1

      # Canvas の検証
      canvas = hd(response["items"])
      assert canvas["type"] == "Canvas"
      assert is_integer(canvas["width"])
      assert is_integer(canvas["height"])
    end

    test "draft 画像の Manifest は 403 を返す", %{conn: conn} do
      image = insert_extracted_image(%{status: "draft", ptif_path: "/tmp/test.tif"})

      identifier = "draft-manifest-#{System.unique_integer([:positive])}"

      %Manifest{}
      |> Manifest.changeset(%{
        extracted_image_id: image.id,
        identifier: identifier,
        metadata: %{}
      })
      |> Repo.insert!()

      conn = get(conn, "/iiif/manifest/#{identifier}")
      assert json_response(conn, 403)
      assert json_response(conn, 403)["error"] =~ "公開されていません"
    end

    test "pending_review 画像の Manifest は 403 を返す", %{conn: conn} do
      image = insert_extracted_image(%{status: "pending_review", ptif_path: "/tmp/test.tif"})

      identifier = "pending-manifest-#{System.unique_integer([:positive])}"

      %Manifest{}
      |> Manifest.changeset(%{
        extracted_image_id: image.id,
        identifier: identifier,
        metadata: %{}
      })
      |> Repo.insert!()

      conn = get(conn, "/iiif/manifest/#{identifier}")
      assert json_response(conn, 403)
    end

    test "CORS ヘッダーが設定される", %{conn: conn} do
      image = insert_extracted_image(%{status: "published", ptif_path: "/tmp/test.tif"})

      identifier = "cors-test-#{System.unique_integer([:positive])}"

      %Manifest{}
      |> Manifest.changeset(%{
        extracted_image_id: image.id,
        identifier: identifier,
        metadata: %{
          "label" => %{"en" => ["Test"]},
          "summary" => %{"en" => ["Test"]}
        }
      })
      |> Repo.insert!()

      conn = get(conn, "/iiif/manifest/#{identifier}")
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    end

    test "PdfSource に書誌フィールドがある場合は recommended プロパティが出力される", %{conn: conn} do
      source =
        insert_pdf_source(%{
          filename: "report.pdf",
          investigating_org: "奈良文化財研究所",
          survey_year: 2024,
          report_title: "平城宮跡発掘調査報告書",
          license_uri: "https://creativecommons.org/licenses/by/4.0/"
        })

      image =
        insert_extracted_image(%{
          pdf_source_id: source.id,
          status: "published",
          ptif_path: "/tmp/test.tif"
        })

      identifier = "biblio-test-#{System.unique_integer([:positive])}"

      %AlchemIiif.Iiif.Manifest{}
      |> AlchemIiif.Iiif.Manifest.changeset(%{
        extracted_image_id: image.id,
        identifier: identifier,
        metadata: %{
          "label" => %{"en" => ["Test Image"]},
          "summary" => %{"en" => ["Summary"]}
        }
      })
      |> AlchemIiif.Repo.insert!()

      conn = get(conn, "/iiif/manifest/#{identifier}")
      response = json_response(conn, 200)

      # requiredStatement
      assert response["requiredStatement"]["label"]["ja"] == ["提供機関"]
      assert response["requiredStatement"]["value"]["ja"] == ["奈良文化財研究所"]

      # rights
      assert response["rights"] == "https://creativecommons.org/licenses/by/4.0/"

      # provider
      assert is_list(response["provider"])
      provider = hd(response["provider"])
      assert provider["type"] == "Agent"

      # metadata に書誌情報が含まれる
      metadata = response["metadata"]
      assert is_list(metadata)

      en_labels = Enum.map(metadata, fn m -> hd(m["label"]["en"]) end)
      assert "Investigating Organization" in en_labels
    end

    test "PdfSource に書誌フィールドがない場合は recommended プロパティが省略される", %{conn: conn} do
      image = insert_extracted_image(%{status: "published", ptif_path: "/tmp/test.tif"})

      identifier = "no-biblio-#{System.unique_integer([:positive])}"

      %AlchemIiif.Iiif.Manifest{}
      |> AlchemIiif.Iiif.Manifest.changeset(%{
        extracted_image_id: image.id,
        identifier: identifier,
        metadata: %{
          "label" => %{"en" => ["Test"]},
          "summary" => %{"en" => ["Test"]}
        }
      })
      |> AlchemIiif.Repo.insert!()

      conn = get(conn, "/iiif/manifest/#{identifier}")
      response = json_response(conn, 200)

      refute Map.has_key?(response, "requiredStatement")
      refute Map.has_key?(response, "provider")
    end
  end
end
