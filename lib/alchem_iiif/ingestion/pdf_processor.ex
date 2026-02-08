defmodule AlchemIiif.Ingestion.PdfProcessor do
  @moduledoc """
  pdftoppm を使用して PDF ページを高解像度 PNG 画像に変換するモジュール。
  """

  @doc """
  PDFファイルの全ページを PNG に変換します。
  出力ディレクトリに page-001.png, page-002.png ... の形式で保存されます。

  ## 引数
    - pdf_path: PDF ファイルのパス
    - output_dir: 出力先ディレクトリ

  ## 戻り値
    - {:ok, %{page_count: integer, image_paths: [String.t()]}}
    - {:error, reason}
  """
  def convert_to_images(pdf_path, output_dir) do
    # 出力ディレクトリを作成
    File.mkdir_p!(output_dir)

    output_prefix = Path.join(output_dir, "page")

    # pdftoppm で PDF→PNG 変換 (300 DPI)
    case System.cmd(
           "pdftoppm",
           [
             "-png",
             "-r",
             "300",
             pdf_path,
             output_prefix
           ], stderr_to_stdout: true) do
      {_output, 0} ->
        # 生成された画像ファイルを取得
        image_paths =
          output_dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".png"))
          |> Enum.sort()
          |> Enum.map(&Path.join(output_dir, &1))

        {:ok, %{page_count: length(image_paths), image_paths: image_paths}}

      {error_output, _exit_code} ->
        {:error, "PDF変換に失敗しました: #{error_output}"}
    end
  end

  @doc """
  PDFのページ数を取得します。
  """
  def get_page_count(pdf_path) do
    case System.cmd("pdfinfo", [pdf_path], stderr_to_stdout: true) do
      {output, 0} ->
        case Regex.run(~r/Pages:\s+(\d+)/, output) do
          [_, count] -> {:ok, String.to_integer(count)}
          _ -> {:error, "ページ数を取得できませんでした"}
        end

      {_error, _} ->
        {:error, "PDF情報の取得に失敗しました"}
    end
  end
end
