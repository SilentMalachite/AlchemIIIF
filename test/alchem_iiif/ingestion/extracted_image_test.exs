defmodule AlchemIiif.Ingestion.ExtractedImageTest do
  use AlchemIiif.DataCase, async: true

  alias AlchemIiif.Ingestion.ExtractedImage
  import AlchemIiif.Factory

  describe "changeset/2" do
    test "有効な属性でチェンジセットが正常に作成される" do
      pdf_source = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        image_path: "priv/static/uploads/pages/1/page-001.png",
        caption: "テストキャプション",
        label: "fig-001"
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?
    end

    test "pdf_source_id と page_number が必須である" do
      changeset = ExtractedImage.changeset(%ExtractedImage{}, %{})
      refute changeset.valid?

      assert %{pdf_source_id: ["can't be blank"], page_number: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "status のデフォルト値が draft である" do
      image = %ExtractedImage{}
      assert image.status == "draft"
    end

    test "有効な status 値を受け入れる" do
      pdf_source = insert_pdf_source()

      for status <- ["draft", "pending_review", "published"] do
        attrs = %{pdf_source_id: pdf_source.id, page_number: 1, status: status}
        changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
        assert changeset.valid?, "status: #{status} は valid であるべき"
      end
    end

    test "無効な status 値を拒否する" do
      pdf_source = insert_pdf_source()
      attrs = %{pdf_source_id: pdf_source.id, page_number: 1, status: "archived"}
      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "geometry を JSONB マップとして保存できる" do
      pdf_source = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        geometry: %{"x" => 10, "y" => 20, "width" => 200, "height" => 300}
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :geometry) == %{
               "x" => 10,
               "y" => 20,
               "width" => 200,
               "height" => 300
             }
    end

    test "検索用メタデータフィールドが保存される" do
      pdf_source = insert_pdf_source()

      attrs = %{
        pdf_source_id: pdf_source.id,
        page_number: 1,
        site: "吉野ヶ里遺跡",
        period: "弥生時代",
        artifact_type: "銅鐸"
      }

      changeset = ExtractedImage.changeset(%ExtractedImage{}, attrs)
      assert changeset.valid?
    end
  end
end
