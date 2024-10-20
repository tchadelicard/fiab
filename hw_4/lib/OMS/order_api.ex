defmodule ImtOrder.API do
  use API.Exceptions
  use Plug.Router
  #plug Plug.Logger
  plug :match
  plug :dispatch

# Old version without multithreaded file reading
#  get "/aggregate-stats/:product" do
#      res = Path.wildcard("data/stat_*")
#      |> Enum.map(fn file_name ->
#        [sold_qty, price] = ImtOrder.StatsAsDb.find_enum(file_name,product)
#        {price_int, ""} = Integer.parse(price)
#        {sold_qty_int, ""} = Integer.parse(sold_qty)
#        %{qty: sold_qty_int, price: price_int}
#      end)
#      |> Enum.reduce(%{ca: 0, total_qty: 0}, fn %{qty: sold_qty, price: price}, acc ->
#        %{acc|
#           ca: acc.ca + sold_qty * price,
#           total_qty: acc.total_qty + sold_qty
#         }
#      end)
#
#    res = Map.put(res, :mean_price, res.ca / (if res.total_qty == 0, do: 1, else: res.total_qty))
#    conn |> send_resp(200, Poison.encode!(res)) |> halt()
#  end

  # New version with multithreaded file reading
  get "/aggregate-stats/:product" do
    chuncked_res = Path.wildcard("data/stat_*")
    |> Enum.map(fn file_name ->
      current_pid = self()
      spawn_link(fn ->
        [sold_qty, price] = ImtOrder.StatsAsDb.find_bisec(file_name,product)
        {price_int, ""} = Integer.parse(price)
        {sold_qty_int, ""} = Integer.parse(sold_qty)
        send(current_pid, %{qty: sold_qty_int, price: price_int})
      end)
    end)
    |> Enum.map(fn _ ->
      receive do
        msg -> msg
      after
        5000 -> %{qty: 0, price: 0}
      end
    end)
    |> Enum.chunk_every(10)

    res = Enum.map(chuncked_res, fn chunk ->
      current_pid = self()
      spawn_link(fn ->
        res = Enum.reduce(chunk, %{ca: 0, total_qty: 0}, fn %{qty: sold_qty, price: price}, acc ->
          %{acc|
            ca: acc.ca + sold_qty * price,
            total_qty: acc.total_qty + sold_qty
          }
        end)
        send(current_pid, res)
      end)
    end)
    |> Enum.map(fn _ ->
      receive do
        msg -> msg
      after
        5000 -> %{ca: 0, total_qty: 0}
      end
    end)
    |> Enum.reduce(%{ca: 0, total_qty: 0}, fn %{ca: ca, total_qty: total_qty}, acc ->
      %{acc|
        ca: acc.ca + ca,
        total_qty: acc.total_qty + total_qty
      }
    end)
    res = Map.put(res, :mean_price, res.ca / (if res.total_qty == 0, do: 1, else: res.total_qty))
    conn |> send_resp(200, Poison.encode!(res)) |> halt()
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
    selected_store = Enum.find(1..200,fn store_id->
      Enum.all?(order["products"],fn %{"id"=>prod_id,"quantity"=>q}->
        case MicroDb.HashTable.get("stocks",{store_id,prod_id}) do
          nil-> false
          store_q when store_q >= q-> true
          _-> false
        end
      end)
    end)
    order = Map.put(order,"store_id",selected_store)
    :httpc.request(:post,{'http://localhost:9091/order/new',[],'application/json',Poison.encode!(order)},[],[])
    MicroDb.HashTable.put("orders",order["id"],order)
    conn |> send_resp(200,"") |> halt()
  end

  # payment arrived, get order and process package delivery !
  post "/order/:orderid/payment-callback" do
    {:ok,bin,conn} = read_body(conn)
    %{"transaction_id"=> transaction_id} = Poison.decode!(bin)
    case MicroDb.HashTable.get("orders",orderid) do
      nil-> conn |> send_resp(404,"") |> halt()
      order->
        order = Map.put(order,"transaction_id",transaction_id)
        :httpc.request(:post,{'http://localhost:9091/order/process_delivery',[],'application/json',Poison.encode!(order)},[],[])
        MicroDb.HashTable.put("orders",orderid,order)
        conn |> send_resp(200,"") |> halt()
    end
  end
end
