defmodule ImtOrder.OrderTransactor do
  @moduledoc """
  Provides a public API for managing order transactions.

  This module defines functions to start an order transactor, create a new order, and process payments.
  """

  @timeout 20_000

  @doc """
  Starts a transactor process for the given `order_id`.

  ## Parameters
  - `order_id`: The unique identifier for the order.

  ## Returns
  - `{:ok, pid}` if the transactor is started successfully.
  - `{:error, reason}` if there is an issue starting the transactor.
  """
  def start(order_id) do
    ImtOrder.OrderTransactor.Supervisor.start_transactor(order_id)
  end

  @doc """
  Sends a synchronous call to create a new order on the specified node.

  ## Parameters
  - `node`: The target node where the GenServer is located.
  - `order`: The order details as a map.

  ## Returns
  - `:ok` if the order is created successfully.
  - `{:error, reason}` if the order creation fails.
  """
  def new(node, order) do
    GenServer.call({:"#{order["id"]}_transactor", node}, {:new, order}, @timeout)
  end

  @doc """
  Sends a synchronous call to process a payment for the specified order.

  ## Parameters
  - `node`: The target node where the GenServer is located.
  - `order_id`: The unique identifier of the order.
  - `transaction_id`: The transaction identifier.

  ## Returns
  - `:ok` if the payment is processed successfully.
  - `{:error, reason}` if the payment processing fails.
  """
  def payment(node, order_id, transaction_id) do
    GenServer.call({:"#{order_id}_transactor", node}, {:payment, %{"transaction_id" => transaction_id}}, @timeout)
  end
end

