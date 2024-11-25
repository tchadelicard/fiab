defmodule ImtOrder.StatsToDb do
  @moduledoc """
  The `ImtOrder.StatsToDb` module provides a public API to interact with the GenServer
  responsible for handling product statistics and saving them to the database.

  This module offers functions to start the server, fetch product stats, initiate file scans,
  and trigger saves of the current state.
  """

  @doc """
  Starts the `ImtOrder.StatsToDb.Server` GenServer.

  This function should be called to initialize the server and start handling requests.
  """
  def start do
    {:ok, _} = GenServer.start_link(ImtOrder.StatsToDb.Server, nil, name: ImtOrder.StatsToDb.Server)
  end

  @doc """
  Fetches the statistics for a product identified by `product_id`.

  This function sends a synchronous request to the GenServer and waits for a reply
  containing the product's statistics or an error message if the product is not found.

  ## Examples
      iex> ImtOrder.StatsToDb.get(1)
      {:ok, %{qty: 100, price: 50}}

      iex> ImtOrder.StatsToDb.get(9999)
      {:error, "Product not found"}
  """
  def get(product_id) do
    GenServer.call(ImtOrder.StatsToDb.Server, {:get, product_id})
  end

  @doc """
  Triggers a scan for new product statistics by sending an asynchronous cast message
  to the GenServer. This function does not wait for a reply.

  The server will scan files for new product stats and update the internal state.
  """
  def scan do
    GenServer.cast(ImtOrder.StatsToDb.Server, :scan)
  end

  @doc """
  Triggers the saving of the current state (product statistics) to the database.

  This function sends an asynchronous cast message to the GenServer to persist the data.
  """
  def save do
    GenServer.cast(ImtOrder.StatsToDb.Server, :save)
  end

  @doc """
  Dumps the entire current state of the GenServer, returning all product statistics.

  This is useful for debugging or logging purposes, allowing inspection of the full state.
  """
  def dump do
    GenServer.call(ImtOrder.StatsToDb.Server, :dump)
  end
end


defmodule ImtOrder.StatsToDb.Server do
  use GenServer

  @moduledoc """
  The `ImtOrder.StatsToDb.Server` is a GenServer responsible for maintaining product statistics
  in memory and periodically saving them to the database. It handles incoming requests to get,
  update, scan, and save product statistics.

  The server operates with two key background tasks:
    - Scanning files for new product stats at regular intervals.
    - Saving the current state to the database at regular intervals.
  """

  @scan_interval 5000    # Interval for scanning files (5 seconds)
  @save_interval 60000   # Interval for saving state to the database (10 seconds)

  @doc """
  Initializes the GenServer state by loading the current product statistics from the database.

  Additionally, it schedules periodic scans and saves using `Process.send_after/3`.
  """
  @impl true
  def init(_) do
    Process.send_after(self(), :scan, 0)
    #Process.send_after(self(), :save, @save_interval)
    {:ok, ImtOrder.StatsToDb.Impl.load_db()}
  end

  @doc """
  Starts the `ImtOrder.StatsToDb.Server` GenServer.

  This is typically called internally when starting the application or server.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Handles a synchronous `get` request, retrieving the product statistics for a given `product_id`.

  If the product is found, it replies with `{:ok, data}`; otherwise, it replies with an error.
  """
  def handle_call({:get, product_id}, _from, state) do
    case ImtOrder.StatsToDb.Impl.get_product(state, product_id) do
      [] -> {:reply, {:error, "Product not found"}, state}
      data -> {:reply, {:ok, data}, state}
    end
  end

  @doc """
  Handles a synchronous `dump` request to return the entire state of the GenServer.
  This is useful for debugging or logging purposes.
  """
  def handle_call(:dump, _from, state) do
    {:reply, state, state}
  end

  @doc """
  Handles an asynchronous `update` cast request to update the current product stats
  with new data from the message.

  This updates the internal state of the GenServer.
  """
  def handle_cast({:update, products}, state) do
    updated_state = ImtOrder.StatsToDb.Impl.update_db(state, products)
    {:noreply, updated_state}
  end

  @doc """
  Handles an asynchronous `scan` cast request to initiate a file scan for new product data.

  The server calls the `scan_files/0` function from the implementation module to update
  product stats.
  """
  def handle_cast(:scan, state) do
    ImtOrder.StatsToDb.Impl.scan_files()
    {:noreply, state}
  end

  @doc """
  Handles an asynchronous `save` cast request to persist the current state to the database.

  After saving, the next save is scheduled according to the defined `@save_interval`.
  """
  def handle_cast(:save, state) do
    ImtOrder.StatsToDb.Impl.save_db(state)
    Process.send_after(self(), :save, @save_interval)
    {:noreply, state}
  end

  @doc """
  Handles the periodic `scan` message to scan files for new product data.

  The server scans files, updates the product stats, and schedules the next scan
  using the `@scan_interval`.
  """
  def handle_info(:scan, state) do
    ImtOrder.StatsToDb.Impl.scan_files()
    Process.send_after(self(), :scan, @scan_interval)
    {:noreply, state}
  end

  @doc """
  Handles the periodic `save` message to save the current product statistics to the database.
  """
  def handle_info(:save, state) do
    ImtOrder.StatsToDb.Impl.save_db(state)
    {:noreply, state}
  end

  def terminate(_, state) do
    ImtOrder.StatsToDb.Impl.save_db(state)
    :ok
  end
