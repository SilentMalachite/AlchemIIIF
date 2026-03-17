defmodule AlchemIiifWeb.InspectorLive.UploadTest do
  @moduledoc """
  Upload LiveView のテスト。

  ウィザード Step 1（PDFアップロード画面）における
  ユーザー間データ分離と非同期通知のエラーハンドリングを検証します。
  """
  use AlchemIiifWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import AlchemIiif.AccountsFixtures

  alias AlchemIiif.Ingestion

  setup :register_and_log_in_user

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

  describe "非同期通知" do
    test "成功通知で Browse へ遷移し、不一致の失敗通知は無視される", %{
      conn: conn,
      user: user
    } do
      pdf_input =
        file_input(live_upload_view(conn), "#upload-form", :pdf, [
          %{
            name: "valid_upload.pdf",
            content: minimal_pdf_content(),
            type: "application/pdf"
          }
        ])

      render_upload(pdf_input, "valid_upload.pdf")
      render_submit(form(pdf_input.view, "#upload-form", %{"color_mode" => "mono"}))

      pdf_source = latest_pdf_source_for(user)

      on_exit(fn ->
        cleanup_upload_artifacts(pdf_source)
      end)

      send(pdf_input.view.pid, {:extraction_failed, pdf_source.id + 1, :ignored})

      refute render(pdf_input.view) =~ "PDF の処理に失敗しました。"

      assert_redirect(pdf_input.view, ~p"/lab/browse/#{pdf_source.id}", 10_000)
    end

    test "失敗通知で画面に留まり、不一致の成功通知は無視される", %{
      conn: conn,
      user: user
    } do
      pdf_input =
        file_input(live_upload_view(conn), "#upload-form", :pdf, [
          %{
            name: "broken_upload.pdf",
            content: "this is not a valid pdf",
            type: "application/pdf"
          }
        ])

      render_upload(pdf_input, "broken_upload.pdf")
      render_submit(form(pdf_input.view, "#upload-form", %{"color_mode" => "mono"}))

      pdf_source = latest_pdf_source_for(user)

      on_exit(fn ->
        cleanup_upload_artifacts(pdf_source)
      end)

      send(pdf_input.view.pid, {:extraction_complete, pdf_source.id + 1})

      refute_receive {_, {:redirect, _, _}}, 500

      html =
        wait_until(fn ->
          rendered = render(pdf_input.view)

          if rendered =~ "PDF の処理に失敗しました。" do
            rendered
          else
            nil
          end
        end)

      assert html =~ "PDF の処理に失敗しました。"
      refute_receive {_, {:redirect, _, _}}, 500
    end
  end

  defp live_upload_view(conn) do
    {:ok, view, _html} = live(conn, ~p"/lab/upload")
    view
  end

  defp latest_pdf_source_for(user) do
    user
    |> Ingestion.list_user_pdf_sources()
    |> List.first()
  end

  defp cleanup_upload_artifacts(nil), do: :ok

  defp cleanup_upload_artifacts(pdf_source) do
    pages_dir = Path.join(["priv", "static", "uploads", "pages", "#{pdf_source.id}"])
    pdf_path = Path.join(["priv", "static", "uploads", "pdfs", pdf_source.filename])

    File.rm_rf(pages_dir)
    File.rm(pdf_path)
  end

  defp minimal_pdf_content do
    """
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
    """
  end

  defp wait_until(fun, attempts \\ 50)

  defp wait_until(_fun, 0) do
    flunk("条件がタイムアウトするまで満たされませんでした")
  end

  defp wait_until(fun, attempts) do
    case fun.() do
      nil ->
        Process.sleep(100)
        wait_until(fun, attempts - 1)

      result ->
        result
    end
  end
end
