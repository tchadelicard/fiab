defmodule ImtSandbox.App do
  use Application
  def start(_,_) do
    File.mkdir("data")

    case ImtOrder.Utils.is_console() do
      true ->
        Supervisor.start_link([
          ImtOrder.App,
          ImtSim.WMS,
          ImtSim.EComFront,
        ], strategy: :one_for_one)
      false ->
        Supervisor.start_link([
          ImtOrder.App
        ], strategy: :one_for_one)
    end
  end
end
