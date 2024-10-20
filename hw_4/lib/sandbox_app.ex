defmodule ImtSandbox.App do
  use Application
  def start(_,_) do
    File.mkdir("data")

    Supervisor.start_link([
      ImtOrder.App,
      ImtSim.WMS,
      ImtSim.EComFront,
    ], strategy: :one_for_one)
  end
end
