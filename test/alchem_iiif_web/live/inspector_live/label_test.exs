defmodule AlchemIiifWeb.InspectorLive.LabelTest do
  @moduledoc """
  Label LiveView のテスト。

  ウィザード Step 4 のラベリング画面をテストします。
  マウント時の初期表示、メタデータ入力、Auto-Save、
  Undo 機能、ナビゲーションを検証します。
  """
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.Factory

  describe "マウント" do
    test "初期状態でステップ4が表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          caption: "テスト土器第3図",
          label: "fig-003",
          site: "テスト遺跡",
          period: "縄文時代",
          artifact_type: "土器"
        })

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      # ステップ4（ラベリング）が表示される
      assert html =~ "ラベリング"
      assert html =~ "いまここ"
      assert html =~ "4 / 5"
    end

    test "既存のメタデータが入力フィールドに表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          caption: "テスト土器第3図",
          label: "fig-003",
          site: "テスト遺跡",
          period: "縄文時代",
          artifact_type: "土器"
        })

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "テスト土器第3図"
      assert html =~ "fig-003"
      assert html =~ "テスト遺跡"
      assert html =~ "縄文時代"
      assert html =~ "土器"
    end

    test "メタデータが空の場合でも正常に表示される", %{conn: conn} do
      image =
        insert_extracted_image(%{
          caption: nil,
          label: nil,
          site: nil,
          period: nil,
          artifact_type: nil
        })

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      # フォームが表示される
      assert html =~ "図版の情報を入力してください"
      assert html =~ "キャプション"
    end
  end

  describe "ナビゲーション" do
    test "戻るリンクがクロップ画面を指す", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "← 戻る"
      assert html =~ "/lab/crop/#{image.id}"
    end

    test "保存して次の図版へボタンが表示される", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "保存して次の図版へ"
    end

    test "保存して終了ボタンが表示される", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, _view, html} = live(conn, ~p"/lab/label/#{image.id}")

      assert html =~ "保存して終了"
    end

    test "save continue で Browse 画面に遷移する", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{image.id}")

      assert {:error, {:live_redirect, %{to: path}}} =
               view |> element(".btn-save-continue") |> render_click()

      assert path =~ "/lab/browse/#{image.pdf_source_id}"
    end

    test "save finish で Lab ダッシュボードに遷移する", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{image.id}")

      assert {:error, {:live_redirect, %{to: "/lab"}}} =
               view |> element(".btn-save-finish") |> render_click()
    end
  end

  describe "Undo 機能" do
    test "Undo スタックが空の場合ボタンが無効", %{conn: conn} do
      image = insert_extracted_image()

      {:ok, view, _html} = live(conn, ~p"/lab/label/#{image.id}")

      assert has_element?(view, "button.btn-undo[disabled]")
    end
  end
end
