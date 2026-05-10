defmodule AlchemIiif.SourceProcessingDispatcherFake do
  @moduledoc false

  @behaviour AlchemIiif.SourceProcessingDispatcher

  @impl true
  def dispatch_source_processing(user_id, source, source_path, pipeline_id, opts) do
    if pid = Application.get_env(:alchem_iiif, :source_processing_dispatch_test_pid) do
      send(pid, {
        :source_processing_dispatched,
        %{
          user_id: user_id,
          source_id: source.id,
          source_type: Map.get(source, :source_type, "pdf"),
          source_path: source_path,
          pipeline_id: pipeline_id,
          opts: opts
        }
      })
    end

    :ok
  end
end
