defmodule ImtOrder.StatsToDb do
  def start do
    {:ok, _} = GenServer.start_link(ImtOrder.StatsToDb.Server, nil, name: __MODULE__)
  end

  def get(product_id) do
    GenServer.call(__MODULE__, {:get, product_id})
  end

  def scan do
    GenServer.cast(__MODULE__, :scan)
  end

  def save do
    GenServer.cast(__MODULE__, :save)
  end

  def dump do
    GenServer.call(__MODULE__, :dump)
  end
end


defmodule ImtOrder.StatsToDb.Server do
  use GenServer
  @scan_interval 5000
  def init(_) do
    #Process.send_after(self(), :scan, 0)
    #Process.send_after(self(), :save, 0)
    {:ok, ImtOrder.StatsToDb.Impl.load_db()}
  end

  def handle_call({:get, product_id}, _from, state) do
    case ImtOrder.StatsToDb.Impl.get_product(state, product_id) do
      nil -> {:reply, {:error, "Product not found"}, state}
      data -> {:reply, {:ok, data}, state}
    end
  end

  def handle_call(:dump, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:update, products}, state) do
    IO.puts("Updating db with products")
    updated_state = ImtOrder.StatsToDb.Impl.update_db(state, products)
    Process.send_after(self(), :save, 0)
    {:noreply, updated_state}
  end

  def handle_cast(:scan, state) do
    ImtOrder.StatsToDb.Impl.scan_files()
    {:noreply, state}
  end

  def handle_cast(:save, state) do
    ImtOrder.StatsToDb.Impl.save_db(state)
    {:noreply, state}
  end

  def handle_info(:scan, state) do
    ImtOrder.StatsToDb.Impl.scan_files()
    Process.send_after(self(), :scan, @scan_interval)
    {:noreply, state}
  end

  def handle_info(:save, state) do
    ImtOrder.StatsToDb.Impl.save_db(state)
    {:noreply, state}
  end
end


defmodule ImtOrder.StatsToDb.Impl do
  def load_db(nb_products \\ 10_000) do
    Enum.reduce(1..nb_products, %{}, fn product_id, acc ->
      case MicroDb.HashTable.get("stats", product_id) do
        nil -> acc
        data -> Map.put(acc, product_id, data)
      end
    end)
  end

  def save_db(state) do
    Enum.each(state, fn {product_id, data} ->
      IO.puts("Saving product #{product_id}")
      MicroDb.HashTable.put("stats", product_id, data)
    end)
  end

  def get_product(state, product_id) do
    Map.get(state, product_id)
  end

  def update_product(state, product_id, data) do
    sales = Map.get(state, product_id, [])
    sales = sales ++ [data]
    Map.put(state, product_id, sales)
  end

  def update_db(state, message) do
    Enum.reduce(message, state, fn {product_id, data}, acc ->
      update_product(acc, product_id, data)
    end)
  end

  def scan_files() do
    Path.wildcard("data/stat_*")
    |> Enum.map(fn file_name ->
      current_pid = self()
      spawn_link(fn ->
        products =
          File.stream!(file_name)
          |> Enum.reduce(%{}, fn line, acc ->
            case line |> String.trim_trailing("\n") |> String.split(",") do
              [product_id, qty, price] ->
                update_product(acc, String.to_integer(product_id), %{qty: String.to_integer(qty), price: String.to_integer(price)})
              _ -> acc
            end
          end)
          GenServer.cast(current_pid, {:update, products})
      end)
    end)
  end
end
