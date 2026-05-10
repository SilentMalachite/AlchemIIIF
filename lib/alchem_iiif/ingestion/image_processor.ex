defmodule AlchemIiif.Ingestion.ImageProcessor do
  @moduledoc """
  vix (libvips) を使用して画像処理を行うモジュール。
  クロップ（矩形・ポリゴン）、PTIF生成、タイル切り出しを担当します。

  ## なぜこの設計か

  - **libvips (Vix) を採用**: ImageMagick と異なり、libvips はストリーミング処理で
    画像全体をメモリに展開しません。これにより、大容量の考古学資料画像（数十MB）
    でもメモリ使用量を低く抑えられます。BEAM VM との共存に適しています。
  - **PTIF (Pyramid TIFF)**: IIIF Image API に最適化されたフォーマットです。
    複数解像度のピラミッド構造を持つため、任意のズームレベルのタイルを
    高速に切り出せます。Deep Zoom や DZI と同等の性能を単一ファイルで実現します。
  """
  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  require Logger

  @doc """
  画像をクロップして保存します。
  ポリゴンデータ（points 配列）がある場合は SVG マスク戦略で多角形クロップを実行します。
  矩形データの場合は従来の extract_area を使用します。

  ## 引数
    - image_path: 元画像のパス
    - geometry: %{"points" => [...]} または %{"x" => x, "y" => y, "width" => w, "height" => h}
    - output_path: 出力先パス
  """
  def crop_image(image_path, %{"points" => points} = _geometry, output_path)
      when is_list(points) and length(points) >= 3 do
    crop_polygon(image_path, points, output_path)
  end

  def crop_image(image_path, %{"x" => x, "y" => y, "width" => w, "height" => h}, output_path) do
    with {:ok, image} <- Image.new_from_file(image_path),
         {:ok, cropped} <- Operation.extract_area(image, round(x), round(y), round(w), round(h)) do
      Image.write_to_file(cropped, output_path)
    end
  end

  @doc """
  画像をクロップし、バイナリとして返します（ファイル保存なし）。
  ダウンロード機能で使用します。
  ポリゴンデータの場合は白背景マスキング済み画像バイナリを返します。

  ## 引数
    - image_path: 元画像のパス
    - geometry: %{"points" => [...]} または %{"x" => x, "y" => y, "width" => w, "height" => h}

  ## 戻り値
    - {:ok, binary} クロップ済み画像バイナリ
    - {:error, reason}
  """
  def crop_to_binary(image_path, %{"points" => points} = _geometry)
      when is_list(points) and length(points) >= 3 do
    crop_polygon_to_binary(image_path, points)
  end

  def crop_to_binary(image_path, %{"x" => x, "y" => y, "width" => w, "height" => h}) do
    with {:ok, image} <- Image.new_from_file(image_path),
         {:ok, cropped} <- Operation.extract_area(image, round(x), round(y), round(w), round(h)) do
      Image.write_to_buffer(cropped, ".jpg")
    end
  end

  @doc """
  画像からピラミッド型TIFF (PTIF) を生成します。

  ## 引数
    - image_path: 元画像のパス
    - ptif_path: 出力 PTIF のパス
  """
  def generate_ptif(image_path, ptif_path) do
    with {:ok, image} <- Image.new_from_file(image_path) do
      # PTIF形式で保存 (ピラミッド型TIFF)
      # 白背景マスキングは crop_image 時に完了済みのため、そのまま保存
      Image.write_to_file(image, ptif_path <> "[tile,pyramid,compression=jpeg]")
    end
  end

  @doc """
  PTIF から指定されたリージョン/サイズのタイルを切り出します。

  ## 引数
    - ptif_path: PTIF ファイルのパス
    - region: {x, y, w, h} または :full
    - size: {width, height} または :max
    - rotation: 回転角度 (0, 90, 180, 270)
    - quality: "default" | "color" | "gray"
    - format: "jpg" | "png" | "webp"

  ## 戻り値
    - {:ok, binary} タイル画像のバイナリ
    - {:error, reason}
  """
  def extract_tile(ptif_path, region, size, rotation, _quality, format) do
    with {:ok, image} <- Image.new_from_file(ptif_path) do
      # リージョンの適用
      image = apply_region(image, region)

      # サイズの適用
      image = apply_size(image, size)

      # 回転の適用
      image = apply_rotation(image, rotation)

      # フォーマット指定でバッファに書き出し
      suffix = format_to_suffix(format)
      Image.write_to_buffer(image, suffix)
    end
  end

  @doc """
  画像の幅と高さを取得します。
  """
  def get_image_dimensions(image_path) do
    with {:ok, image} <- Image.new_from_file(image_path) do
      {:ok, %{width: Image.width(image), height: Image.height(image)}}
    end
  end

  @doc """
  ポリゴンの外周色を `#RRGGBB` 文字列で返します。

  ギャラリー等のクライアント側 SVG `<clipPath>` プレビューで、
  polygon 外を「白」ではなく「周囲色」で塗るために使用します。

  bounding box 外周の 8 点（四隅 + 各辺の中点）を `getpoint` で
  サンプリングし、各バンドの平均を 8bit RGB として返します。
  サンプリングが完全に失敗した場合は `#ffffff` を返します。

  ## 引数
    - image_path: 元画像のパス
    - points: ポリゴン頂点の配列 `[%{"x" => x, "y" => y} | %{x: x, y: y}, ...]`

  ## 戻り値
    - `{:ok, "#RRGGBB"}` 成功
    - `{:error, :insufficient_points}` 頂点が 3 点未満
    - `{:error, reason}` 画像読み込み失敗等
  """
  @spec sample_polygon_border_color(binary(), [map()]) ::
          {:ok, binary()} | {:error, term()}
  def sample_polygon_border_color(image_path, points)
      when is_binary(image_path) and is_list(points) do
    if length(points) < 3 do
      {:error, :insufficient_points}
    else
      do_sample_polygon_border_color(image_path, points)
    end
  end

  defp do_sample_polygon_border_color(image_path, points) do
    with {:ok, image} <- Image.new_from_file(image_path) do
      {min_x, min_y, bbox_w, bbox_h} = bounding_box(points)

      img_w = Image.width(image)
      img_h = Image.height(image)
      min_x = max(0, min(min_x, img_w - 1))
      min_y = max(0, min(min_y, img_h - 1))
      bbox_w = max(1, min(bbox_w, img_w - min_x))
      bbox_h = max(1, min(bbox_h, img_h - min_y))

      with {:ok, cropped} <- Operation.extract_area(image, min_x, min_y, bbox_w, bbox_h),
           {:ok, rgb} <- Operation.extract_band(cropped, 0, n: 3) do
        [r, g, b] = sample_border_color(rgb, Image.width(rgb), Image.height(rgb))
        {:ok, rgb_to_hex(r, g, b)}
      end
    end
  end

  defp rgb_to_hex(r, g, b) do
    "#" <>
      (r |> trunc() |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
      (g |> trunc() |> Integer.to_string(16) |> String.pad_leading(2, "0")) <>
      (b |> trunc() |> Integer.to_string(16) |> String.pad_leading(2, "0"))
  end

  # --- プライベート関数 ---

  # ポリゴンクロップ: ifthenelse 白背景合成戦略
  #
  # 1. バウンディングボックスを計算し、元画像からその領域を extract_area で切り出す
  # 2. SVG マスク（白ポリゴン/黒背景）を生成し、1バンドマスクを抽出
  # 3. 白背景RGB画像を作成
  # 4. ifthenelse でマスク白部分=元画像、マスク黒部分=白背景 に合成
  # 5. ポリゴン外が純白(255,255,255)の RGB 画像を保存
  defp crop_polygon(image_path, points, output_path) do
    with {:ok, masked} <- apply_polygon_mask(image_path, points) do
      # 白背景マスキング済みRGB画像として保存（透過不要）
      Image.write_to_file(masked, output_path)
    end
  end

  # ポリゴンクロップを JPEG バイナリとして返す（ダウンロード用）。
  # IIIF Image API の default format / download_controller の content_type:
  # "image/jpeg" / build_filename の拡張子(.jpg)と整合させる。
  # apply_polygon_mask は 3バンド RGB を返すのでアルファ欠落は発生しない。
  defp crop_polygon_to_binary(image_path, points) do
    with {:ok, masked} <- apply_polygon_mask(image_path, points) do
      Image.write_to_buffer(masked, ".jpg")
    end
  end

  # ポリゴンマスキングのコアロジック（ifthenelse 周囲色合成）
  #
  # JPEG はアルファチャンネルを持てないため、ポリゴン外を物理的に
  # 「周囲色」で塗りつぶし、3バンド RGB 画像として返す。
  # 周囲色は bounding box の外周 8 点（四隅 + 各辺中点）を getpoint で
  # サンプルし、その平均 RGB を使用する。bbox の外周はほとんどの場合
  # ポリゴンの外側であり、元画像の「ポリゴンの周囲」ピクセルに該当する。
  # サンプリングに失敗した場合は従来通り純白にフォールバックする。
  defp apply_polygon_mask(image_path, points) do
    with {:ok, image} <- Image.new_from_file(image_path) do
      # 1. バウンディングボックスを計算
      {min_x, min_y, bbox_w, bbox_h} = bounding_box(points)

      # 画像境界内にクランプ
      img_w = Image.width(image)
      img_h = Image.height(image)
      min_x = max(0, min(min_x, img_w - 1))
      min_y = max(0, min(min_y, img_h - 1))
      bbox_w = min(bbox_w, img_w - min_x)
      bbox_h = min(bbox_h, img_h - min_y)

      # 2. バウンディングボックスで矩形クロップ（メモリ節約）
      with {:ok, cropped_img} <- Operation.extract_area(image, min_x, min_y, bbox_w, bbox_h) do
        width = Image.width(cropped_img)
        height = Image.height(cropped_img)

        # 3. オフセット済みポリゴン座標で SVG マスクを生成（白ポリゴン/黒背景）
        offset_points =
          Enum.map(points, fn p ->
            x = round(p["x"] || p[:x] || 0) - min_x
            y = round(p["y"] || p[:y] || 0) - min_y
            "#{x},#{y}"
          end)
          |> Enum.join(" ")

        svg_mask = """
        <svg width="#{width}" height="#{height}">
          <rect width="100%" height="100%" fill="black" />
          <polygon points="#{offset_points}" fill="white" />
        </svg>
        """

        {:ok, {svg_img, _}} = Operation.svgload_buffer(svg_mask)
        # 1バンドマスクを抽出（白=255, 黒=0）
        {:ok, mask} = Operation.extract_band(svg_img, 0)

        # 4. クロップ画像を正確に 3バンド RGB に正規化（バンドミスマッチ防止）
        {:ok, rgb_img} = Operation.extract_band(cropped_img, 0, n: 3)

        # 5. 周囲色をサンプリングして塗りつぶし用の単色背景を作成
        fill_color = sample_border_color(rgb_img, width, height)
        {:ok, fill_bg} = build_solid_rgb(width, height, fill_color)

        # 6. マスクをガウシアンぼかしでフェザー化（境界の階段状段差を解消）。
        #    sigma は bbox 短辺の 3.0%、最低 1.5px。/gallery 側 SVG と同等。
        sigma = polygon_feather_sigma(width, height)
        {:ok, blurred_mask} = Operation.gaussblur(mask, sigma)

        Logger.info(
          "[ImageProcessor] Polygon crop (border-color fill #{inspect(fill_color)}, " <>
            "feather sigma=#{Float.round(sigma, 2)}): " <>
            "bbox=#{min_x},#{min_y},#{bbox_w}x#{bbox_h} points=#{length(points)}"
        )

        # 7. アルファブレンド合成:
        #    result = (mask/255) * rgb_img + (1 - mask/255) * fill_bg
        #    マスクの中間値（フェザー領域）が滑らかに RGB と背景色を補間する。
        {:ok, final_img} = alpha_blend(rgb_img, fill_bg, blurred_mask)

        {:ok, final_img}
      end
    end
  end

  # マスクを 0..1 のアルファとして使い rgb_img を fill_bg の上に合成する。
  defp alpha_blend(rgb_img, fill_bg, mask) do
    with {:ok, mask_norm} <- Operation.linear(mask, [1.0 / 255.0], [0.0]),
         {:ok, mask3} <- Operation.bandjoin([mask_norm, mask_norm, mask_norm]),
         {:ok, inv_mask3} <-
           Operation.linear(mask3, [-1.0, -1.0, -1.0], [1.0, 1.0, 1.0]),
         {:ok, rgb_float} <- Operation.cast(rgb_img, :VIPS_FORMAT_FLOAT),
         {:ok, bg_float} <- Operation.cast(fill_bg, :VIPS_FORMAT_FLOAT),
         {:ok, fg} <- Operation.multiply(rgb_float, mask3),
         {:ok, bg} <- Operation.multiply(bg_float, inv_mask3),
         {:ok, blend} <- Operation.add(fg, bg) do
      Operation.cast(blend, :VIPS_FORMAT_UCHAR)
    end
  end

  # ポリゴン外周のフェザー sigma（pixel）。bbox 短辺の 3.0%、最低 1.5px。
  defp polygon_feather_sigma(w, h) when is_integer(w) and is_integer(h) and w > 0 and h > 0 do
    max(1.5, min(w, h) * 0.03)
  end

  defp polygon_feather_sigma(_, _), do: 1.5

  # 3バンド RGB 画像の bbox 外周 8 点（四隅 + 各辺中点）の平均色を返す。
  # bbox 外周はほとんどの場合ポリゴンの外側なので、polygon の周囲色として妥当。
  # サンプルが取れなかった場合は純白にフォールバック。
  @fallback_color [255, 255, 255]
  defp sample_border_color(rgb_img, width, height)
       when width > 0 and height > 0 do
    sample_points = [
      {0, 0},
      {width - 1, 0},
      {0, height - 1},
      {width - 1, height - 1},
      {div(width, 2), 0},
      {div(width, 2), height - 1},
      {0, div(height, 2)},
      {width - 1, div(height, 2)}
    ]

    samples =
      Enum.flat_map(sample_points, fn {x, y} ->
        case Operation.getpoint(rgb_img, x, y) do
          {:ok, [_ | _] = pixel} -> [normalize_pixel(pixel)]
          _ -> []
        end
      end)

    case samples do
      [] ->
        @fallback_color

      _ ->
        n = length(samples) * 1.0

        samples
        |> Enum.zip()
        |> Enum.map(fn band_tuple ->
          band_tuple
          |> Tuple.to_list()
          |> Enum.sum()
          |> Kernel./(n)
          |> round()
          |> max(0)
          |> min(255)
        end)
    end
  end

  defp sample_border_color(_rgb_img, _w, _h), do: @fallback_color

  # getpoint の戻り値を [r, g, b] の 3 要素リストに正規化する。
  # 1バンド（グレースケール）の場合は同値を 3 回複製する。
  defp normalize_pixel([v]), do: [v, v, v]
  defp normalize_pixel([r, g, b | _]), do: [r, g, b]
  defp normalize_pixel(other), do: List.duplicate(hd(other ++ [255.0]), 3)

  # 指定 RGB の単色 3バンド uchar 画像を生成する。
  defp build_solid_rgb(width, height, [r, g, b]) do
    with {:ok, black} <- Operation.black(width, height, bands: 3),
         {:ok, colored} <-
           Operation.linear(black, [0.0, 0.0, 0.0], [r * 1.0, g * 1.0, b * 1.0]) do
      Operation.cast(colored, :VIPS_FORMAT_UCHAR)
    end
  end

  # ポリゴン頂点配列からバウンディングボックスを計算
  # 戻り値: {min_x, min_y, width, height}
  defp bounding_box(points) do
    xs = Enum.map(points, fn p -> round(p["x"] || p[:x] || 0) end)
    ys = Enum.map(points, fn p -> round(p["y"] || p[:y] || 0) end)

    min_x = Enum.min(xs)
    min_y = Enum.min(ys)
    max_x = Enum.max(xs)
    max_y = Enum.max(ys)

    {min_x, min_y, max_x - min_x, max_y - min_y}
  end

  defp apply_region(image, :full), do: image

  defp apply_region(image, {x, y, w, h}) do
    case Operation.extract_area(image, x, y, w, h) do
      {:ok, cropped} -> cropped
      _ -> image
    end
  end

  defp apply_size(image, :max), do: image

  defp apply_size(image, {width, height}) do
    case Operation.thumbnail_image(image, width, height: height) do
      {:ok, resized} -> resized
      _ -> image
    end
  end

  defp apply_rotation(image, 0), do: image

  defp apply_rotation(image, degrees) when degrees in [90, 180, 270] do
    angle =
      case degrees do
        90 -> :VIPS_ANGLE_D90
        180 -> :VIPS_ANGLE_D180
        270 -> :VIPS_ANGLE_D270
      end

    case Operation.rot(image, angle) do
      {:ok, rotated} -> rotated
      _ -> image
    end
  end

  defp apply_rotation(image, _), do: image
  defp format_to_suffix("jpg"), do: ".jpg"
  defp format_to_suffix("jpeg"), do: ".jpg"
  defp format_to_suffix("png"), do: ".png"
  defp format_to_suffix("webp"), do: ".webp"
  defp format_to_suffix(_), do: ".jpg"
end
