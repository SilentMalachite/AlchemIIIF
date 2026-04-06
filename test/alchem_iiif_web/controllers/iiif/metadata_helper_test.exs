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
    test "全フィールドがある場合は3つのキーを含む" do
      source = %{
        investigating_org: "奈良文化財研究所",
        license_uri: "https://creativecommons.org/licenses/by/4.0/"
      }

      result = MetadataHelper.build_recommended_properties(source)

      assert Map.has_key?(result, "requiredStatement")
      assert Map.has_key?(result, "rights")
      assert Map.has_key?(result, "provider")
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
end
