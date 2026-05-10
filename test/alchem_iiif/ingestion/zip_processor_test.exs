defmodule AlchemIiif.Ingestion.ZipProcessorTest do
  use ExUnit.Case, async: true

  alias AlchemIiif.Ingestion.ZipProcessor

  # PNG マジックバイト + 任意の追加バイトで「PNG として有効に見える」最小バイト列を返す。
  # ZipProcessor のマジックバイト検証は先頭 8 バイトのみを見るので、後段は任意で良い。
  defp png_bytes(payload \\ <<>>) do
    <<137, 80, 78, 71, 13, 10, 26, 10>> <> payload
  end

  defp setup_dirs(test_name) do
    base =
      Path.join(
        System.tmp_dir!(),
        "zp_test_#{test_name}_#{System.unique_integer([:positive])}"
      )

    src = Path.join(base, "src")
    out = Path.join(base, "out")
    File.mkdir_p!(src)
    File.mkdir_p!(out)
    on_exit_remove(base)
    {src, out}
  end

  defp on_exit_remove(path) do
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(path) end)
  end

  defp build_zip(zip_path, files) when is_list(files) do
    entries =
      Enum.map(files, fn {name, bin} ->
        {String.to_charlist(name), bin}
      end)

    zip_charlist = String.to_charlist(zip_path)
    {:ok, _} = :zip.create(zip_charlist, entries)
    zip_path
  end

  describe "extract_pngs/3 normal cases" do
    test "フラットな ZIP に PNG 3 枚 → 3 ページとして抽出される" do
      {src, out} = setup_dirs(~c"flat3")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"a.png", png_bytes()},
          {"b.png", png_bytes()},
          {"c.png", png_bytes()}
        ])

      assert {:ok, %{page_count: 3, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip, out)

      assert length(paths) == 3
      assert Enum.all?(paths, &File.exists?/1)
      assert Enum.all?(paths, &String.starts_with?(Path.basename(&1), "page-"))
      assert Enum.all?(paths, &String.ends_with?(Path.basename(&1), ".png"))
    end

    test "サブディレクトリ配下の PNG も再帰的に集める" do
      {src, out} = setup_dirs("nested")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"top.png", png_bytes()},
          {"sub/inner.png", png_bytes()},
          {"sub/deeper/leaf.png", png_bytes()}
        ])

      assert {:ok, %{page_count: 3, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip, out)

      assert length(paths) == 3
    end

    test "p1.png, p2.png, p10.png を自然順で並べて連番を振る" do
      {src, out} = setup_dirs("natural")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"p10.png", png_bytes(<<10>>)},
          {"p2.png", png_bytes(<<2>>)},
          {"p1.png", png_bytes(<<1>>)}
        ])

      assert {:ok, %{page_count: 3, image_paths: [first, second, third]}} =
               ZipProcessor.extract_pngs(zip, out)

      assert Path.basename(first) =~ ~r/^page-001-/
      assert Path.basename(second) =~ ~r/^page-002-/
      assert Path.basename(third) =~ ~r/^page-003-/

      # 内容で順序を確認（先頭 9 バイト目に元 payload の識別バイトが入っている）
      assert <<137, 80, 78, 71, 13, 10, 26, 10, 1>> = File.read!(first)
      assert <<137, 80, 78, 71, 13, 10, 26, 10, 2>> = File.read!(second)
      assert <<137, 80, 78, 71, 13, 10, 26, 10, 10>> = File.read!(third)
    end
  end
end
