defmodule AlchemIiif.SourceProcessingDispatcher do
  @moduledoc """
  ソース（PDF/ZIP）バックグラウンド処理の dispatch 境界。

  本番では `UserWorker` に委譲し、テストでは fake 実装に差し替える。
  """

  @callback dispatch_source_processing(
              user_id :: integer(),
              source :: struct(),
              source_path :: String.t(),
              pipeline_id :: String.t(),
              opts :: map()
            ) :: :ok

  def dispatch_source_processing(user_id, source, source_path, pipeline_id, opts) do
    impl().dispatch_source_processing(user_id, source, source_path, pipeline_id, opts)
  end

  defp impl do
    Application.get_env(
      :alchem_iiif,
      :source_processing_dispatcher,
      AlchemIiif.Workers.UserWorker
    )
  end
end
