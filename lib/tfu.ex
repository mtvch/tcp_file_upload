defmodule TFU do
  @moduledoc """
  Приложение, позволяющее клиентам загружать файлы на сервер через TCP.
  """
  use Application

  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT") || "4040")

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: TFU.UploaderSupervisor},
      {TFU.Server, port},
      TFU.Stats.Engine
    ]

    opts = [strategy: :one_for_one, name: TFU.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
