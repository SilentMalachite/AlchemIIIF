defmodule AlchemIiif.Ingestion.ImageProcessorTest do
  use ExUnit.Case, async: true

  alias AlchemIiif.Ingestion.ImageProcessor
  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  @moduletag :tmp_dir

  # 指定の単色 RGB 画像を作って path に書き出すユーティリティ。
  defp write_solid_rgb_png(path, width, height, [r, g, b]) do
    with {:ok, black} <- Operation.black(width, height, bands: 3),
         {:ok, colored} <- Operation.linear(black, [0.0, 0.0, 0.0], [r * 1.0, g * 1.0, b * 1.0]),
         {:ok, uchar} <- Operation.cast(colored, :VIPS_FORMAT_UCHAR),
         :ok <- Image.write_to_file(uchar, path) do
      :ok
    end
  end

  # path 画像の (x, y) 位置の RGB 値を取得。
  defp pixel_rgb(path, x, y) do
    {:ok, img} = Image.new_from_file(path)
    {:ok, [r, g, b | _]} = Operation.getpoint(img, x, y)
    {round(r), round(g), round(b)}
  end

  describe "crop_image/3 polygon fill color" do
    test "単色背景画像のポリゴンクロップは外側を背景と同等の色で埋める", %{tmp_dir: tmp} do
      # 100x100 の純緑 [0, 200, 0] 画像
      src = Path.join(tmp, "src.png")
      out = Path.join(tmp, "out.png")
      :ok = write_solid_rgb_png(src, 100, 100, [0, 200, 0])

      # ダイヤ型ポリゴン：bbox の四隅は確実にポリゴン外側になる
      points = [
        %{"x" => 50, "y" => 10},
        %{"x" => 90, "y" => 50},
        %{"x" => 50, "y" => 90},
        %{"x" => 10, "y" => 50}
      ]

      assert :ok = ImageProcessor.crop_image(src, %{"points" => points}, out)

      # 出力左上 (0, 0) は bbox 左上角 = ポリゴン外
      {r, g, b} = pixel_rgb(out, 0, 0)

      # 純白ではないことを最低限確認
      refute {r, g, b} == {255, 255, 255}, "ポリゴン外が純白で埋まっている: #{inspect({r, g, b})}"

      # 緑成分が強く、赤・青がほぼ無い（許容誤差込みで背景色に近い）
      assert g > 150, "G チャンネルが背景色と乖離: #{g}"
      assert r < 30, "R チャンネルが背景色と乖離: #{r}"
      assert b < 30, "B チャンネルが背景色と乖離: #{b}"
    end

    test "多角形内側のピクセルは元画像の値を保持する", %{tmp_dir: tmp} do
      src = Path.join(tmp, "src.png")
      out = Path.join(tmp, "out.png")
      :ok = write_solid_rgb_png(src, 100, 100, [0, 200, 0])

      points = [
        %{"x" => 10, "y" => 10},
        %{"x" => 90, "y" => 10},
        %{"x" => 90, "y" => 90},
        %{"x" => 10, "y" => 90}
      ]

      assert :ok = ImageProcessor.crop_image(src, %{"points" => points}, out)

      # 中央は polygon 内部 → 元画像のまま [0, 200, 0]
      {r, g, b} = pixel_rgb(out, 40, 40)
      assert g > 150
      assert r < 30
      assert b < 30
    end
  end

  describe "sample_polygon_border_color/2" do
    test "単色背景画像の bbox 外周をサンプルすると背景色に近い #RRGGBB を返す", %{tmp_dir: tmp} do
      src = Path.join(tmp, "src.png")
      :ok = write_solid_rgb_png(src, 100, 100, [0, 200, 0])

      points = [
        %{"x" => 50, "y" => 10},
        %{"x" => 90, "y" => 50},
        %{"x" => 50, "y" => 90},
        %{"x" => 10, "y" => 50}
      ]

      assert {:ok, "#" <> hex} = ImageProcessor.sample_polygon_border_color(src, points)
      assert byte_size(hex) == 6

      <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex
      r = String.to_integer(r, 16)
      g = String.to_integer(g, 16)
      b = String.to_integer(b, 16)

      assert g > 150, "G が背景色から乖離: #{g}"
      assert r < 30
      assert b < 30
    end

    test "存在しないファイルや points 不正なら {:error, _}", %{tmp_dir: tmp} do
      assert {:error, _} =
               ImageProcessor.sample_polygon_border_color(
                 Path.join(tmp, "missing.png"),
                 [%{"x" => 0, "y" => 0}, %{"x" => 1, "y" => 1}, %{"x" => 0, "y" => 1}]
               )
    end

    test "points が 3 点未満なら {:error, :insufficient_points}", %{tmp_dir: tmp} do
      src = Path.join(tmp, "src.png")
      :ok = write_solid_rgb_png(src, 10, 10, [0, 0, 0])

      assert {:error, :insufficient_points} =
               ImageProcessor.sample_polygon_border_color(src, [%{"x" => 0, "y" => 0}])
    end
  end

  describe "crop_image/3 矩形クロップ（既存挙動）" do
    test "矩形 geometry はマスクを介さず extract_area される", %{tmp_dir: tmp} do
      src = Path.join(tmp, "src.png")
      out = Path.join(tmp, "out.png")
      :ok = write_solid_rgb_png(src, 100, 100, [10, 20, 30])

      assert :ok =
               ImageProcessor.crop_image(
                 src,
                 %{"x" => 5, "y" => 5, "width" => 50, "height" => 50},
                 out
               )

      {:ok, img} = Image.new_from_file(out)
      assert Image.width(img) == 50
      assert Image.height(img) == 50
    end
  end
end
