defmodule AlchemIiif.UploadStoreTest do
  use ExUnit.Case, async: false

  alias AlchemIiif.Ingestion.PdfSource
  alias AlchemIiif.UploadStore

  setup do
    original_root = Application.get_env(:alchem_iiif, :upload_root)

    tmp_root =
      Path.join(
        System.tmp_dir!(),
        "upload_store_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_root)
    Application.put_env(:alchem_iiif, :upload_root, tmp_root)

    on_exit(fn ->
      if is_nil(original_root) do
        Application.delete_env(:alchem_iiif, :upload_root)
      else
        Application.put_env(:alchem_iiif, :upload_root, original_root)
      end

      File.rm_rf!(tmp_root)
    end)

    {:ok, tmp_root: tmp_root}
  end

  describe "pages_dir/1" do
    test "PdfSource 構造体は storage_key 配下のパスを返す", %{tmp_root: root} do
      source = %PdfSource{id: 1, storage_key: "abc-123"}

      assert UploadStore.pages_dir(source) ==
               Path.expand(Path.join([root, "pages", "abc-123"]))
    end

    test "ID 違いでも storage_key が異なれば別パスになる", %{tmp_root: root} do
      a = %PdfSource{id: 1, storage_key: "key-a"}
      b = %PdfSource{id: 1, storage_key: "key-b"}

      refute UploadStore.pages_dir(a) == UploadStore.pages_dir(b)
      assert UploadStore.pages_dir(a) =~ Path.expand(root)
    end

    test "数値 ID 単体を渡した場合は ID 直書きパス（互換）を返す", %{tmp_root: root} do
      assert UploadStore.pages_dir(42) ==
               Path.expand(Path.join([root, "pages", "42"]))
    end
  end

  describe "existing_pages_dir/1" do
    test "storage_key パスが優先され、ID パスにファイルがあっても採用しない", %{tmp_root: root} do
      source = %PdfSource{id: 5, storage_key: "uuid-five"}

      storage_dir = Path.join([root, "pages", "uuid-five"])
      legacy_dir = Path.join([root, "pages", "5"])
      File.mkdir_p!(storage_dir)
      File.mkdir_p!(legacy_dir)

      assert {:ok, found} = UploadStore.existing_pages_dir(source)
      assert found == Path.expand(storage_dir)
    end

    test "storage_key パスが無ければ ID 直書きパスにフォールバックする", %{tmp_root: root} do
      source = %PdfSource{id: 9, storage_key: "uuid-nine"}
      legacy_dir = Path.join([root, "pages", "9"])
      File.mkdir_p!(legacy_dir)

      assert {:ok, found} = UploadStore.existing_pages_dir(source)
      assert found == Path.expand(legacy_dir)
    end
  end

  describe "existing_page_path/2" do
    test "storage_key 配下のファイルを優先して返す", %{tmp_root: root} do
      source = %PdfSource{id: 7, storage_key: "uuid-seven"}

      storage_file = Path.join([root, "pages", "uuid-seven", "page-001-9999.png"])
      legacy_file = Path.join([root, "pages", "7", "page-001-9999.png"])

      File.mkdir_p!(Path.dirname(storage_file))
      File.mkdir_p!(Path.dirname(legacy_file))
      File.write!(storage_file, "storage")
      File.write!(legacy_file, "legacy")

      assert {:ok, path} = UploadStore.existing_page_path(source, "page-001-9999.png")
      assert File.read!(path) == "storage"
    end

    test "ファイル名が安全でない場合は :invalid_filename を返す" do
      source = %PdfSource{id: 1, storage_key: "k"}

      assert {:error, :invalid_filename} =
               UploadStore.existing_page_path(source, "../etc/passwd")
    end
  end

  describe "ecto.reset 後のシナリオ再現" do
    test "ID が再採番されても新ソースの storage_key が違えば旧ファイルと混在しない", %{tmp_root: root} do
      # 古いソース（同じ ID = 1）の残骸ファイルを直書き
      legacy_dir = Path.join([root, "pages", "1"])
      File.mkdir_p!(legacy_dir)
      File.write!(Path.join(legacy_dir, "page-001-old.png"), "old")

      # ecto.reset 後に同じ ID = 1 で新規ソースが作られた想定
      new_source = %PdfSource{id: 1, storage_key: "uuid-new"}
      new_dir = UploadStore.pages_dir(new_source)
      File.mkdir_p!(new_dir)
      File.write!(Path.join(new_dir, "page-001-new.png"), "new")

      assert {:ok, found} = UploadStore.existing_pages_dir(new_source)
      assert found == Path.expand(new_dir)

      # 旧ファイルは混入しない
      entries = File.ls!(found)
      assert "page-001-new.png" in entries
      refute "page-001-old.png" in entries
    end
  end
end