defmodule ImtOrder.OrderTransactor.Supervisor do
  @moduledoc """
  DynamicSupervisor responsible for managing `OrderTransactor.Server` processes.

  This module handles starting, supervising, and listing the transactor processes.
  """

  use DynamicSupervisor

  @doc """
  Starts a new transactor process for the given `order_id`.

  ## Parameters
  - `order_id`: The unique identifier for the order.

  ## Returns
  - `{:ok, pid}` if the transactor is started successfully.
  - `{:error, reason}` if starting the transactor fails.
  """
  def start_transactor(order_id) do
    case DynamicSupervisor.start_child(__MODULE__, {ImtOrder.OrderTransactor.Server, order_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists the names and PIDs of all transactors supervised by this module.
  """
  def list_children_names do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.each(fn {_, pid, :worker, [ImtOrder.OrderTransactor.Server]} ->
      transactor_name = Process.info(pid, :registered_name) |> elem(1)
      IO.puts("OrderTransactor: #{inspect(transactor_name)} with PID: #{inspect(pid)}")
    end)
  end

  @doc """
  Starts the DynamicSupervisor with the given `init_arg`.

  ## Returns
  - `{:ok, pid}` if the supervisor is started successfully.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Initializes the DynamicSupervisor with a one-for-one strategy.
  """
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end

defmodule ImtOrder.OrderTransactor.Server do
  @moduledoc """
  GenServer that handles the lifecycle and operations for a specific order.

  The server processes order creation, payment, and delivery with error handling and state management.
  """

  use GenServer, restart: :transient
  require Logger
  alias ImtOrder.OrderTransactor.Impl

  @retires 3

  @doc """
  Starts the GenServer for the given `order_id`.

  ## Returns
  - `{:ok, pid}` if the server is started successfully.
  """
  def start_link(order_id) do
    GenServer.start_link(__MODULE__, order_id, name: :"#{order_id}_transactor")
  end

  @doc """
  Initializes the GenServer state with the order ID.
  """
  def init(order_id) do
    Logger.info("OrderTransactor: Starting transactor for order #{order_id}")
    {:ok, %{id: order_id, order: nil}}
  end

  @doc """
  Handles the creation of a new order.

  ## Returns
  - `:ok` if the order is created successfully.
  - `{:error, reason}` if the order has already been processed.
  """
  def handle_call({:new, order}, _from, %{id: order_id, order: nil}) do
    order = Impl.process_order(order)
    {:reply, :ok, %{id: order_id, order: order}}
  end

  def handle_call({:new, _}, _from, state) do
    {:reply, {:error, "Order already processed"}, state}
  end

  @doc """
  Handles payment processing for an order.

  ## Returns
  - `:ok` if the payment is processed successfully.
  - `{:error, reason}` if the order is not found.
  """
  def handle_call({:payment, %{"transaction_id" => transaction_id}}, _from, %{id: order_id, order: order_state}) when not is_nil(order_state) do
    {:ok, _, order} = Impl.process_payments(order_id, transaction_id)
    Logger.info("OrderTransactor: Order #{order_id} payment received")
    {:reply, :ok, %{id: order_id, order: order}}
  end

  def handle_call({:payment, _}, _from, %{id: order_id, order: nil}) do
    Logger.warning("OrderTransactor: Order #{order_id} payment received without order")
    {:reply, {:error, "Order #{order_id} not found"}, %{id: order_id, order: nil}}
  end

  @doc """
  Processes order delivery asynchronously with retries.

  ## Returns
  - `{:stop, :normal, state}` when processing completes, regardless of success or failure.
  """
  def handle_cast(:process_delivery, %{id: order_id, order: order}) do
    case Impl.process_delivery(order, @retires) do
      {:ok, _} ->
        Logger.info("OrderTransactor: Order #{order_id} process delivery successful")
        {:stop, :normal, %{id: order_id, order: order}}
      {:error, _} ->
        Logger.warning("OrderTransactor: Order #{order_id} process delivery failed")
        {:stop, :normal, %{id: order_id, order: order}}
    end
  end

  @doc """
  Ensures the order state is saved upon termination.
  """
  def terminate(_, %{id: order_id, order: order}) do
    MicroDb.HashTable.put("orders", order_id, order)
  end
end

defmodule ImtOrder.OrderTransactor.Impl do
  @moduledoc """
  Implements the business logic for order processing, payments, and deliveries.

  This module provides helper functions used by `OrderTransactor.Server` to handle the lifecycle of an order.
  """

  @doc """
  Processes the creation of an order.

  This includes:
  - Selecting a store based on product availability.
  - Sending an HTTP request to notify an external service about the order.
  - Storing the order details in a local database.

  ## Parameters
  - `order`: A map containing the order details.

  ## Returns
  - `{:ok, message, order}` on success.
  """
  @url "http://localhost:9091"
  def process_order(order) do
    selected_store = Enum.find(1..200, fn store_id ->
      Enum.all?(order["products"], fn %{"id" => prod_id, "quantity" => q} ->
        case MicroDb.HashTable.get("stocks", {store_id, prod_id}) do
          nil -> false
          store_q when store_q >= q -> true
          _ -> false
        end
      end)
    end)

    order = Map.put(order, "store_id", selected_store)

    :httpc.request(
      :post,
      {'#{@url}/order/new', [], 'application/json', Poison.encode!(order)},
      [],
      []
    )

    MicroDb.HashTable.put("orders", order["id"], order)

    {:ok, "Order created", order}
  end

  @doc """
  Processes payment for an order.

  This includes:
  - Updating the order with the `transaction_id`.
  - Triggering the delivery process asynchronously.

  ## Parameters
  - `order_id`: The unique identifier for the order.
  - `transaction_id`: The identifier for the payment transaction.

  ## Returns
  - `{:ok, message, order}` on success.
  """
  def process_payments(order_id, transaction_id) do
    order = MicroDb.HashTable.get("orders", order_id)
    order = Map.put(order, "transaction_id", transaction_id)
    MicroDb.HashTable.put("orders", order_id, order)

    # Trigger delivery asynchronously
    GenServer.cast(:"#{order_id}_transactor", :process_delivery)

    {:ok, "Order payment received", order}
  end

  @doc """
  Handles the delivery process with retries and exponential backoff.

  This function makes repeated HTTP requests to process the delivery,
  applying a delay between attempts.

  ## Parameters
  - `order`: A map containing the order details.
  - `max_retries`: The maximum number of retries allowed.

  ## Returns
  - `{:ok, message}` on successful delivery.
  - `{:error, message}` if all attempts fail.
  """
  def process_delivery(order, max_retries) do
    Enum.reduce_while(1..max_retries, :error, fn attempt, _acc ->
      case :httpc.request(
             :post,
             {'#{@url}/order/process_delivery', [], 'application/json', Poison.encode!(order)},
             [],
             []
           ) do
        {:ok, {{_, 200, _}, _, _}} ->
          {:halt, {:ok, "Order process delivery request sent"}}

        _ ->
          # Calculate exponential backoff delay
          delay = :math.pow(2, attempt - 1) * 100
          :timer.sleep(trunc(delay))

          # Halt on the last attempt, otherwise continue retrying
          if attempt == max_retries do
            {:halt, {:error, "Order process delivery request failed"}}
          else
            {:cont, :error}
          end
      end
    end)
  end
end
