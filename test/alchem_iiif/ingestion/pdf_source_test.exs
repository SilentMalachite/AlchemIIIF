defmodule AlchemIiif.Ingestion.PdfSourceTest do
  use AlchemIiif.DataCase, async: true

  alias AlchemIiif.Ingestion.PdfSource

  describe "changeset/2" do
    test "有効な属性でチェンジセットが正常に作成される" do
      attrs = %{filename: "report.pdf", page_count: 5, status: "ready"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
    end

    test "filename が必須である" do
      attrs = %{page_count: 5}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{filename: ["can't be blank"]} = errors_on(changeset)
    end

    test "status のデフォルト値が uploading である" do
      pdf_source = %PdfSource{}
      assert pdf_source.status == "uploading"
    end

    test "有効な status 値を受け入れる" do
      for status <- ["uploading", "converting", "ready", "error"] do
        attrs = %{filename: "test.pdf", status: status}
        changeset = PdfSource.changeset(%PdfSource{}, attrs)
        assert changeset.valid?, "status: #{status} は valid であるべき"
      end
    end

    test "無効な status 値を拒否する" do
      attrs = %{filename: "test.pdf", status: "invalid_status"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{status: _} = errors_on(changeset)
    end

    test "書誌フィールドが cast される" do
      attrs = %{
        filename: "report.pdf",
        investigating_org: "奈良文化財研究所",
        survey_year: 2024,
        report_title: "平城宮跡発掘調査報告書",
        license_uri: "https://creativecommons.org/licenses/by/4.0/"
      }

      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :investigating_org) == "奈良文化財研究所"
      assert Ecto.Changeset.get_change(changeset, :survey_year) == 2024
      assert Ecto.Changeset.get_change(changeset, :report_title) == "平城宮跡発掘調査報告書"

      assert Ecto.Changeset.get_change(changeset, :license_uri) ==
               "https://creativecommons.org/licenses/by/4.0/"
    end

    test "書誌フィールドなしでも changeset は valid" do
      attrs = %{filename: "report.pdf"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
    end

    test "survey_year が 1900 未満の場合は invalid" do
      attrs = %{filename: "report.pdf", survey_year: 1899}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{survey_year: _} = errors_on(changeset)
    end

    test "survey_year が現在年を超える場合は invalid" do
      attrs = %{filename: "report.pdf", survey_year: Date.utc_today().year + 1}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{survey_year: _} = errors_on(changeset)
    end

    test "survey_year が現在年の場合は valid" do
      attrs = %{filename: "report.pdf", survey_year: Date.utc_today().year}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
    end

    test "license_uri が不正な形式の場合は invalid" do
      attrs = %{filename: "report.pdf", license_uri: "not-a-uri"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{license_uri: _} = errors_on(changeset)
    end

    test "license_uri が http:// で始まる場合は valid" do
      attrs = %{filename: "report.pdf", license_uri: "http://rightsstatements.org/vocab/InC/1.0/"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
    end

    test "license_uri が https:// で始まる場合は valid" do
      attrs = %{
        filename: "report.pdf",
        license_uri: "https://creativecommons.org/licenses/by/4.0/"
      }

      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
    end

    test "investigating_org が 200 文字を超える場合は invalid" do
      attrs = %{filename: "report.pdf", investigating_org: String.duplicate("あ", 201)}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{investigating_org: _} = errors_on(changeset)
    end

    test "report_title が 500 文字を超える場合は invalid" do
      attrs = %{filename: "report.pdf", report_title: String.duplicate("あ", 501)}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{report_title: _} = errors_on(changeset)
    end
  end

  describe "changeset/2 site_code validation" do
    test "任意形式の site_code を受け入れる" do
      attrs = %{filename: "report.pdf", site_code: "15206-27"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
    end

    test "site_code が nil の場合は valid（任意項目）" do
      attrs = %{filename: "report.pdf", site_code: nil}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      assert changeset.valid?
    end

    test "site_code が 31 文字を超える場合は invalid" do
      attrs = %{filename: "report.pdf", site_code: String.duplicate("1", 31)}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)
      refute changeset.valid?
      assert %{site_code: _} = errors_on(changeset)
    end
  end

  describe "source_type" do
    alias AlchemIiif.Ingestion.PdfSource

    test "デフォルト値は \"pdf\"" do
      assert %PdfSource{}.source_type == "pdf"
    end

    test ~s(pdf と zip を受け入れる) do
      for type <- ["pdf", "zip"] do
        cs = PdfSource.changeset(%PdfSource{}, %{filename: "x.pdf", source_type: type})
        assert cs.valid?, "source_type=#{type} は valid であるべき"
      end
    end

    test "未知の source_type を拒否する" do
      cs = PdfSource.changeset(%PdfSource{}, %{filename: "x.pdf", source_type: "tar"})
      refute cs.valid?
      assert %{source_type: _} = errors_on(cs)
    end

    test "source_type を空にすると invalid" do
      cs = PdfSource.changeset(%PdfSource{}, %{filename: "x.pdf", source_type: nil})
      refute cs.valid?
      assert %{source_type: _} = errors_on(cs)
    end

    test "pdf?/1 は struct と map と nil を区別する" do
      assert PdfSource.pdf?(%PdfSource{source_type: "pdf"})
      assert PdfSource.pdf?(%{source_type: "pdf"})
      refute PdfSource.pdf?(%PdfSource{source_type: "zip"})
      refute PdfSource.pdf?(%{source_type: "zip"})
      refute PdfSource.pdf?(nil)
      refute PdfSource.pdf?(%{})
    end

    test "zip?/1 は struct と map と nil を区別する" do
      assert PdfSource.zip?(%PdfSource{source_type: "zip"})
      assert PdfSource.zip?(%{source_type: "zip"})
      refute PdfSource.zip?(%PdfSource{source_type: "pdf"})
      refute PdfSource.zip?(%{source_type: "pdf"})
      refute PdfSource.zip?(nil)
      refute PdfSource.zip?(%{})
    end
  end

  describe "storage_key auto-generation" do
    test "新規作成時に storage_key が未指定なら UUID が自動付与される" do
      attrs = %{filename: "report.pdf"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)

      assert changeset.valid?
      key = Ecto.Changeset.get_change(changeset, :storage_key)
      assert is_binary(key)
      assert {:ok, _} = Ecto.UUID.cast(key)
    end

    test "明示的に渡された storage_key は維持される" do
      attrs = %{filename: "report.pdf", storage_key: "explicit-key-123"}
      changeset = PdfSource.changeset(%PdfSource{}, attrs)

      assert Ecto.Changeset.get_field(changeset, :storage_key) == "explicit-key-123"
    end

    test "ファイル名違いの 2 ソースは異なる storage_key を持つ" do
      cs_a =
        PdfSource.changeset(%PdfSource{}, %{filename: "a.pdf"})

      cs_b =
        PdfSource.changeset(%PdfSource{}, %{filename: "b.pdf"})

      key_a = Ecto.Changeset.get_change(cs_a, :storage_key)
      key_b = Ecto.Changeset.get_change(cs_b, :storage_key)

      refute key_a == key_b
    end

    test "更新時に既存 storage_key が空文字に上書きされない" do
      existing = %PdfSource{storage_key: "preserve-me"}
      changeset = PdfSource.changeset(existing, %{filename: "renamed.pdf"})

      assert Ecto.Changeset.get_field(changeset, :storage_key) == "preserve-me"
    end
  end
end
