defmodule TFU.Uploader do
  @moduledoc """
  Получает файл от клиента и сохраняет его.

  ## Протокол работы:
  1. Получает от клиента `header` размером 42 байта. Он состоит из размера желаемого имени
  файла на сервере (первые 2 байта) и размера файла (`data_size`, оставшиеся 40 байт).
  2. Получает от клиента `data_size` байтов. Если клиент больше данные не передает,
  отправляет клиенту байт со значением 1 и закрывает соединение.
  3. Сервер завершает исполнение со статусом :normal.

  Файл сохраняется на сервере в соответствии с желаемым именем файла относительно директории `uploads`.
  Если файл с таким именем уже существует, к данному имени добавляется случайная комбинация цифр.

  ## Действия в результате нарушения протокола со стороны клиента:
  1. Если клиент некорректно передает `header` - сервер заврешает исполнение с ошибкой.
  2. Если клиент закрывает соединение, не передав `data_size` байтов - завершается с ошибкой.
  3. Если клиент закрывает соединение, передав `data_size` байтов - завершается со статусом :normal.
  4. Если после передачи `data_size` байтов клиент продолжает передавать данные - отправляет клиенту байт '0' и завершается с ошибкой.

  Если сервер завршается с ошибкой, файл в `uploads` удаляется.
  """
  use GenServer, restart: :temporary

  require Logger

  @header_size 42
  @init_state %{
    client_socket: nil,
    file: nil,
    filename: nil,
    data_size_expected: nil,
    data_size_current: 0
  }

  def start_link(client_socket) do
    GenServer.start_link(__MODULE__, client_socket)
  end

  @impl true
  def init(client_socket) do
    send(self(), :on_start)
    {:ok, %{@init_state | client_socket: client_socket}}
  end

  @impl true
  def handle_info(:on_start, %{client_socket: client_socket} = state) do
    with {filename_size, data_size} when is_integer(filename_size) <-
           receive_header(client_socket),
         {:ok, filename} <- receive_filename(client_socket, filename_size) do
      {:ok, file} = create_file(filename)
      :ok = :inet.setopts(client_socket, active: :once)

      Logger.info(
        "Receiving file '#{filename}'. Expected data size: #{(data_size / (1024 * 1024)) |> Float.round(2)} MB"
      )

      TFU.Stats.create(self())

      {:noreply, %{state | data_size_expected: data_size, file: file, filename: filename}}
    else
      {:error, error} ->
        {:stop, error, state}
    end
  end

  @impl true
  def handle_info({:tcp, _, data}, state) do
    case IO.binwrite(state.file, data) do
      :ok ->
        received_data_size = byte_size(data)

        state = update_stats_and_state(state, received_data_size)
        {:noreply, state, {:continue, :make_desicion}}

      {:error, error} ->
        {:stop, error, state}
    end
  end

  @impl true
  def handle_info({:tcp_closed, _}, state) do
    if state.data_size_current < state.data_size_expected do
      {:stop, :client_closed, state}
    else
      Logger.warn("Client closed connection, but file was successfully received")
      {:stop, :normal, state}
    end
  end

  @impl true
  def handle_continue(:make_desicion, state) do
    cond do
      state.data_size_current < state.data_size_expected ->
        :ok = :inet.setopts(state.client_socket, active: :once)
        {:noreply, state}

      state.data_size_current == state.data_size_expected ->
        {:noreply, state, {:continue, :on_end}}

      true ->
        {:stop, :larger_data, state}
    end
  end

  @impl true
  def handle_continue(:on_end, %{client_socket: client_socket} = state) do
    case validate_client_finished(client_socket) do
      :finished ->
        Logger.info("Successfully received file.")
        {:stop, :normal, state}

      :closed ->
        Logger.warn("Client closed connection, but file was successfully received")
        {:stop, :normal, state}

      :not_finished ->
        {:stop, :larger_data, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    if reason == :normal do
      send_ok_and_close(state.client_socket)
    else
      rm_file_if_exists(state.filename)
      send_error_and_close(state.client_socket)
    end

    TFU.Stats.delete(self())
    reason
  end

  # PRIVATE

  defp rm_file_if_exists(nil) do
    :ok
  end

  defp rm_file_if_exists(filename) do
    File.rm!(filename)
  end

  defp receive_header(client_socket) do
    case :gen_tcp.recv(client_socket, @header_size, 1000) do
      {:ok, header} ->
        parse_header(header)

      _ ->
        {:error, :receive_header_error}
    end
  end

  defp receive_filename(client_socket, filename_size) do
    with {:ok, filename} <- :gen_tcp.recv(client_socket, filename_size, 1000),
         :ok <- validate_filename(filename) do
      {:ok, process_filename(filename)}
    else
      _ ->
        {:error, :receive_filename_error}
    end
  end

  defp validate_filename(filename) do
    if String.valid?(filename) do
      :ok
    else
      Logger.error("Filename is not valid")
      {:error, :filename_is_not_valid}
    end
  end

  defp create_file(filename) do
    with :ok <- make_file_dir_if_not_exist(filename),
         {:ok, file} <- File.open(filename, [:binary, :write]) do
      {:ok, file}
    else
      _ ->
        {:error, :create_file_error}
    end
  end

  defp update_stats_and_state(state, received_data_size) do
    TFU.Stats.update(self(), received_data_size, state.data_size_current)

    %{state | data_size_current: state.data_size_current + received_data_size}
  end

  defp parse_header(header) when is_binary(header) do
    <<filename_size_bin::binary-size(2), data_size_bin::binary-size(40)>> = header
    <<filename_size::16>> = filename_size_bin
    <<data_size::320>> = data_size_bin
    {filename_size, data_size}
  end

  defp make_file_dir_if_not_exist(filename) when is_binary(filename) do
    filename
    |> Path.split()
    |> Enum.reverse()
    |> tl()
    |> Enum.reverse()
    |> File.mkdir_p()
  end

  defp process_filename(filename) when is_binary(filename) do
    filename = Path.join("uploads", filename)

    if File.exists?(filename) do
      new_filename(filename)
    else
      filename
    end
  end

  defp new_filename(filename) when is_binary(filename) do
    [head | tail] = String.split(filename, ".")
    head = "#{head}#{Enum.random(100_000..999_999)}"
    Enum.join([head] ++ tail, ".")
  end

  defp validate_client_finished(client_socket) do
    case :gen_tcp.recv(client_socket, 1, 1) do
      {:error, :timeout} ->
        :finished

      {:error, :closed} ->
        :closed

      _ ->
        :not_finished
    end
  end

  defp send_ok_and_close(client_socket) do
    :ok = :gen_tcp.send(client_socket, <<1>>)
    :ok = :gen_tcp.close(client_socket)
  end

  defp send_error_and_close(client_socket) do
    :ok = :gen_tcp.send(client_socket, <<0>>)
    :ok = :gen_tcp.close(client_socket)
  end
end
