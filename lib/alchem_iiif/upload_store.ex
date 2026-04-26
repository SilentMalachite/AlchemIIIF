defmodule AlchemIiif.UploadStore do
  @moduledoc """
  アップロード済みファイルの保存先と解決を一元管理する。

  新規ファイルは静的配信対象外の `priv/uploads` に保存する。既存データとの
  互換性のため、旧 `priv/static/uploads` 配下はコントローラー経由の読み取りと
  削除対象としてだけ扱う。
  """

  @default_root Path.join(["priv", "uploads"])
  @legacy_root Path.join(["priv", "static", "uploads"])

  def root do
    :alchem_iiif
    |> Application.get_env(:upload_root, System.get_env("ALCHEM_UPLOAD_ROOT") || @default_root)
    |> Path.expand()
  end

  def pdfs_dir, do: Path.join(root(), "pdfs")
  def pages_dir(pdf_source_id), do: Path.join([root(), "pages", to_string(pdf_source_id)])

  def legacy_root, do: Path.expand(@legacy_root)
  def legacy_pdfs_dir, do: Path.join(legacy_root(), "pdfs")

  def legacy_pages_dir(pdf_source_id),
    do: Path.join([legacy_root(), "pages", to_string(pdf_source_id)])

  def pdf_path(filename), do: Path.join(pdfs_dir(), filename)
  def page_path(pdf_source_id, filename), do: Path.join(pages_dir(pdf_source_id), filename)

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

  def existing_pages_dir(pdf_source_id) do
    pdf_source_id
    |> pages_dir_candidates()
    |> Enum.find(&File.dir?/1)
    |> case do
      nil -> {:error, :not_found}
      dir -> {:ok, dir}
    end
  end

  def existing_page_path(pdf_source_id, filename) do
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

  def pages_dirs(pdf_source_id) do
    pdf_source_id
    |> pages_dir_candidates()
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

  defp pages_dir_candidates(pdf_source_id) do
    [
      "priv/uploads/pages/#{pdf_source_id}",
      "priv/static/uploads/pages/#{pdf_source_id}"
    ]
    |> path_candidates()
  end

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
