defmodule ImtOrder.API do
  use API.Exceptions
  use Plug.Router
  alias ImtOrder.OrderDispatcher
  alias ImtOrder.OrderTransactor
  require Logger
  #plug Plug.Logger
  plug :match
  plug :dispatch

  get "/aggregate-stats/:product" do
    product = String.to_integer(conn.params["product"])

    case ImtOrder.StatsToDb.get(product) do
      {:ok, stats} ->
        res = Enum.reduce(stats, %{ca: 0, total_qty: 0}, fn %{qty: sold_qty, price: price}, acc ->
          %{acc |
            ca: acc.ca + sold_qty * price,
            total_qty: acc.total_qty + sold_qty
          }
        end)

        res = Map.put(res, :mean_price, res.ca / (if res.total_qty == 0, do: 1, else: res.total_qty))

        conn
        |> send_resp(200, Poison.encode!(res))
        |> halt()

      {:error, error} ->
        conn
        |> send_resp(200, Poison.encode!(%{:mean_price => 0, :total_qty => 0, :ca => 0}))
        |> halt()
    end
  end

  put "/stocks" do
    {:ok,bin,conn} = read_body(conn,length: 100_000_000)
    for line<-String.split(bin,"\n") do
      case String.split(line,",") do
        [_,_,_]=l->
          [prod_id,store_id,quantity] = Enum.map(l,&String.to_integer/1)
          MicroDb.HashTable.put("stocks",{store_id,prod_id},quantity)
        _-> :ignore_line
      end
    end
    conn |> send_resp(200,"") |> halt()
  end

  # Choose first store containing all products and send it the order !
  post "/order" do
    {:ok,bin,conn} = read_body(conn)
    order = Poison.decode!(bin)

    case OrderDispatcher.start(order["id"]) do
      {:ok, node} ->
        case OrderTransactor.new(node, order) do
          :ok ->
            Logger.info("Order #{order["id"]} created")
            conn |> send_resp(200, "") |> halt()
          err ->
            Logger.error("[Create] Error #{inspect err}")
            conn |> send_resp(500, "") |> halt()
        end
      err ->
        Logger.error("[Create] Error #{inspect err}")
        conn |> send_resp(500, "") |> halt()
    end
  end

  # payment arrived, get order and process package delivery !
  post "/order/:orderid/payment-callback" do
    {:ok,bin,conn} = read_body(conn)
    %{"transaction_id" => transaction_id} = Poison.decode!(bin)
    {:ok, node} = OrderDispatcher.start(orderid)
    case OrderTransactor.payment(node, orderid, transaction_id) do
      :ok ->
        Logger.info("Order #{orderid} payment received")
        conn |> send_resp(200, "") |> halt()
      err ->
        Logger.error("[Payment] Error #{inspect err}")
        conn |> send_resp(400, "") |> halt()
    end
  end
end
