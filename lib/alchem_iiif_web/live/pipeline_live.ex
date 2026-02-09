defmodule AlchemIiifWeb.PipelineLive do
  @moduledoc """
  並列処理パイプラインの進捗をリアルタイム表示する LiveView。

  PubSub をサブスクライブして各タスクのプログレスバーを動的に更新し、
  システムリソース情報も表示します。
  """
  use AlchemIiifWeb, :live_view

  alias AlchemIiif.Pipeline
  alias AlchemIiif.Pipeline.ResourceMonitor

  @impl true
  def mount(%{"pipeline_id" => pipeline_id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AlchemIiif.PubSub, Pipeline.topic(pipeline_id))
    end

    # システムリソース情報を取得
    system_info = ResourceMonitor.system_info()

    {:ok,
     socket
     |> assign(:page_title, "処理状況")
     |> assign(:pipeline_id, pipeline_id)
     |> assign(:system_info, system_info)
     |> assign(:tasks, %{})
     |> assign(:phase, :waiting)
     |> assign(:phase_message, "処理を開始しています...")
     |> assign(:overall_progress, 0)
     |> assign(:completed, false)
     |> assign(:error, nil)
     |> assign(:result_summary, nil)
     |> assign(:redirect_to, nil)}
  end

  @impl true
  def handle_info({:pipeline_progress, payload}, socket) do
    socket = process_pipeline_event(payload, socket)
    {:noreply, socket}
  end

  # --- イベントハンドラ ---

  @impl true
  def handle_event("go_back", _params, socket) do
    case socket.assigns.redirect_to do
      nil -> {:noreply, push_navigate(socket, to: ~p"/lab")}
      path -> {:noreply, push_navigate(socket, to: path)}
    end
  end

  # --- プライベート関数 ---

  defp process_pipeline_event(%{event: :pipeline_started} = payload, socket) do
    socket
    |> assign(:phase, payload.phase)
    |> assign(:phase_message, payload.message)
    |> assign(:overall_progress, 0)
  end

  defp process_pipeline_event(%{event: :phase_complete} = payload, socket) do
    socket
    |> assign(:phase_message, payload.message)
  end

  defp process_pipeline_event(%{event: :task_progress} = payload, socket) do
    tasks =
      Map.put(socket.assigns.tasks, payload.task_id, %{
        task_id: payload.task_id,
        status: payload.status,
        progress: payload.progress,
        message: payload.message
      })

    # 全体進捗を計算
    overall =
      if map_size(tasks) > 0 do
        completed_count = Enum.count(tasks, fn {_, t} -> t.status == :completed end)
        round(completed_count / map_size(tasks) * 100)
      else
        0
      end

    socket
    |> assign(:tasks, tasks)
    |> assign(:overall_progress, overall)
    |> assign(:phase_message, payload.message)
  end

  defp process_pipeline_event(%{event: :pipeline_complete} = payload, socket) do
    socket
    |> assign(:completed, true)
    |> assign(:overall_progress, 100)
    |> assign(:result_summary, %{
      total: payload.total,
      succeeded: payload.succeeded,
      failed: payload.failed
    })
    |> assign(:phase_message, "処理が完了しました！")
  end

  defp process_pipeline_event(%{event: :pipeline_error} = payload, socket) do
    socket
    |> assign(:error, payload.message)
    |> assign(:phase_message, "エラーが発生しました")
  end

  defp process_pipeline_event(_payload, socket), do: socket

  # ステータスに応じた絵文字
  defp status_emoji(:pending), do: "⏳"
  defp status_emoji(:processing), do: "⚙️"
  defp status_emoji(:completed), do: "✅"
  defp status_emoji(:error), do: "❌"
  defp status_emoji(_), do: "⏳"

  # ステータスラベル
  defp status_label(:pending), do: "待機中"
  defp status_label(:processing), do: "処理中"
  defp status_label(:completed), do: "完了"
  defp status_label(:error), do: "エラー"
  defp status_label(_), do: "不明"

  # バイトの人間用フォーマット
  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 1)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pipeline-container">
      <%!-- ヘッダー --%>
      <div class="pipeline-header">
        <h1 class="pipeline-title">⚡ パイプライン処理</h1>
        <p class="pipeline-subtitle">{@phase_message}</p>
      </div>

      <%!-- システムリソース情報 --%>
      <div class="resource-info-card">
        <h3 class="resource-title">🖥️ システムリソース</h3>
        <div class="resource-grid">
          <div class="resource-item">
            <span class="resource-label">CPU コア数</span>
            <span class="resource-value">{@system_info.cpu_cores}</span>
          </div>
          <div class="resource-item">
            <span class="resource-label">総メモリ</span>
            <span class="resource-value">{format_bytes(@system_info.total_memory_bytes)}</span>
          </div>
          <div class="resource-item">
            <span class="resource-label">利用可能メモリ</span>
            <span class="resource-value">{format_bytes(@system_info.available_memory_bytes)}</span>
          </div>
          <div class="resource-item">
            <span class="resource-label">パイプライン並列度</span>
            <span class="resource-value">{@system_info.pipeline_concurrency}</span>
          </div>
          <div class="resource-item">
            <span class="resource-label">最大PTIF同時変換</span>
            <span class="resource-value">{@system_info.max_ptif_workers}</span>
          </div>
        </div>
      </div>

      <%!-- 全体進捗バー --%>
      <div class="overall-progress-section">
        <div class="progress-header">
          <span class="progress-label">全体の進捗</span>
          <span class="progress-percentage">{@overall_progress}%</span>
        </div>
        <div
          class="progress-bar-container"
          role="progressbar"
          aria-valuenow={@overall_progress}
          aria-valuemin="0"
          aria-valuemax="100"
        >
          <div
            class={"progress-bar-fill #{if @completed, do: "progress-complete", else: "progress-active"}"}
            style={"width: #{@overall_progress}%"}
          >
          </div>
        </div>
      </div>

      <%!-- エラー表示 --%>
      <%= if @error do %>
        <div class="pipeline-error" role="alert">
          <span class="error-icon">⚠️</span>
          <span class="error-text">{@error}</span>
        </div>
      <% end %>

      <%!-- 完了サマリー --%>
      <%= if @result_summary do %>
        <div class="result-summary-card">
          <h3 class="summary-title">📊 処理結果</h3>
          <div class="summary-grid">
            <div class="summary-item summary-total">
              <span class="summary-number">{@result_summary.total}</span>
              <span class="summary-label">合計</span>
            </div>
            <div class="summary-item summary-success">
              <span class="summary-number">{@result_summary.succeeded}</span>
              <span class="summary-label">成功</span>
            </div>
            <div class="summary-item summary-failed">
              <span class="summary-number">{@result_summary.failed}</span>
              <span class="summary-label">失敗</span>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- タスク一覧 --%>
      <%= if map_size(@tasks) > 0 do %>
        <div class="tasks-section">
          <h3 class="tasks-title">📋 タスク一覧</h3>
          <div class="task-list">
            <%= for {_id, task} <- Enum.sort_by(@tasks, fn {id, _} -> id end) do %>
              <div class={"task-card task-#{task.status}"}>
                <div class="task-header">
                  <span class="task-emoji">{status_emoji(task.status)}</span>
                  <span class="task-message">{task.message}</span>
                  <span class={"task-badge badge-#{task.status}"}>{status_label(task.status)}</span>
                </div>
                <div
                  class="task-progress-bar"
                  role="progressbar"
                  aria-valuenow={task.progress}
                  aria-valuemin="0"
                  aria-valuemax="100"
                >
                  <div
                    class={"task-progress-fill fill-#{task.status}"}
                    style={"width: #{task.progress}%"}
                  >
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- ナビゲーション --%>
      <div class="pipeline-actions">
        <%= if @completed do %>
          <button type="button" class="btn-primary btn-large" phx-click="go_back">
            ✅ 完了 — 次へ進む
          </button>
        <% else %>
          <div class="processing-indicator" role="status" aria-live="polite">
            <span class="spinner"></span>
            <span>処理中です。しばらくお待ちください...</span>
          </div>
        <% end %>
      </div>
    </div>

    <style>
      /* パイプラインコンテナ */
      .pipeline-container {
        max-width: 800px;
        margin: 2rem auto;
        padding: 0 1.5rem;
        font-family: 'Inter', 'Hiragino Sans', sans-serif;
      }

      /* ヘッダー */
      .pipeline-header {
        text-align: center;
        margin-bottom: 2rem;
      }

      .pipeline-title {
        font-size: 1.75rem;
        font-weight: 700;
        color: #1a1a2e;
        margin-bottom: 0.5rem;
      }

      .pipeline-subtitle {
        color: #6b7280;
        font-size: 1rem;
      }

      /* ===== リソース情報カード ===== */
      .resource-info-card {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        border-radius: 16px;
        padding: 1.5rem;
        margin-bottom: 2rem;
        color: white;
        box-shadow: 0 4px 20px rgba(102, 126, 234, 0.3);
      }

      .resource-title {
        font-size: 1rem;
        font-weight: 600;
        margin-bottom: 1rem;
        opacity: 0.95;
      }

      .resource-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
        gap: 1rem;
      }

      .resource-item {
        display: flex;
        flex-direction: column;
        align-items: center;
        background: rgba(255, 255, 255, 0.15);
        border-radius: 12px;
        padding: 0.75rem;
        backdrop-filter: blur(10px);
      }

      .resource-label {
        font-size: 0.75rem;
        opacity: 0.8;
        margin-bottom: 0.25rem;
      }

      .resource-value {
        font-size: 1.25rem;
        font-weight: 700;
      }

      /* ===== 全体進捗バー ===== */
      .overall-progress-section {
        margin-bottom: 2rem;
      }

      .progress-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 0.5rem;
      }

      .progress-label {
        font-weight: 600;
        color: #374151;
      }

      .progress-percentage {
        font-weight: 700;
        font-size: 1.25rem;
        color: #667eea;
      }

      .progress-bar-container {
        width: 100%;
        height: 12px;
        background: #e5e7eb;
        border-radius: 999px;
        overflow: hidden;
      }

      .progress-bar-fill {
        height: 100%;
        border-radius: 999px;
        transition: width 0.5s ease-in-out;
      }

      .progress-active {
        background: linear-gradient(90deg, #667eea, #764ba2);
        animation: progress-pulse 2s ease-in-out infinite;
      }

      .progress-complete {
        background: linear-gradient(90deg, #10b981, #059669);
      }

      @keyframes progress-pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.7; }
      }

      /* ===== エラー表示 ===== */
      .pipeline-error {
        background: #fef2f2;
        border: 1px solid #fecaca;
        border-radius: 12px;
        padding: 1rem 1.5rem;
        margin-bottom: 1.5rem;
        display: flex;
        align-items: center;
        gap: 0.75rem;
      }

      .pipeline-error .error-icon {
        font-size: 1.25rem;
      }

      .pipeline-error .error-text {
        color: #dc2626;
        font-weight: 500;
      }

      /* ===== 完了サマリー ===== */
      .result-summary-card {
        background: #f0fdf4;
        border: 1px solid #bbf7d0;
        border-radius: 16px;
        padding: 1.5rem;
        margin-bottom: 2rem;
      }

      .summary-title {
        font-size: 1rem;
        font-weight: 600;
        color: #166534;
        margin-bottom: 1rem;
      }

      .summary-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 1rem;
        text-align: center;
      }

      .summary-item {
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 0.75rem;
        border-radius: 12px;
      }

      .summary-total { background: rgba(99, 102, 241, 0.1); }
      .summary-success { background: rgba(16, 185, 129, 0.1); }
      .summary-failed { background: rgba(239, 68, 68, 0.1); }

      .summary-number {
        font-size: 2rem;
        font-weight: 800;
      }

      .summary-total .summary-number { color: #6366f1; }
      .summary-success .summary-number { color: #10b981; }
      .summary-failed .summary-number { color: #ef4444; }

      .summary-label {
        font-size: 0.8rem;
        color: #6b7280;
        margin-top: 0.25rem;
      }

      /* ===== タスク一覧 ===== */
      .tasks-section {
        margin-bottom: 2rem;
      }

      .tasks-title {
        font-size: 1rem;
        font-weight: 600;
        color: #374151;
        margin-bottom: 1rem;
      }

      .task-list {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
      }

      .task-card {
        background: white;
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        padding: 1rem;
        transition: all 0.3s ease;
        box-shadow: 0 1px 3px rgba(0,0,0,0.05);
      }

      .task-card:hover {
        box-shadow: 0 4px 12px rgba(0,0,0,0.1);
      }

      .task-completed { border-left: 4px solid #10b981; }
      .task-processing { border-left: 4px solid #667eea; }
      .task-error { border-left: 4px solid #ef4444; }
      .task-pending { border-left: 4px solid #9ca3af; }

      .task-header {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin-bottom: 0.5rem;
      }

      .task-emoji { font-size: 1.1rem; }

      .task-message {
        flex: 1;
        font-size: 0.9rem;
        color: #374151;
      }

      .task-badge {
        font-size: 0.7rem;
        font-weight: 600;
        padding: 0.2rem 0.6rem;
        border-radius: 999px;
        text-transform: uppercase;
      }

      .badge-completed { background: #d1fae5; color: #065f46; }
      .badge-processing { background: #e0e7ff; color: #3730a3; }
      .badge-error { background: #fee2e2; color: #991b1b; }
      .badge-pending { background: #f3f4f6; color: #6b7280; }

      .task-progress-bar {
        width: 100%;
        height: 6px;
        background: #f3f4f6;
        border-radius: 999px;
        overflow: hidden;
      }

      .task-progress-fill {
        height: 100%;
        border-radius: 999px;
        transition: width 0.4s ease-in-out;
      }

      .fill-completed { background: #10b981; }
      .fill-processing {
        background: linear-gradient(90deg, #667eea, #764ba2);
        animation: progress-pulse 1.5s ease-in-out infinite;
      }
      .fill-error { background: #ef4444; }
      .fill-pending { background: #d1d5db; }

      /* ===== アクションバー ===== */
      .pipeline-actions {
        text-align: center;
        padding: 1.5rem 0;
      }

      .processing-indicator {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 0.75rem;
        color: #6b7280;
        font-size: 0.95rem;
      }

      /* スピナー */
      .spinner {
        display: inline-block;
        width: 20px;
        height: 20px;
        border: 3px solid #e5e7eb;
        border-top-color: #667eea;
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
      }

      @keyframes spin {
        to { transform: rotate(360deg); }
      }

      /* ボタン */
      .btn-primary {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border: none;
        padding: 0.875rem 2rem;
        border-radius: 12px;
        font-size: 1rem;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.3s ease;
        box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
      }

      .btn-primary:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(102, 126, 234, 0.4);
      }

      .btn-large {
        padding: 1rem 2.5rem;
        font-size: 1.1rem;
      }

      /* レスポンシブ対応 */
      @media (max-width: 640px) {
        .pipeline-container {
          padding: 0 1rem;
        }

        .resource-grid {
          grid-template-columns: repeat(2, 1fr);
        }

        .summary-grid {
          grid-template-columns: repeat(3, 1fr);
          gap: 0.5rem;
        }

        .summary-number {
          font-size: 1.5rem;
        }
      }
    </style>
    """
  end
end
