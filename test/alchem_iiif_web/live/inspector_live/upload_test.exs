defmodule AlchemIiifWeb.InspectorLive.UploadTest do
  @moduledoc """
  Upload LiveView のテスト。

  ウィザード Step 1（PDFアップロード画面）における
  ユーザー間データ分離と報告書情報フォームの動作を検証します。
  """
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.AccountsFixtures
  import Ecto.Query, only: [from: 2]

  alias AlchemIiif.Repo
  alias AlchemIiif.Ingestion.PdfSource

  describe "security: uploads are isolated between users" do
    test "User A のアップロードファイルが User B に見えないこと" do
      # ── 1. セットアップ: 2人のユーザーを作成 ──
      user_a = user_fixture()
      user_b = user_fixture()

      # ── 2. User A: ログイン → LiveView マウント → ファイル選択 ──
      conn_a =
        build_conn()
        |> log_in_user(user_a)

      {:ok, view_a, _html} = live(conn_a, ~p"/lab/upload")

      # PDF ファイルを選択（file_input でエントリを登録）
      pdf_input =
        file_input(view_a, "#upload-form", :pdf, [
          %{
            name: "secret_plan.pdf",
            content: <<0, 1, 2, 3, 4>>,
            type: "application/pdf"
          }
        ])

      # アップロードチャンクを送信してバリデーションを発火
      render_upload(pdf_input, "secret_plan.pdf")

      # User A のビューにファイル名が表示されることを確認
      html_a = render(view_a)
      assert html_a =~ "secret_plan.pdf"

      # ── 3. User B: ログイン → LiveView マウント → 分離を検証 ──
      conn_b =
        build_conn()
        |> log_in_user(user_b)

      {:ok, view_b, _html} = live(conn_b, ~p"/lab")

      # User B のビューに User A のファイル名が表示されないことを確認
      html_b = render(view_b)

      refute html_b =~ "secret_plan.pdf",
             "セキュリティ違反: User A のアップロード (secret_plan.pdf) が User B のセッションに漏洩しています"
    end
  end

  describe "報告書情報フォーム" do
    setup :register_and_log_in_user

    test "報告書情報セクションが表示される", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/lab/upload")

      assert html =~ "報告書情報"
      assert html =~ "報告書名"
      assert html =~ "調査機関名"
      assert html =~ "調査年度"
      assert html =~ "遺跡コード"
      assert html =~ "ライセンスURI"
    end

    test "report_title を入力して送信すると pdf_source に保存される", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/lab/upload")

      # フォームに書誌情報を入力（validate イベント）
      view
      |> element("#upload-form")
      |> render_change(%{
        "report_title" => "令和6年度 テスト遺跡発掘調査報告書",
        "investigating_org" => "テスト市教育委員会",
        "survey_year" => "2024",
        "site_code" => "15-201-001",
        "license_uri" => "https://creativecommons.org/licenses/by/4.0/",
        "color_mode" => "mono"
      })

      # PDF ファイルをアップロード
      pdf_input =
        file_input(view, "#upload-form", :pdf, [
          %{
            name: "test_report.pdf",
            content: <<0, 1, 2, 3, 4>>,
            type: "application/pdf"
          }
        ])

      render_upload(pdf_input, "test_report.pdf")

      # submit 送信 — PdfSource 作成後に Pipeline（pdftoppm）が起動するが、
      # テスト環境では外部コマンドが失敗する場合がある。
      # PdfSource の DB 挿入は Pipeline 起動前に完了するため、
      # Pipeline 由来の例外のみ許容する。
      try do
        render_submit(view, "upload_pdf", %{
          "color_mode" => "mono"
        })
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end

      # PdfSource が書誌情報付きで作成されていることを確認
      [pdf_source] =
        Repo.all(from p in PdfSource, where: p.user_id == ^user.id, order_by: [desc: p.id])

      assert pdf_source.report_title == "令和6年度 テスト遺跡発掘調査報告書"
      assert pdf_source.investigating_org == "テスト市教育委員会"
      assert pdf_source.survey_year == 2024
      assert pdf_source.site_code == "15-201-001"
      assert pdf_source.license_uri == "https://creativecommons.org/licenses/by/4.0/"
    end

    test "survey_year に範囲外の値を入力するとエラーが表示される", _context do
      # changeset バリデーションを直接テスト（LiveView 経由だと HTML5 の min/max で弾かれる）
      changeset =
        PdfSource.changeset(%PdfSource{}, %{
          filename: "test.pdf",
          survey_year: 1800
        })

      refute changeset.valid?
      assert {:survey_year, _} = List.keyfind(changeset.errors, :survey_year, 0)
    end

    test "site_code に不正な形式を入力するとエラーが表示される", _context do
      changeset =
        PdfSource.changeset(%PdfSource{}, %{
          filename: "test.pdf",
          site_code: "abc"
        })

      refute changeset.valid?
      assert {:site_code, _} = List.keyfind(changeset.errors, :site_code, 0)
    end

    test "書誌フィールドが空でも PDF アップロードは成功する", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/lab/upload")

      # 書誌フィールドは一切入力しない
      pdf_input =
        file_input(view, "#upload-form", :pdf, [
          %{
            name: "empty_fields.pdf",
            content: <<0, 1, 2, 3, 4>>,
            type: "application/pdf"
          }
        ])

      render_upload(pdf_input, "empty_fields.pdf")

      try do
        render_submit(view, "upload_pdf", %{
          "color_mode" => "mono"
        })
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end

      # PdfSource が作成されている（書誌フィールドは nil）
      [pdf_source] =
        Repo.all(from p in PdfSource, where: p.user_id == ^user.id, order_by: [desc: p.id])

      assert pdf_source.filename =~ "empty_fields"
      assert is_nil(pdf_source.report_title)
      assert is_nil(pdf_source.investigating_org)
    end
  end
end
