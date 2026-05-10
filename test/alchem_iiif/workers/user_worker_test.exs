defmodule AlchemIiif.Workers.UserWorkerTest do
  use ExUnit.Case, async: false

  alias AlchemIiif.Workers.UserWorker

  defmodule Runner do
    def run_extraction(source, _source_path, pipeline_id, _opts) do
      test_pid = Application.fetch_env!(:alchem_iiif, :user_worker_test_pid)
      send(test_pid, {:runner_started, source.id, pipeline_id, self()})

      receive do
        {:release, ^pipeline_id} -> :ok
      after
        5_000 -> :timeout
      end
    end
  end

  setup do
    previous_runner = Application.get_env(:alchem_iiif, :pdf_processing_runner)
    previous_pid = Application.get_env(:alchem_iiif, :user_worker_test_pid)

    Application.put_env(:alchem_iiif, :pdf_processing_runner, Runner)
    Application.put_env(:alchem_iiif, :user_worker_test_pid, self())

    user_id = System.unique_integer([:positive])
    start_user_worker(user_id)

    on_exit(fn ->
      stop_user_worker(user_id)
      restore_env(:pdf_processing_runner, previous_runner)
      restore_env(:user_worker_test_pid, previous_pid)
    end)

    {:ok, user_id: user_id}
  end

  test "同一ユーザーの source 処理は並列起動せず直列化される", %{user_id: user_id} do
    src1 = %{id: 1, source_type: "pdf"}
    src2 = %{id: 2, source_type: "pdf"}
    :ok = UserWorker.process_source(user_id, src1, "/tmp/one.pdf", "pipeline-1", %{})
    assert_receive {:runner_started, 1, "pipeline-1", first_task}, 1_000

    :ok = UserWorker.process_source(user_id, src2, "/tmp/two.pdf", "pipeline-2", %{})
    refute_receive {:runner_started, 2, "pipeline-2", _second_task}, 100

    send(first_task, {:release, "pipeline-1"})
    assert_receive {:runner_started, 2, "pipeline-2", second_task}, 1_000

    send(second_task, {:release, "pipeline-2"})
  end

  defp start_user_worker(user_id) do
    case UserWorker.start_user_worker(user_id) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp stop_user_worker(user_id) do
    case Registry.lookup(AlchemIiif.UserWorkerRegistry, user_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(AlchemIiif.UserWorkerSupervisor, pid)
      [] -> :ok
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:alchem_iiif, key)
  defp restore_env(key, value), do: Application.put_env(:alchem_iiif, key, value)
end
