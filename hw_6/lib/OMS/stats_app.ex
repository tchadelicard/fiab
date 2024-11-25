defmodule ImtOrder.Stats do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
        {Plug.Cowboy, scheme: :http, plug: ImtOrder.Stats.API, options: [port: ImtOrder.Utils.get_port()]},
        ImtOrder.StatsToDb.Server
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
