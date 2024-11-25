defmodule ImtSandbox.App do
  use Application

  require Logger

  def start(_,_) do
    File.mkdir("data")

    childs = case Application.fetch_env!(:imt_order, :app_type) do
      :front -> [ImtSim.EComFront]
      :back -> [ImtSim.WMS]
      #:lb -> [LoadBalancer]
      :statsdb -> [ImtOrder.Stats]
      :sim-> [ImtOrder.App]
    end

    Logger.info("[#{Node.self()}] Starting #{inspect childs} with params #{inspect Application.get_all_env(:imt_order)}")

    Supervisor.start_link(childs, strategy: :one_for_one)
  end
end
