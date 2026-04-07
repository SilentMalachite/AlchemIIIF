defmodule AlchemIiifWeb.IIIF.MetadataHelper do
  @moduledoc """
  IIIF Presentation API v3.0 の recommended プロパティ生成ヘルパー。
  requiredStatement / rights / provider および書誌メタデータを構築する。
  """

  @doc """
  requiredStatement を構築する。
  investigating_org が nil の場合は nil を返す。
  """
  def build_required_statement(%{investigating_org: nil}), do: nil

  def build_required_statement(%{investigating_org: org}) do
    %{
      "label" => %{"ja" => ["提供機関"], "en" => ["Attribution"]},
      "value" => %{"ja" => [org], "en" => [org]}
    }
  end

  @doc """
  provider を構築する。
  investigating_org が nil の場合は nil を返す。
  """
  def build_provider(%{investigating_org: nil}), do: nil

  def build_provider(%{investigating_org: org}) do
    [
      %{
        "id" => AlchemIiifWeb.Endpoint.url(),
        "type" => "Agent",
        "label" => %{"ja" => [org], "en" => [org]}
      }
    ]
  end

  @doc """
  書誌フィールドから IIIF metadata エントリのリストを構築する。
  nil のフィールドは省略する。
  """
  def build_bibliographic_metadata(source) do
    [
      label_value("調査機関", "Investigating Organization", Map.get(source, :investigating_org)),
      label_value("調査年度", "Survey Year", Map.get(source, :survey_year)),
      label_value("報告書名", "Report Title", Map.get(source, :report_title)),
      label_value("遺跡コード", "Site Code", Map.get(source, :site_code))
    ]
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  recommended プロパティ（requiredStatement, rights, provider, summary, navDate, rendering）をマップで返す。
  nil の値はキーごと省略する。
  """
  def build_recommended_properties(source) do
    %{
      "requiredStatement" => build_required_statement(source),
      "rights" => Map.get(source, :license_uri),
      "provider" => build_provider(source),
      "summary" => build_summary(source),
      "navDate" => format_nav_date(Map.get(source, :survey_year)),
      "rendering" => build_rendering(source)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc "survey_year を ISO 8601 形式の navDate 文字列に変換する"
  def format_nav_date(nil), do: nil
  def format_nav_date(year) when is_integer(year), do: "#{year}-01-01T00:00:00Z"

  @doc "report_title と investigating_org から IIIF summary を生成する"
  def build_summary(source) do
    case {Map.get(source, :report_title), Map.get(source, :investigating_org)} do
      {nil, _} -> nil
      {title, nil} -> %{"ja" => [title], "en" => [title]}
      {title, org} -> %{"ja" => ["#{title}（#{org}）"], "en" => ["#{title} (#{org})"]}
    end
  end

  @doc "元 PDF への参照リンク（IIIF rendering）を生成する"
  def build_rendering(source) do
    case Map.get(source, :filename) do
      blank when blank in [nil, ""] ->
        nil

      filename ->
        url =
          "priv/static/uploads/pdfs/#{filename}"
          |> String.replace_prefix("priv/static", "")
          |> then(&(AlchemIiifWeb.Endpoint.url() <> &1))

        [
          %{
            "id" => url,
            "type" => "Text",
            "label" => %{"ja" => ["原本PDF"], "en" => ["Original PDF"]},
            "format" => "application/pdf"
          }
        ]
    end
  end

  @doc """
  ラベル/値ペアを IIIF metadata エントリ形式で構築する。
  value が nil の場合は nil を返す。
  """
  def label_value(_ja_label, _en_label, nil), do: nil

  def label_value(ja_label, en_label, value) do
    %{
      "label" => %{"ja" => [ja_label], "en" => [en_label]},
      "value" => format_value(en_label, value)
    }
  end

  defp format_value("Survey Year", value) when is_integer(value) do
    %{"ja" => ["#{value}年"], "en" => ["#{value}"]}
  end

  defp format_value(_label, value) do
    %{"ja" => [to_string(value)], "en" => [to_string(value)]}
  end
end
