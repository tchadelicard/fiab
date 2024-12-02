defmodule ImtOrder.App do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      ImtOrder.OrderTransactor.Supervisor,
      ImtOrder.OrderDispatcher.Server,
      {Plug.Cowboy, scheme: :http, plug: ImtOrder.API, options: [port: ImtOrder.Utils.get_port()]}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
