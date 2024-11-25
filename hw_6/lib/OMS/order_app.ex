defmodule ImtOrder.App do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    case ImtOrder.Utils.is_console() do
      true ->
        children = [
          ImtOrder.OrderTransactor.Supervisor,
          ImtOrder.OrderDispatcher.Server,
          ImtOrder.OrderManager.Server,
          {Plug.Cowboy, scheme: :http, plug: ImtOrder.API, options: [port: ImtOrder.Utils.get_port()]}
        ]
        Supervisor.init(children, strategy: :one_for_one)
      false ->
        children = [
          ImtOrder.OrderTransactor.Supervisor,
          ImtOrder.OrderManager.Server
        ]
        Supervisor.init(children, strategy: :one_for_one)
    end
  end
end
