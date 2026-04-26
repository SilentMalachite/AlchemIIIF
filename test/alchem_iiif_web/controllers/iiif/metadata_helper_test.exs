defmodule AlchemIiifWeb.IIIF.MetadataHelperTest do
  use ExUnit.Case, async: true

  alias AlchemIiifWeb.IIIF.MetadataHelper

  describe "build_required_statement/1" do
    test "investigating_org がある場合は requiredStatement を返す" do
      source = %{investigating_org: "奈良文化財研究所"}
      result = MetadataHelper.build_required_statement(source)

      assert result == %{
               "label" => %{"ja" => ["提供機関"], "en" => ["Attribution"]},
               "value" => %{"ja" => ["奈良文化財研究所"], "en" => ["奈良文化財研究所"]}
             }
    end

    test "investigating_org が nil の場合は nil を返す" do
      source = %{investigating_org: nil}
      assert MetadataHelper.build_required_statement(source) == nil
    end
  end

  describe "build_provider/1" do
    test "investigating_org がある場合は provider を返す" do
      source = %{investigating_org: "奈良文化財研究所"}
      result = MetadataHelper.build_provider(source)

      assert is_list(result)
      assert length(result) == 1

      agent = hd(result)
      assert agent["type"] == "Agent"
      assert agent["label"] == %{"ja" => ["奈良文化財研究所"], "en" => ["奈良文化財研究所"]}
      assert is_binary(agent["id"])
    end

    test "investigating_org が nil の場合は nil を返す" do
      source = %{investigating_org: nil}
      assert MetadataHelper.build_provider(source) == nil
    end
  end

  describe "build_bibliographic_metadata/1" do
    test "全フィールドがある場合は3つのメタデータエントリを返す" do
      source = %{
        investigating_org: "奈良文化財研究所",
        survey_year: 2024,
        report_title: "発掘調査報告書"
      }

      result = MetadataHelper.build_bibliographic_metadata(source)
      assert length(result) == 3

      labels = Enum.map(result, fn entry -> entry["label"]["en"] end)
      assert ["Investigating Organization"] in labels
      assert ["Survey Year"] in labels
      assert ["Report Title"] in labels
    end

    test "survey_year がある場合は「2024年」形式で出力" do
      source = %{investigating_org: nil, survey_year: 2024, report_title: nil}
      result = MetadataHelper.build_bibliographic_metadata(source)

      assert length(result) == 1
      entry = hd(result)
      assert entry["value"] == %{"ja" => ["2024年"], "en" => ["2024"]}
    end

    test "全フィールドが nil の場合は空リストを返す" do
      source = %{investigating_org: nil, survey_year: nil, report_title: nil}
      result = MetadataHelper.build_bibliographic_metadata(source)
      assert result == []
    end
  end

  describe "build_recommended_properties/1" do
    test "全フィールドがある場合は全キーを含む" do
      source = %{
        investigating_org: "奈良文化財研究所",
        license_uri: "https://creativecommons.org/licenses/by/4.0/",
        report_title: "発掘調査報告書",
        survey_year: 2024,
        filename: "report.pdf",
        id: 123
      }

      result = MetadataHelper.build_recommended_properties(source)

      assert Map.has_key?(result, "requiredStatement")
      assert Map.has_key?(result, "rights")
      assert Map.has_key?(result, "provider")
      assert Map.has_key?(result, "summary")
      assert Map.has_key?(result, "navDate")
      assert Map.has_key?(result, "rendering")
    end

    test "investigating_org が nil の場合は requiredStatement と provider を含まない" do
      source = %{
        investigating_org: nil,
        license_uri: "https://creativecommons.org/licenses/by/4.0/"
      }

      result = MetadataHelper.build_recommended_properties(source)

      refute Map.has_key?(result, "requiredStatement")
      assert Map.has_key?(result, "rights")
      refute Map.has_key?(result, "provider")
    end

    test "license_uri が nil の場合は rights を含まない" do
      source = %{investigating_org: "奈良文化財研究所", license_uri: nil}
      result = MetadataHelper.build_recommended_properties(source)

      assert Map.has_key?(result, "requiredStatement")
      refute Map.has_key?(result, "rights")
      assert Map.has_key?(result, "provider")
    end

    test "全フィールドが nil の場合は空マップを返す" do
      source = %{investigating_org: nil, license_uri: nil}
      result = MetadataHelper.build_recommended_properties(source)
      assert result == %{}
    end
  end

  describe "format_nav_date/1" do
    test "整数の年を ISO 8601 形式に変換する" do
      assert MetadataHelper.format_nav_date(2014) == "2014-01-01T00:00:00Z"
    end

    test "nil の場合は nil を返す" do
      assert MetadataHelper.format_nav_date(nil) == nil
    end
  end

  describe "build_summary/1" do
    test "report_title と investigating_org が両方ある場合は日英の summary を返す" do
      source = %{report_title: "発掘調査報告書", investigating_org: "奈良文化財研究所"}
      result = MetadataHelper.build_summary(source)

      assert result["ja"] == ["発掘調査報告書（奈良文化財研究所）"]
      assert result["en"] == ["発掘調査報告書 (奈良文化財研究所)"]
    end

    test "report_title のみの場合は title だけの summary を返す" do
      source = %{report_title: "発掘調査報告書", investigating_org: nil}
      result = MetadataHelper.build_summary(source)

      assert result["ja"] == ["発掘調査報告書"]
      assert result["en"] == ["発掘調査報告書"]
    end

    test "report_title が nil の場合は nil を返す" do
      source = %{report_title: nil, investigating_org: "奈良文化財研究所"}
      assert MetadataHelper.build_summary(source) == nil
    end
  end

  describe "build_rendering/1" do
    test "filename がある場合は PDF rendering 配列を返す" do
      source = %{id: 123, filename: "report.pdf"}
      result = MetadataHelper.build_rendering(source)

      assert is_list(result)
      assert length(result) == 1

      entry = hd(result)
      assert entry["type"] == "Text"
      assert entry["format"] == "application/pdf"
      assert entry["id"] =~ "/download/pdf/123"
      assert entry["label"]["ja"] == ["原本PDF"]
      assert entry["label"]["en"] == ["Original PDF"]
    end

    test "filename が nil の場合は nil を返す" do
      source = %{filename: nil}
      assert MetadataHelper.build_rendering(source) == nil
    end

    test "filename が空文字の場合は nil を返す" do
      source = %{filename: ""}
      assert MetadataHelper.build_rendering(source) == nil
    end
  end

  describe "strip_timestamp/1" do
    test "末尾の -<digits>.pdf を除去する" do
      assert MetadataHelper.strip_timestamp("黒姫洞穴遺跡-1775979589.pdf") == "黒姫洞穴遺跡"
    end

    test "桁数に依らず除去する" do
      assert MetadataHelper.strip_timestamp("foo-1.pdf") == "foo"
      assert MetadataHelper.strip_timestamp("foo-1234567890123.pdf") == "foo"
    end

    test "タイムスタンプが無ければ .pdf のみ除去" do
      assert MetadataHelper.strip_timestamp("report.pdf") == "report"
    end

    test "nil を空文字にフォールバック" do
      assert MetadataHelper.strip_timestamp(nil) == ""
    end
  end

  describe "build_manifest_label/1" do
    test "report_title があればそれを使う" do
      source = %{report_title: "黒姫洞穴遺跡", filename: "黒姫洞穴遺跡-1775979589.pdf"}

      assert MetadataHelper.build_manifest_label(source) ==
               %{"ja" => ["黒姫洞穴遺跡"], "en" => ["黒姫洞穴遺跡"]}
    end

    test "report_title が nil なら filename からタイムスタンプを除去" do
      source = %{report_title: nil, filename: "test-1234567890.pdf"}

      assert MetadataHelper.build_manifest_label(source) ==
               %{"ja" => ["test"], "en" => ["test"]}
    end

    test "\"none\" キーは含まれない" do
      source = %{report_title: "x", filename: "x.pdf"}
      refute Map.has_key?(MetadataHelper.build_manifest_label(source), "none")
    end

    test "report_title と filename が両方 nil の場合は (無題)/(Untitled) フォールバック" do
      source = %{report_title: nil, filename: nil}

      assert MetadataHelper.build_manifest_label(source) ==
               %{"ja" => ["(無題)"], "en" => ["(Untitled)"]}
    end
  end

  describe "build_canvas_label/1" do
    test "caption があれば ja に label と caption を結合した値を返す" do
      image = %{label: "fig-2-1", caption: "縄文時代の深鉢形土器"}
      result = MetadataHelper.build_canvas_label(image)
      assert result["ja"] == ["fig-2-1 縄文時代の深鉢形土器"]
      assert result["en"] == ["fig-2-1"]
    end

    test "caption が nil/空なら label のみ" do
      assert MetadataHelper.build_canvas_label(%{label: "fig-2-1", caption: nil}) ==
               %{"ja" => ["fig-2-1"], "en" => ["fig-2-1"]}

      assert MetadataHelper.build_canvas_label(%{label: "fig-2-1", caption: ""}) ==
               %{"ja" => ["fig-2-1"], "en" => ["fig-2-1"]}
    end

    test "label が nil の場合はフォールバック文字列を使う" do
      result = MetadataHelper.build_canvas_label(%{label: nil, caption: nil, page_number: 3})
      assert result == %{"ja" => ["Page 3"], "en" => ["Page 3"]}
    end

    test "\"none\" キーは含まれない" do
      image = %{label: "fig-1-1", caption: nil}
      refute Map.has_key?(MetadataHelper.build_canvas_label(image), "none")
    end

    test "page_number キーが無い場合は \"Page ?\" にフォールバック" do
      assert MetadataHelper.build_canvas_label(%{label: nil, caption: nil}) ==
               %{"ja" => ["Page ?"], "en" => ["Page ?"]}
    end
  end
end
