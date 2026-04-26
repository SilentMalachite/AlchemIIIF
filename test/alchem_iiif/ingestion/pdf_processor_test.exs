defmodule AlchemIiif.Ingestion.PdfProcessorTest do
  use ExUnit.Case, async: false
  alias AlchemIiif.Ingestion.PdfProcessor
  import ExUnit.CaptureLog

  @tag :tmp_dir
  test "returns error when PDF file does not exist", %{tmp_dir: tmp_dir} do
    # 存在しないPDFパスを指定
    pdf_path = Path.join(tmp_dir, "non_existent.pdf")
    output_dir = Path.join(tmp_dir, "output")

    # ログをキャプチャして検証
    assert capture_log(fn ->
             assert {:error, message} = PdfProcessor.convert_to_images(pdf_path, output_dir)
             assert message =~ "PDF変換に失敗しました"

             # pdftoppm のエラーメッセージが含まれていることを期待（環境によるが）
           end) =~ "Command failed with exit code"
  end

  @tag :tmp_dir
  test "returns error when pdftoppm fails (e.g. invalid file)", %{tmp_dir: tmp_dir} do
    # 空のファイルを作成（PDFとして不正）
    pdf_path = Path.join(tmp_dir, "invalid.pdf")
    File.write!(pdf_path, "not a pdf")
    output_dir = Path.join(tmp_dir, "output")

    assert capture_log(fn ->
             assert {:error, message} = PdfProcessor.convert_to_images(pdf_path, output_dir)
             assert message =~ "PDF変換に失敗しました"
           end) =~ "Command failed with exit code"
  end

  @tag :tmp_dir
  test "returns error before conversion when page count exceeds the configured limit", %{
    tmp_dir: tmp_dir
  } do
    pdf_path = write_minimal_pdf(tmp_dir, "too_many_pages.pdf")
    output_dir = Path.join(tmp_dir, "output")

    assert capture_log(fn ->
             assert {:error, message} =
                      PdfProcessor.convert_to_images(pdf_path, output_dir, %{max_pages: 0})

             assert message =~ "ページ数の上限"
           end) =~ "exceeds page limit"
  end

  @tag :tmp_dir
  test "returns timeout error when pdftoppm exceeds the configured command timeout", %{
    tmp_dir: tmp_dir
  } do
    bin_dir = Path.join(tmp_dir, "bin")
    File.mkdir_p!(bin_dir)

    write_executable(Path.join(bin_dir, "pdfinfo"), """
    #!/bin/sh
    echo "Pages: 1"
    """)

    write_executable(Path.join(bin_dir, "pdftoppm"), """
    #!/bin/sh
    sleep 0.2
    exit 0
    """)

    original_path = System.get_env("PATH") || ""
    System.put_env("PATH", bin_dir <> ":" <> original_path)
    on_exit(fn -> System.put_env("PATH", original_path) end)

    pdf_path = write_minimal_pdf(tmp_dir, "timeout.pdf")
    output_dir = Path.join(tmp_dir, "timeout-output")

    assert capture_log(fn ->
             assert {:error, message} =
                      PdfProcessor.convert_to_images(pdf_path, output_dir, %{
                        command_timeout_ms: 10,
                        chunk_timeout_ms: 50
                      })

             assert message =~ "タイムアウト"
           end) =~ "timed out"
  end

  defp write_minimal_pdf(tmp_dir, filename) do
    path = Path.join(tmp_dir, filename)

    File.write!(path, """
    %PDF-1.0
    1 0 obj
    << /Type /Catalog /Pages 2 0 R >>
    endobj
    2 0 obj
    << /Type /Pages /Kids [3 0 R] /Count 1 >>
    endobj
    3 0 obj
    << /Type /Page /Parent 2 0 R /MediaBox [0 0 72 72] >>
    endobj
    xref
    0 4
    0000000000 65535 f
    0000000009 00000 n
    0000000058 00000 n
    0000000115 00000 n
    trailer
    << /Size 4 /Root 1 0 R >>
    startxref
    190
    %%EOF
    """)

    path
  end

  defp write_executable(path, contents) do
    File.write!(path, contents)
    File.chmod!(path, 0o755)
  end
end
