defmodule AlchemIiifWeb.WizardComponents do
  @moduledoc """
  ウィザード UI の共通コンポーネント。
  Inspector フローの全5ステップで共有されるヘッダーと
  Processing Pulse アニメーションを提供します。
  """
  use Phoenix.Component

  @doc """
  ウィザード進捗ヘッダー（ブレッドクラム "現在地マップ"）。
  完了・進行中・未着手を視覚的に区別します。

  ## 属性
    - current_step: 現在のステップ番号 (1-5)
  """
  attr :current_step, :integer, required: true

  def wizard_header(assigns) do
    steps = [
      %{number: 1, icon: "📄", label: "アップロード"},
      %{number: 2, icon: "🔍", label: "ページ選択"},
      %{number: 3, icon: "✂️", label: "クロップ"},
      %{number: 4, icon: "🏷️", label: "ラベリング"},
      %{number: 5, icon: "✅", label: "レビュー提出"}
    ]

    assigns = assign(assigns, :steps, steps)

    ~H"""
    <nav class="wizard-header" aria-label="進捗ステップ" role="navigation">
      <ol class="wizard-steps">
        <%= for step <- @steps do %>
          <li class={"wizard-step #{step_state(@current_step, step.number)}"}>
            <span class={"step-number #{step_state(@current_step, step.number)}"}>
              <%= if step.number < @current_step do %>
                ✓
              <% else %>
                {step.number}
              <% end %>
            </span>
            <span class="step-label">
              <span class="step-icon">{step.icon}</span>
              {step.label}
            </span>
          </li>
        <% end %>
      </ol>
      <%!-- 現在地テキスト表示 --%>
      <div class="wizard-current-location" role="status" aria-live="polite">
        📍 いまここ：
        <strong>
          {Enum.find(@steps, &(&1.number == @current_step)) |> then(& &1.label)}
        </strong>
        <span class="step-counter">（{@current_step} / 5）</span>
      </div>
    </nav>
    """
  end

  # ステップの状態を判定
  defp step_state(current, step_number) when step_number < current, do: "completed"
  defp step_state(current, step_number) when step_number == current, do: "active"
  defp step_state(_current, _step_number), do: "upcoming"

  @doc """
  Processing Pulse — バックグラウンド処理中のアニメーション表示。

  ## 属性
    - active: パルスが有効かどうか
    - message: 表示メッセージ
  """
  attr :active, :boolean, default: false
  attr :message, :string, default: "処理中です..."

  def processing_pulse(assigns) do
    ~H"""
    <%= if @active do %>
      <div class="processing-pulse" role="status" aria-live="polite">
        <div class="pulse-indicator">
          <span class="pulse-dot"></span>
          <span class="pulse-dot"></span>
          <span class="pulse-dot"></span>
        </div>
        <span class="pulse-message">{@message}</span>
      </div>
    <% end %>
    """
  end

  @doc """
  Auto-Save インジケーター。

  ## 属性
    - state: :saved | :saving | :idle
  """
  attr :state, :atom, default: :idle

  def auto_save_indicator(assigns) do
    ~H"""
    <div class={"auto-save-indicator save-#{@state}"} role="status" aria-live="polite">
      <%= case @state do %>
        <% :saved -> %>
          <span class="save-icon">💾</span>
          <span class="save-text">保存済み</span>
        <% :saving -> %>
          <span class="save-icon spinning">⏳</span>
          <span class="save-text">保存中...</span>
        <% _ -> %>
      <% end %>
    </div>
    """
  end
end
