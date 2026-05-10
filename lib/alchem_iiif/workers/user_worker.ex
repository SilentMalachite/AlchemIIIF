defmodule AlchemIiif.Workers.UserWorker do
  @moduledoc """
  ユーザーごとのバックグラウンドワーカー GenServer。

  DynamicSupervisor 配下で起動され、PDF / ZIP 抽出など重い処理を
  LiveView プロセスから分離して非同期実行します。
  """
  use GenServer
  @behaviour AlchemIiif.SourceProcessingDispatcher
  require Logger

  @registry AlchemIiif.UserWorkerRegistry
  @supervisor AlchemIiif.UserWorkerSupervisor

  # Client API

  def start_user_worker(user_id) do
    name = via_tuple(user_id)
    DynamicSupervisor.start_child(@supervisor, {__MODULE__, [user_id: user_id, name: name]})
  end

  def process_source(user_id, source, source_path, pipeline_id, opts \\ %{}) do
    GenServer.cast(
      via_tuple(user_id),
      {:process_source, source, source_path, pipeline_id, opts}
    )
  end

  @impl true
  def dispatch_source_processing(user_id, source, source_path, pipeline_id, opts) do
    process_source(user_id, source, source_path, pipeline_id, opts)
    :ok
  end

  defp via_tuple(user_id), do: {:via, Registry, {@registry, user_id}}

  # Server Callbacks

  def start_link(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, %{user_id: user_id}, name: name)
  end

  @impl true
  def init(state) do
    Logger.info("✅ UserWorker started safely for user_id: #{state.user_id}")
    {:ok, Map.merge(state, %{current_job: nil, queue: :queue.new()})}
  end

  @impl true
  def handle_cast(
        {:process_source, _source, _source_path, _pipeline_id, _opts} = job,
        state
      ) do
    if state.current_job do
      {:noreply, %{state | queue: :queue.in(job, state.queue)}}
    else
      {:noreply, start_job(job, state)}
    end
  end

  @impl true
  def handle_cast({:source_processing_finished, ref}, %{current_job: ref} = state) do
    case :queue.out(state.queue) do
      {{:value, next_job}, queue} ->
        {:noreply, start_job(next_job, %{state | current_job: nil, queue: queue})}

      {:empty, queue} ->
        {:noreply, %{state | current_job: nil, queue: queue}}
    end
  end

  def handle_cast({:source_processing_finished, _stale_ref}, state), do: {:noreply, state}

  defp start_job({:process_source, source, source_path, pipeline_id, opts}, state) do
    Logger.info(
      "⚙️ ユーザー(#{state.user_id})の source(ID:#{source.id}, type:#{Map.get(source, :source_type, "pdf")})の裏側処理を開始します..."
    )

    ref = make_ref()
    user_id = state.user_id

    Task.start(fn ->
      try do
        runner().run_extraction(
          source,
          source_path,
          pipeline_id,
          pipeline_opts(opts, user_id)
        )

        Phoenix.PubSub.broadcast(
          AlchemIiif.PubSub,
          "source_#{source.id}",
          {:source_processed, source.id}
        )
      after
        GenServer.cast(via_tuple(user_id), {:source_processing_finished, ref})
      end
    end)

    %{state | current_job: ref}
  end

  defp pipeline_opts(%{} = opts, user_id) do
    base = %{
      owner_id: user_id,
      color_mode: Map.get(opts, :color_mode) || "mono"
    }

    case Map.get(opts, :max_pages) do
      max_pages when is_integer(max_pages) -> Map.put(base, :max_pages, max_pages)
      _ -> base
    end
  end

  defp pipeline_opts(color_mode, user_id) when is_binary(color_mode) do
    %{owner_id: user_id, color_mode: color_mode}
  end

  defp pipeline_opts(_opts, user_id) do
    %{owner_id: user_id, color_mode: "mono"}
  end

  defp runner do
    Application.get_env(:alchem_iiif, :pdf_processing_runner, AlchemIiif.Pipeline)
  end
end
