defmodule AlchemIiifWeb.WizardComponents do
  @moduledoc """
  ウィザード UI の共通コンポーネント。
  Inspector フローの全ステップで共有されるヘッダーを提供します。
  """
  use Phoenix.Component

  @doc """
  ウィザード進捗ヘッダー。
  現在のステップをハイライト表示します。

  ## 属性
    - current_step: 現在のステップ番号 (1-4)
  """
  attr :current_step, :integer, required: true

  def wizard_header(assigns) do
    ~H"""
    <nav class="wizard-header" aria-label="進捗ステップ">
      <ol class="wizard-steps">
        <li class={"wizard-step #{if @current_step >= 1, do: "active", else: ""}"}>
          <span class="step-number">1</span>
          <span class="step-label">アップロード</span>
        </li>
        <li class={"wizard-step #{if @current_step >= 2, do: "active", else: ""}"}>
          <span class="step-number">2</span>
          <span class="step-label">ページ選択</span>
        </li>
        <li class={"wizard-step #{if @current_step >= 3, do: "active", else: ""}"}>
          <span class="step-number">3</span>
          <span class="step-label">クロップ</span>
        </li>
        <li class={"wizard-step #{if @current_step >= 4, do: "active", else: ""}"}>
          <span class="step-number">4</span>
          <span class="step-label">保存</span>
        </li>
      </ol>
    </nav>
    """
  end
end
