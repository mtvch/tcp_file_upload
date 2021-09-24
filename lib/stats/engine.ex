defmodule TFU.Stats.Engine do
  @moduledoc """
  Реализация работы со статистикой.

  Выводит статистику по `uploader`'ам раз в `printing_stats_delay` из конфигурации приложения
  мс.
  """
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    schedule_printing()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:create, caller}, %{} = state) when is_pid(caller) do
    now = :erlang.system_time()

    stats = %TFU.Stats{
      id: caller,
      time_started: now,
      time_last_touched: now
    }

    {:noreply, Map.put(state, caller, stats)}
  end

  def handle_cast({:update, caller, data_size_received, data_size_before}, %{} = state) do
    now = :erlang.system_time()
    %TFU.Stats{} = stats = Map.get(state, caller)
    time_uploading = now - stats.time_started
    time_inst = now - stats.time_last_touched

    stats = %TFU.Stats{
      stats
      | time_uploading: time_uploading,
        speed_avg: (data_size_before + data_size_received) / time_uploading,
        speed_inst: data_size_received / time_inst,
        time_last_touched: now
    }

    {:noreply, Map.put(state, caller, stats)}
  end

  @impl true
  def handle_cast({:delete, id}, %{} = state) when is_pid(id) do
    state =
      if Map.has_key?(state, id) do
        Map.update!(state, id, &Map.put(&1, :status, :finished))
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:print, %{} = state) do
    Task.start_link(fn -> print_stats(state) end)

    schedule_printing()

    {:noreply, delete_finished(state)}
  end

  defp schedule_printing do
    Process.send_after(self(), :print, Application.get_env(:tfu, :printing_stats_delay, 3 * 1000))
  end

  defp delete_finished(%{} = state) do
    Enum.reduce(state, %{}, fn {id, entry}, acc ->
      if entry.status == :running do
        Map.put(acc, id, entry)
      else
        acc
      end
    end)
  end

  defp print_stats(%{} = state) do
    state
    |> Enum.map(fn {_, entry} -> entry end)
    |> Scribe.print(
      data: [
        {"ID", :id},
        {"AVG SPEED, MB/s",
         fn x -> (x.speed_avg * 1_000_000_000 / (1024 * 1024)) |> Float.round(2) end},
        {"INSTANT SPEED, MB/s",
         fn x -> (x.speed_inst * 1_000_000_000 / (1024 * 1024)) |> Float.round(2) end},
        {"TIME UPLOADING, s", fn x -> (x.time_uploading / 1_000_000_000) |> Float.round(2) end},
        {"STATUS", :status}
      ]
    )
  end
end