end


defmodule ImtOrder.StatsToDb.Impl do
  @moduledoc """
  The `ImtOrder.StatsToDb.Impl` module contains the implementation for handling product statistics,
  including loading, saving, and updating product data in the database.

  This module is responsible for scanning files, updating the in-memory state, and
  persisting the data.
  """

  @doc """
  Loads product statistics from the database for a specified number of products.

  By default, it loads stats for 10,000 products but this can be configured by passing
  a different `nb_products` value.
  """
  def load_db(nb_products \\ 40_000) do
    Enum.reduce(1..nb_products, %{}, fn product_id, acc ->
      case MicroDb.HashTable.get("stats", product_id) do
        nil -> acc
        data -> Map.put(acc, product_id, data)
      end
    end)
  end

  @doc """
  Saves the current state (product statistics) asynchronously to the database.

  Each product's statistics are saved using `MicroDb.HashTable.put/2`.
  """
  def save_db(state) do
    spawn_link(fn ->
      Enum.each(state, fn {product_id, data} ->
        spawn_link(fn ->
          MicroDb.HashTable.put("stats", product_id, data)
        end)
      end)
    end)
  end

  @doc """
  Retrieves the statistics for a given `product_id` from the current state.

  Returns an empty list if the product is not found.
  """
  def get_product(state, product_id) do
    Map.get(state, product_id, [])
  end

  @doc """
  Updates the sales data for a specific `product_id` by appending new data to the existing sales.

  Returns the updated state.
  """
  def update_product(state, product_id, data) do
    sales = Map.get(state, product_id, [])
    updated_sales = sales ++ [data]
    Map.put(state, product_id, updated_sales)
  end

  @doc """
  Updates the database state with a list of products and their respective data.

  Each product is updated using `update_product/3`.
  """
  def update_db(state, message) do
    Enum.reduce(message, state, fn {product_id, data}, acc ->
      update_product(acc, product_id, data)
    end)
  end

  @doc """
  Scans files for product data and updates the state with the extracted information.

  Files are deleted after processing to avoid duplication of data.
  """
  def scan_files() do
    Path.wildcard("data/stat_*")
    |> Enum.map(fn file_name ->
      current_pid = self()
      spawn_link(fn ->
        products =
          File.stream!(file_name)
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(String.trim_trailing(line, "\n"), ",") do
              [product_id, qty, price] ->
                Map.put(acc, String.to_integer(product_id), %{qty: String.to_integer(qty), price: String.to_integer(price)})
              _ -> acc
            end
          end)
        File.rm!(file_name)
        GenServer.cast(current_pid, {:update, products})
      end)
    end)
  end
end
