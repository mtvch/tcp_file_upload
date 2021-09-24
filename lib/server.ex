defmodule TFU.Server do
  @moduledoc """
  Сервер, который слушает `port` и передает клиентов `uploader`'ам.
  """
  use GenServer

  require Logger

  @init_state %{
    listening_socket: nil
  }

  @spec start_link(integer) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(port) when is_integer(port) do
    GenServer.start_link(__MODULE__, port)
  end

  @impl true
  def init(port) when is_integer(port) do
    {:ok, @init_state, {:continue, {:start_listening, port}}}
  end

  @impl true
  def handle_continue({:start_listening, port}, state) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: 0, active: false, reuseaddr: true])
    Logger.info("Listening on port #{port}")
    send(self(), :accept)
    {:noreply, %{state | listening_socket: socket}}
  end

  @impl true
  def handle_info(:accept, %{listening_socket: listening_socket} = state) do
    {:ok, client_socket} = :gen_tcp.accept(listening_socket)
    Logger.info("Accepting connection...")

    {:ok, pid} =
      DynamicSupervisor.start_child(TFU.UploaderSupervisor, {TFU.Uploader, client_socket})

    :ok = :gen_tcp.controlling_process(client_socket, pid)
    send(self(), :accept)
    {:noreply, state}
  end
end
