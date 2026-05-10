defmodule AlchemIiif.UploadStore do
  @moduledoc """
  アップロード済みファイルの保存先と解決を一元管理する。

  新規ファイルは静的配信対象外の `priv/uploads` に保存する。既存データとの
  互換性のため、旧 `priv/static/uploads` 配下はコントローラー経由の読み取りと
  削除対象としてだけ扱う。

  ## ページ画像のパス解決

  ページ画像の保存先は `pages/{storage_key}/` を基本とする。
  PdfSource ごとに永続的に異なる識別子（UUID）を持たせることで、
  `mix ecto.reset` 等で ID が再採番されても旧データと混在しないようにする。

  既存データ互換のため、旧形式 `pages/{id}/` も読み取り時のフォールバック
  候補として残す（マイグレーションで storage_key を `to_string(id)` で
  バックフィルしているため、通常はそもそも同じパスを指す）。
  """

  alias AlchemIiif.Ingestion.PdfSource

  @default_root Path.join(["priv", "uploads"])
  @legacy_root Path.join(["priv", "static", "uploads"])

  def root do
    :alchem_iiif
    |> Application.get_env(:upload_root, System.get_env("ALCHEM_UPLOAD_ROOT") || @default_root)
    |> Path.expand()
  end

  def pdfs_dir, do: Path.join(root(), "pdfs")

  @doc """
  新形式のページ保存ディレクトリ。

  PdfSource 構造体（または `{storage_key, id}` のタプル）を受け取り、
  `pages/{storage_key}/` を返す。テストや移行期の互換目的で
  storage_key が文字列単体で渡された場合はそのまま採用する。
  """
  def pages_dir(%PdfSource{storage_key: key}) when is_binary(key) and key != "" do
    pages_dir(key)
  end

  def pages_dir(key) when is_binary(key) and key != "" do
    Path.join([root(), "pages", key])
  end

  def pages_dir(pdf_source_id) when is_integer(pdf_source_id) do
    Path.join([root(), "pages", to_string(pdf_source_id)])
  end

  def legacy_root, do: Path.expand(@legacy_root)
  def legacy_pdfs_dir, do: Path.join(legacy_root(), "pdfs")

  def legacy_pages_dir(pdf_source_id),
    do: Path.join([legacy_root(), "pages", to_string(pdf_source_id)])

  def pdf_path(filename), do: Path.join(pdfs_dir(), filename)

  def page_path(%PdfSource{} = source, filename), do: Path.join(pages_dir(source), filename)

  def page_path(key_or_id, filename) when is_binary(key_or_id) or is_integer(key_or_id) do
    Path.join(pages_dir(key_or_id), filename)
  end

  def safe_filename?(filename) when is_binary(filename) do
    filename not in ["", ".", ".."] and Path.basename(filename) == filename
  end

  def safe_filename?(_), do: false

  def existing_pdf_path(filename) do
    if safe_filename?(filename) do
      ["priv/uploads/pdfs/#{filename}", "priv/static/uploads/pdfs/#{filename}"]
      |> existing_path()
    else
      {:error, :invalid_filename}
    end
  end

  @doc """
  実在するページディレクトリを返す。

  `PdfSource` 構造体を渡した場合は `storage_key` を最優先候補とし、
  ID 直書きの旧パスをフォールバックとして探す。
  数値 ID 単体で渡された場合は旧形式互換でのみ探索する。
  """
  def existing_pages_dir(%PdfSource{} = source) do
    source
    |> pages_dir_candidates()
    |> Enum.find(&File.dir?/1)
    |> case do
      nil -> {:error, :not_found}
      dir -> {:ok, dir}
    end
  end

  def existing_pages_dir(pdf_source_id) when is_integer(pdf_source_id) do
    pdf_source_id
    |> legacy_pages_dir_candidates()
    |> Enum.find(&File.dir?/1)
    |> case do
      nil -> {:error, :not_found}
      dir -> {:ok, dir}
    end
  end

  def existing_page_path(%PdfSource{} = source, filename) do
    if safe_filename?(filename) do
      source
      |> page_path_candidates(filename)
      |> existing_path()
    else
      {:error, :invalid_filename}
    end
  end

  def existing_page_path(pdf_source_id, filename) when is_integer(pdf_source_id) do
    if safe_filename?(filename) do
      [
        "priv/uploads/pages/#{pdf_source_id}/#{filename}",
        "priv/static/uploads/pages/#{pdf_source_id}/#{filename}"
      ]
      |> existing_path()
    else
      {:error, :invalid_filename}
    end
  end

  def pdf_paths(filename) do
    if safe_filename?(filename) do
      ["priv/uploads/pdfs/#{filename}", "priv/static/uploads/pdfs/#{filename}"]
      |> path_candidates()
      |> Enum.uniq()
    else
      []
    end
  end

  @doc """
  hard_delete 等で物理削除する際の候補ディレクトリ群を返す。

  storage_key ベースの新パスと、互換のため ID 直書きの旧パス、さらに
  `priv/static/uploads` 配下の legacy パスをすべて列挙する。
  """
  def pages_dirs(%PdfSource{} = source) do
    source
    |> pages_dir_candidates()
    |> Enum.uniq()
  end

  def pages_dirs(pdf_source_id) when is_integer(pdf_source_id) do
    pdf_source_id
    |> legacy_pages_dir_candidates()
    |> Enum.uniq()
  end

  def resolve_path(path) when is_binary(path) do
    path
    |> List.wrap()
    |> existing_path()
  end

  def resolve_path(_), do: {:error, :invalid_path}

  defp existing_path(paths) do
    paths
    |> path_candidates()
    |> Enum.find_value(fn path ->
      if allowed_path?(path) and File.exists?(path), do: {:ok, path}, else: nil
    end)
    |> case do
      nil -> {:error, :not_found}
      result -> result
    end
  end

  defp path_candidates(paths) do
    paths
    |> List.wrap()
    |> Enum.flat_map(&single_path_candidates/1)
    |> Enum.map(&Path.expand/1)
  end

  defp single_path_candidates(path) do
    cond do
      Path.type(path) == :absolute ->
        [path]

      String.starts_with?(path, "priv/uploads/") ->
        [path, Application.app_dir(:alchem_iiif, path)]

      String.starts_with?(path, "priv/static/uploads/") ->
        [path, Application.app_dir(:alchem_iiif, path)]

      true ->
        [Path.join(root(), path)]
    end
  end

  defp pages_dir_candidates(%PdfSource{storage_key: key, id: id}) do
    paths_for_key(key) ++ paths_for_key(id_string(id))
  end

  defp legacy_pages_dir_candidates(pdf_source_id) when is_integer(pdf_source_id) do
    paths_for_key(id_string(pdf_source_id))
  end

  defp paths_for_key(nil), do: []
  defp paths_for_key(""), do: []

  defp paths_for_key(key) when is_binary(key) do
    [
      Path.join([root(), "pages", key]),
      "priv/uploads/pages/#{key}",
      "priv/static/uploads/pages/#{key}"
    ]
    |> path_candidates()
  end

  defp page_path_candidates(%PdfSource{storage_key: key, id: id}, filename) do
    paths_for_page(key, filename) ++ paths_for_page(id_string(id), filename)
  end

  defp paths_for_page(nil, _filename), do: []
  defp paths_for_page("", _filename), do: []

  defp paths_for_page(key, filename) when is_binary(key) do
    [
      Path.join([root(), "pages", key, filename]),
      "priv/uploads/pages/#{key}/#{filename}",
      "priv/static/uploads/pages/#{key}/#{filename}"
    ]
  end

  defp id_string(id) when is_integer(id), do: Integer.to_string(id)
  defp id_string(_), do: nil

  defp allowed_path?(path) do
    Enum.any?(allowed_roots(), &within_root?(path, &1))
  end

  defp allowed_roots do
    [
      root(),
      legacy_root(),
      Application.app_dir(:alchem_iiif, "priv/uploads"),
      Application.app_dir(:alchem_iiif, "priv/static/uploads")
    ]
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp within_root?(path, root) do
    path == root or String.starts_with?(path, root <> "/")
  end
end
