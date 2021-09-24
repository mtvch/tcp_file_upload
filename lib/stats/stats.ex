defmodule TFU.Stats do
  @moduledoc """
  Модуль для работы со статистикой `Uploader`.

  `Uploader` процесс должен, сначала, создать запись для себя при помощи `create`, потом,
  в течение загрузки обновлять данные через `update`, и после окончания загрузки удалить
  себя из статистики через `delete`.
  """
  defstruct speed_avg: 0,
            speed_inst: 0,
            time_uploading: 0,
            time_started: nil,
            time_last_touched: nil,
            id: nil,
            status: :running

  @type t :: %__MODULE__{
          # Bytes/s^-9
          speed_avg: number(),
          # Bytes/s^-9
          speed_inst: number(),
          # s^-9
          time_started: number(),
          # s^-9
          time_last_touched: number(),
          # s^-9
          time_uploading: number(),
          id: pid(),
          status: :running | :finished
        }

  @doc """
  Создает запись `caller`'а в статистике
  """
  def create(caller) when is_pid(caller) do
    GenServer.cast(__MODULE__.Engine, {:create, caller})
  end

  @doc """
  Обновляет запись `caller`'а в статистике
  """
  def update(caller, data_size_received, data_size_before)
      when is_pid(caller) and is_integer(data_size_received) and is_integer(data_size_before) do
    GenServer.cast(__MODULE__.Engine, {:update, caller, data_size_received, data_size_before})
  end

  @doc """
  Удаляет запись `caller`'а из статистики
  """
  def delete(caller) when is_pid(caller) do
    GenServer.cast(__MODULE__.Engine, {:delete, caller})
  end
end
