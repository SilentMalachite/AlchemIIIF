defmodule AlchemIiif.PdfProcessingDispatcherFake do
  @moduledoc false

  @behaviour AlchemIiif.PdfProcessingDispatcher

  @impl true
  def dispatch_pdf_processing(user_id, pdf_source, pdf_path, pipeline_id, color_mode) do
    if pid = Application.get_env(:alchem_iiif, :pdf_processing_dispatch_test_pid) do
      send(pid, {
        :pdf_processing_dispatched,
        %{
          user_id: user_id,
          pdf_source_id: pdf_source.id,
          pdf_path: pdf_path,
          pipeline_id: pipeline_id,
          color_mode: color_mode
        }
      })
    end

    :ok
  end
end
