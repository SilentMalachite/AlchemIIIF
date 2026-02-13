defmodule AlchemIiif.IngestionTest do
  use AlchemIiif.DataCase, async: true

  alias AlchemIiif.Ingestion
  alias AlchemIiif.Ingestion.{ExtractedImage, PdfSource}
  import AlchemIiif.Factory

  # === PdfSource テスト ===

  describe "list_pdf_sources/0" do
    test "全ての PdfSource を返す" do
      pdf1 = insert_pdf_source(%{filename: "report_a.pdf"})
      pdf2 = insert_pdf_source(%{filename: "report_b.pdf"})

      result = Ingestion.list_pdf_sources()
      ids = Enum.map(result, & &1.id)

      assert pdf1.id in ids
      assert pdf2.id in ids
    end

    test "PdfSource がない場合は空リストを返す" do
      assert Ingestion.list_pdf_sources() == []
    end
  end

  describe "get_pdf_source!/1" do
    test "ID で PdfSource を取得する" do
      pdf = insert_pdf_source()
      assert Ingestion.get_pdf_source!(pdf.id).id == pdf.id
    end

    test "存在しない ID で Ecto.NoResultsError を発生させる" do
      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_pdf_source!(0)
      end
    end
  end

  describe "create_pdf_source/1" do
    test "有効な属性で PdfSource を作成する" do
      attrs = %{filename: "new_report.pdf", page_count: 15, status: "uploading"}
      assert {:ok, %PdfSource{} = pdf} = Ingestion.create_pdf_source(attrs)
      assert pdf.filename == "new_report.pdf"
      assert pdf.page_count == 15
      assert pdf.status == "uploading"
    end

    test "無効な属性でエラーを返す" do
      assert {:error, %Ecto.Changeset{}} = Ingestion.create_pdf_source(%{})
    end
  end

  describe "update_pdf_source/2" do
    test "PdfSource を更新する" do
      pdf = insert_pdf_source(%{status: "uploading"})
      assert {:ok, updated} = Ingestion.update_pdf_source(pdf, %{status: "ready", page_count: 20})
      assert updated.status == "ready"
      assert updated.page_count == 20
    end
  end

  # === ExtractedImage テスト ===

  describe "list_extracted_images/1" do
    test "指定した PdfSource の画像のみを返す" do
      pdf1 = insert_pdf_source()
      pdf2 = insert_pdf_source()

      img1 = insert_extracted_image(%{pdf_source_id: pdf1.id, page_number: 1})
      _img2 = insert_extracted_image(%{pdf_source_id: pdf2.id, page_number: 1})

      result = Ingestion.list_extracted_images(pdf1.id)
      assert length(result) == 1
      assert hd(result).id == img1.id
    end

    test "画像がない場合は空リストを返す" do
      pdf = insert_pdf_source()
      assert Ingestion.list_extracted_images(pdf.id) == []
    end
  end

  describe "get_extracted_image!/1" do
    test "ID で ExtractedImage を取得する" do
      image = insert_extracted_image()
      assert Ingestion.get_extracted_image!(image.id).id == image.id
    end

    test "存在しない ID で Ecto.NoResultsError を発生させる" do
      assert_raise Ecto.NoResultsError, fn ->
        Ingestion.get_extracted_image!(0)
      end
    end
  end

  describe "create_extracted_image/1" do
    test "有効な属性で ExtractedImage を作成する" do
      pdf = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf.id,
        page_number: 3,
        image_path: "priv/static/uploads/pages/1/page-003.png",
        caption: "テスト図版"
      }

      assert {:ok, %ExtractedImage{} = image} = Ingestion.create_extracted_image(attrs)
      assert image.page_number == 3
      assert image.caption == "テスト図版"
      assert image.status == "draft"
    end

    test "必須フィールド未指定でエラーを返す" do
      assert {:error, %Ecto.Changeset{}} = Ingestion.create_extracted_image(%{})
    end
  end

  describe "update_extracted_image/2" do
    test "ExtractedImage を更新する" do
      image = insert_extracted_image()

      assert {:ok, updated} =
               Ingestion.update_extracted_image(image, %{
                 caption: "更新されたキャプション",
                 label: "fig-updated"
               })

      assert updated.caption == "更新されたキャプション"
      assert updated.label == "fig-updated"
    end
  end

  # === ステータス遷移テスト ===

  describe "submit_for_review/1" do
    test "draft → pending_review に遷移する" do
      image = insert_extracted_image(%{status: "draft"})
      assert {:ok, updated} = Ingestion.submit_for_review(image)
      assert updated.status == "pending_review"
    end

    test "draft 以外のステータスではエラーを返す" do
      image = insert_extracted_image(%{status: "published"})
      assert {:error, :invalid_status_transition} = Ingestion.submit_for_review(image)
    end

    test "pending_review からの遷移はエラーを返す" do
      image = insert_extracted_image(%{status: "pending_review"})
      assert {:error, :invalid_status_transition} = Ingestion.submit_for_review(image)
    end
  end

  describe "approve_and_publish/1" do
    test "pending_review → published に遷移する" do
      image = insert_extracted_image(%{status: "pending_review"})
      assert {:ok, updated} = Ingestion.approve_and_publish(image)
      assert updated.status == "published"
    end

    test "pending_review 以外のステータスではエラーを返す" do
      image = insert_extracted_image(%{status: "draft"})
      assert {:error, :invalid_status_transition} = Ingestion.approve_and_publish(image)
    end
  end

  describe "reject_to_draft/1" do
    test "pending_review → draft に遷移する" do
      image = insert_extracted_image(%{status: "pending_review"})
      assert {:ok, updated} = Ingestion.reject_to_draft(image)
      assert updated.status == "draft"
    end

    test "pending_review 以外のステータスではエラーを返す" do
      image = insert_extracted_image(%{status: "draft"})
      assert {:error, :invalid_status_transition} = Ingestion.reject_to_draft(image)
    end

    test "published からの遷移はエラーを返す" do
      image = insert_extracted_image(%{status: "published"})
      assert {:error, :invalid_status_transition} = Ingestion.reject_to_draft(image)
    end
  end

  describe "list_pending_review_images/0" do
    test "pending_review の画像を返す（PTIF の有無を問わない）" do
      _draft = insert_extracted_image(%{status: "draft", ptif_path: "/path/to/test.tif"})

      pending_with_ptif =
        insert_extracted_image(%{status: "pending_review", ptif_path: "/path/to/test2.tif"})

      _published = insert_extracted_image(%{status: "published", ptif_path: "/path/to/test3.tif"})
      pending_no_ptif = insert_extracted_image(%{status: "pending_review", ptif_path: nil})

      result = Ingestion.list_pending_review_images()
      ids = Enum.map(result, & &1.id)

      assert pending_with_ptif.id in ids
      assert pending_no_ptif.id in ids
      assert length(result) == 2
    end
  end

  describe "list_all_images_for_lab/0" do
    test "PTIF ありの全ステータス画像を返す" do
      img1 = insert_extracted_image(%{status: "draft", ptif_path: "/path/a.tif"})
      img2 = insert_extracted_image(%{status: "published", ptif_path: "/path/b.tif"})
      _no_ptif = insert_extracted_image(%{status: "draft", ptif_path: nil})

      result = Ingestion.list_all_images_for_lab()
      ids = Enum.map(result, & &1.id)

      assert img1.id in ids
      assert img2.id in ids
      assert length(result) == 2
    end
  end
end
