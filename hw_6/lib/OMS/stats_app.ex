defmodule ImtOrder.Stats do
  @moduledoc """
  Supervisor for managing the `ImtOrder.Stats` application components.

  This module supervises the HTTP server (`Plug.Cowboy`) for the stats API
  and the `ImtOrder.StatsToDb.Server` responsible for managing statistics data.
  """

  use Supervisor

  @doc """
  Starts the supervisor with the specified initialization argument.
  """
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  @doc """
  Initializes the supervisor with its child processes.

  - `Plug.Cowboy`: HTTP server for the stats API, dynamically configured to listen on a port.
  - `ImtOrder.StatsToDb.Server`: Server handling interactions with the statistics database.
  """
  def init(_) do
    children = [
      # Start the HTTP server for the stats API
      {Plug.Cowboy, scheme: :http, plug: ImtOrder.Stats.API, options: [port: ImtOrder.Utils.get_port()]},
      # Start the StatsToDb server for managing statistics
      ImtOrder.StatsToDb.Server
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
