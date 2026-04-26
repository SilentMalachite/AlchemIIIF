defmodule AlchemIiifWeb.IIIF.PresentationControllerTest do
  use AlchemIiifWeb.ConnCase, async: true

  import AlchemIiif.Factory

  describe "GET /iiif/presentation/:source_id/manifest" do
    test "公開済み画像の Manifest を JSON-LD で返す", %{conn: conn} do
      source = insert_pdf_source(%{filename: "report_2026.pdf"})

      # published 画像を2つ作成
      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 2,
        status: "published",
        label: "fig-2-1",
        caption: nil,
        geometry: %{"x" => 0, "y" => 0, "width" => 800, "height" => 600}
      })

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published",
        label: "fig-1-1",
        caption: nil,
        geometry: %{"x" => 0, "y" => 0, "width" => 400, "height" => 300}
      })

      # draft 画像（含まれないはず）
      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 3,
        status: "draft",
        label: "fig-3-1"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      # IIIF 3.0 準拠の構造を検証
      assert response["@context"] == "http://iiif.io/api/presentation/3/context.json"
      assert response["type"] == "Manifest"
      assert response["label"] == %{"ja" => ["report_2026"], "en" => ["report_2026"]}
      refute Map.has_key?(response["label"], "none")

      # published 画像のみ含まれる（draft は除外）
      assert length(response["items"]) == 2

      # page_number 昇順で並んでいる
      [canvas1, canvas2] = response["items"]
      assert canvas1["label"] == %{"ja" => ["fig-1-1"], "en" => ["fig-1-1"]}
      assert canvas2["label"] == %{"ja" => ["fig-2-1"], "en" => ["fig-2-1"]}

      # Canvas の寸法が geometry から取得されている
      assert canvas1["width"] == 400
      assert canvas1["height"] == 300
      assert canvas2["width"] == 800
      assert canvas2["height"] == 600

      # Canvas 構造の検証
      assert canvas1["type"] == "Canvas"
      assert is_list(canvas1["items"])

      annotation_page = hd(canvas1["items"])
      assert annotation_page["type"] == "AnnotationPage"

      annotation = hd(annotation_page["items"])
      assert annotation["type"] == "Annotation"
      assert annotation["motivation"] == "painting"
      assert annotation["body"]["type"] == "Image"
    end

    test "存在しない source_id で 404 を返す", %{conn: conn} do
      conn = get(conn, "/iiif/presentation/999999/manifest")
      assert json_response(conn, 404)
      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "公開済み画像がない場合は書誌メタデータを返さず 404 にする", %{conn: conn} do
      source = insert_pdf_source()

      # draft のみ作成
      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "draft"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")

      assert json_response(conn, 404)["error"] =~ "見つかりません"
    end

    test "CORS ヘッダーが設定される", %{conn: conn} do
      source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    end

    test "Content-Type が application/ld+json", %{conn: conn} do
      source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      [content_type] = get_resp_header(conn, "content-type")
      assert content_type =~ "application/ld+json"
    end

    test "geometry が nil の場合はデフォルト寸法を使用", %{conn: conn} do
      source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published",
        geometry: nil
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      canvas = hd(response["items"])
      assert canvas["width"] == 1000
      assert canvas["height"] == 1000
    end

    test "書誌フィールドがある場合は recommended プロパティが出力される", %{conn: conn} do
      source =
        insert_pdf_source(%{
          filename: "report.pdf",
          investigating_org: "奈良文化財研究所",
          survey_year: 2024,
          report_title: "平城宮跡発掘調査報告書",
          license_uri: "https://creativecommons.org/licenses/by/4.0/"
        })

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
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
      assert provider["label"]["ja"] == ["奈良文化財研究所"]

      # metadata に書誌情報が含まれる
      metadata = response["metadata"]
      assert is_list(metadata)

      labels = Enum.map(metadata, fn m -> hd(m["label"]["en"]) end)
      assert "Investigating Organization" in labels
      assert "Survey Year" in labels
      assert "Report Title" in labels
    end

    test "書誌フィールドが nil の場合は recommended プロパティが省略される", %{conn: conn} do
      source = insert_pdf_source(%{filename: "report.pdf"})

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      refute Map.has_key?(response, "requiredStatement")
      refute Map.has_key?(response, "provider")
      assert response["metadata"] == nil or response["metadata"] == []
    end
  end

  describe "navDate" do
    test "survey_year が設定されている場合、navDate が出力される", %{conn: conn} do
      source =
        insert_pdf_source(%{
          filename: "report.pdf",
          survey_year: 2014
        })

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      assert response["navDate"] == "2014-01-01T00:00:00Z"
    end

    test "survey_year が nil の場合、navDate キーが存在しない", %{conn: conn} do
      source = insert_pdf_source(%{filename: "report.pdf", survey_year: nil})

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      refute Map.has_key?(response, "navDate")
    end
  end

  describe "rendering" do
    test "filename が設定されている場合、rendering 配列が出力される", %{conn: conn} do
      source = insert_pdf_source(%{filename: "report.pdf"})

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      assert is_list(response["rendering"])
      entry = hd(response["rendering"])
      assert entry["type"] == "Text"
      assert entry["format"] == "application/pdf"
      assert entry["id"] =~ "/download/pdf/#{source.id}"
    end
  end

  describe "summary" do
    test "report_title と investigating_org が両方ある場合、summary が出力される", %{conn: conn} do
      source =
        insert_pdf_source(%{
          filename: "report.pdf",
          report_title: "平城宮跡発掘調査報告書",
          investigating_org: "奈良文化財研究所"
        })

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      assert response["summary"]["ja"] == ["平城宮跡発掘調査報告書（奈良文化財研究所）"]
      assert response["summary"]["en"] == ["平城宮跡発掘調査報告書 (奈良文化財研究所)"]
    end

    test "report_title が nil の場合、summary キーが存在しない", %{conn: conn} do
      source = insert_pdf_source(%{filename: "report.pdf", report_title: nil})

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      refute Map.has_key?(response, "summary")
    end
  end

  describe "言語タグ付き label" do
    test "report_title がある場合、Manifest label が ja/en の言語タグ付きマップで返される", %{conn: conn} do
      source =
        insert_pdf_source(%{
          filename: "report.pdf",
          report_title: "黒姫洞穴遺跡"
        })

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      assert response["label"] == %{"ja" => ["黒姫洞穴遺跡"], "en" => ["黒姫洞穴遺跡"]}
      refute Map.has_key?(response["label"], "none")
    end

    test "Canvas label が label と caption から ja/en のマップで生成される", %{conn: conn} do
      source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published",
        label: "fig-1-1",
        caption: "縄文時代の深鉢形土器"
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      canvas = hd(response["items"])
      assert canvas["label"] == %{"ja" => ["fig-1-1 縄文時代の深鉢形土器"], "en" => ["fig-1-1"]}
    end

    test "Canvas の width/height が geometry から取得される", %{conn: conn} do
      source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published",
        geometry: %{"width" => 2480, "height" => 3508}
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      canvas = hd(response["items"])
      assert canvas["width"] == 2480
      assert canvas["height"] == 3508
    end

    test "geometry が nil の場合、実ファイルから幅・高さを取得する", %{conn: conn} do
      # priv/static/images/lab_wizard.png は 1024×574 の既存 PNG
      # uploads 配下にコピーして path confinement を通過させる
      uploads_dir = Application.app_dir(:alchem_iiif, "priv/static/uploads/test_fixtures")
      File.mkdir_p!(uploads_dir)

      dest_path =
        Path.join(uploads_dir, "lab_wizard_test_#{System.unique_integer([:positive])}.png")

      source_path = Application.app_dir(:alchem_iiif, "priv/static/images/lab_wizard.png")
      assert File.exists?(source_path), "フィクスチャ画像が存在しません: #{source_path}"
      File.cp!(source_path, dest_path)

      on_exit(fn -> File.rm(dest_path) end)

      # DB に保存する image_path は priv/static/ からの相対パス（本番慣習）
      filename = Path.basename(dest_path)
      relative_path = "priv/static/uploads/test_fixtures/#{filename}"

      source = insert_pdf_source()

      insert_extracted_image(%{
        pdf_source_id: source.id,
        page_number: 1,
        status: "published",
        geometry: nil,
        image_path: relative_path
      })

      conn = get(conn, "/iiif/presentation/#{source.id}/manifest")
      response = json_response(conn, 200)

      canvas = hd(response["items"])

      # Vix でファイルの実寸法（1024×574）を取得し、デフォルト値 1000 を返さないこと
      assert canvas["width"] == 1024
      assert canvas["height"] == 574
    end
  end
end
