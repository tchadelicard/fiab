# in this file : all module for backend simulation :
# generate stocks and stats, and receive orders

defmodule ImtSim.WMS do
  use Supervisor

  @order_receiver_port 9091

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      ImtSim.WMS.Stocks,
      ImtSim.WMS.Stats,
      {Plug.Cowboy, scheme: :http, plug: ImtSim.WMS.OrderReceiver, options: [port: @order_receiver_port]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule ImtSim.WMS.Stocks do
  use GenServer
  require Logger

  @timeout :timer.seconds(15) # Generate file every 15 sec

  def start_link(_) do GenServer.start_link(__MODULE__, [], name: __MODULE__) end
  def init([]) do {:ok, [], @timeout} end

  def handle_info(:timeout, []) do
    gen_stock_file()
    {:noreply, [], @timeout}
  end

  def gen_stock_file() do
    # generate stocks for 10_000 products in 200 stores : IDPROD,IDSTORE,QUANTITY
    nb_products = 10_000
    nb_stores = 200

    lines =
      Enum.flat_map(1..nb_products, fn product_id ->
        Enum.map(1..nb_stores, fn store_id ->
        # stock from 0 to 15, half of the time stock of 0 !
        "#{product_id},#{store_id},#{max(0, :rand.uniform(30) - 15)}\n"
        end)
      end)

    oms_stocks_api = 'http://localhost:9090/stocks'
    Logger.info("[WMS - Simulator] stock file sent to the OMS")
    :httpc.request(:put, {oms_stocks_api, [], 'text/csv', IO.iodata_to_binary(lines)}, [], [])
  end
end

defmodule ImtSim.WMS.Stats do
  use GenServer
  require Logger

  @timeout :timer.seconds(10) # Generate file every 10 sec

  def start_link(_) do GenServer.start_link(__MODULE__, [], name: __MODULE__) end
  def init([]) do {:ok, [], @timeout} end
  def handle_info(:timeout, []) do gen_stat_file(); {:noreply, [], @timeout} end

  def gen_stat_file() do
    # generate 10_000 product line : IDPROD,NBVENTE,PRIXVENTE
    nb_products = 10_000

    file =
      Enum.map(1..nb_products, fn product_id ->
        "#{product_id},#{:rand.uniform(30)},#{:rand.uniform(30)}\n"
      end)

    padded_ts = String.pad_leading("#{:erlang.system_time(:millisecond)}", 15, ["0"])
    file_name = "data/stat_#{padded_ts}.csv"
    File.write!(file_name, file)
    Logger.info("[WMS - Simulator] stat file #{file_name} generated")
  end
end

defmodule ImtSim.WMS.OrderReceiver do
  use Plug.Router
  #plug Plug.Logger
  plug :match
  plug :dispatch

  post "/order/new" do
    create_order_duration = :timer.seconds(2) + (:rand.uniform(8) * 250) # random duration between 2s and 4s with 0.25s step.
    Process.sleep(create_order_duration) # simulate time requeste to create an order on order receiver

    conn
    |> send_resp(200, "")
    |> halt()
  end

  post "/order/process_delivery" do
    process_delivery_duration = 200 # 200ms
    Process.sleep(process_delivery_duration)

    resp_code =
      case :rand.uniform(15) do # fake a failure once in 15
        1 -> 504 # Failure
        _ -> 200 # Success
      end

      conn
      |> send_resp(resp_code, "")
      |> halt()
  end

  match _ do
    conn
  end
end
