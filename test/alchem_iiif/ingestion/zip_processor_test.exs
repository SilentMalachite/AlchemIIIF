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

  describe "extract_pngs/3 security guards" do
    test "Zip Slip エントリ（../etc/passwd.png）は採用しない" do
      {src, out} = setup_dirs("slip")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"../etc/passwd.png", png_bytes()},
          {"ok.png", png_bytes()}
        ])

      assert {:ok, %{page_count: 1, image_paths: [path]}} =
               ZipProcessor.extract_pngs(zip, out)

      refute File.exists?(Path.join([out, "..", "etc", "passwd.png"]))
      assert String.starts_with?(path, out)
    end

    test "絶対パスのエントリ（/tmp/foo.png）は out の外に展開されない" do
      {src, out} = setup_dirs("abs")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"/tmp/abs.png", png_bytes()},
          {"ok.png", png_bytes()}
        ])

      # Erlang の :zip.create/3 は絶対パスを正規化して相対パスに変換するため、
      # エントリは out 内に留まる。どのパスも out の外に存在しないことを確認する。
      assert {:ok, %{image_paths: paths}} = ZipProcessor.extract_pngs(zip, out)
      assert Enum.all?(paths, &String.starts_with?(&1, out))
      refute File.exists?("/tmp/abs.png")
    end

    test "PNG マジックバイトを持たない .png は除外され、すべて偽装なら error" do
      {src, out} = setup_dirs("magic")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"fake.png", "not a png file"}
        ])

      assert {:error, :no_valid_png} = ZipProcessor.extract_pngs(zip, out)
    end

    test "PNG エントリが 0 件の ZIP は no_png_entries エラー" do
      {src, out} = setup_dirs("empty")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"readme.txt", "hello"}
        ])

      assert {:error, :no_png_entries} = ZipProcessor.extract_pngs(zip, out)
    end

    test "PNG エントリ数が opts.max_pages を超えたら too_many_pages エラー" do
      {src, out} = setup_dirs("too_many")
      files = for i <- 1..5, do: {"p#{i}.png", png_bytes()}
      zip = build_zip(Path.join(src, "in.zip"), files)

      assert {:error, {:too_many_pages, 5, 3}} =
               ZipProcessor.extract_pngs(zip, out, %{max_pages: 3})
    end

    test "宣言サイズ合計が opts.max_extracted_bytes を超えたら拒否（unzip しない）" do
      {src, out} = setup_dirs("too_big")
      bin = png_bytes(:binary.copy(<<0>>, 1024))
      files = for i <- 1..5, do: {"p#{i}.png", bin}
      zip = build_zip(Path.join(src, "in.zip"), files)

      assert {:error, :extracted_size_exceeds_limit} =
               ZipProcessor.extract_pngs(zip, out, %{max_extracted_bytes: 100})

      # output_dir に何も書き出されていないこと
      assert File.ls!(out) == []
    end
  end

  describe "extract_pngs/3 macOS resource fork" do
    test "__MACOSX/ 配下の .png は候補にカウントされず無視される" do
      {src, out} = setup_dirs("macosx_dir")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"a.png", png_bytes()},
          {"__MACOSX/._a.png", "AppleDouble metadata"},
          {"__MACOSX/._b.png", "AppleDouble metadata"}
        ])

      assert {:ok, %{page_count: 1, image_paths: [path]}} =
               ZipProcessor.extract_pngs(zip, out)

      assert File.exists?(path)
    end

    test "._ で始まる AppleDouble エントリ（フラット配置）は候補から外す" do
      {src, out} = setup_dirs("appledouble_flat")

      zip =
        build_zip(Path.join(src, "in.zip"), [
          {"a.png", png_bytes()},
          {"b.png", png_bytes()},
          {"._a.png", "AppleDouble metadata"},
          {"._b.png", "AppleDouble metadata"}
        ])

      assert {:ok, %{page_count: 2, image_paths: paths}} =
               ZipProcessor.extract_pngs(zip, out)

      assert length(paths) == 2
    end

    test "max_pages 直前の境界：resource fork 除外で本数が上限内に収まれば成功する" do
      {src, out} = setup_dirs("macosx_boundary")

      # 5 枚の PNG を Mac で zip した想定：本物 5 + AppleDouble 3 = 8 エントリ
      files =
        for i <- 1..5, do: {"p#{i}.png", png_bytes()}

      forks =
        for i <- 1..3, do: {"__MACOSX/._p#{i}.png", "AppleDouble metadata"}

      zip = build_zip(Path.join(src, "in.zip"), files ++ forks)

      assert {:ok, %{page_count: 5}} =
               ZipProcessor.extract_pngs(zip, out, %{max_pages: 5})
    end
  end
end
