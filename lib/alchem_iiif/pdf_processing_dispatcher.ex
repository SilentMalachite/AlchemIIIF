defmodule AlchemIiif.PdfProcessingDispatcher do
  @moduledoc """
  PDF バックグラウンド処理の dispatch 境界。

  本番では `UserWorker` に委譲し、テストでは fake 実装に差し替える。
  """

  @callback dispatch_pdf_processing(
              user_id :: integer(),
              pdf_source :: struct(),
              pdf_path :: String.t(),
              pipeline_id :: String.t(),
              color_mode :: String.t()
            ) :: :ok

  def dispatch_pdf_processing(user_id, pdf_source, pdf_path, pipeline_id, color_mode) do
    impl().dispatch_pdf_processing(user_id, pdf_source, pdf_path, pipeline_id, color_mode)
  end

  defp impl do
    Application.get_env(
      :alchem_iiif,
      :pdf_processing_dispatcher,
      AlchemIiif.Workers.UserWorker
    )
  end
end
