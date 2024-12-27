defmodule ImtOrder.OrderTransactor do
  @moduledoc """
  Provides a public API for managing order transactions.

  This module defines functions to start an order transactor, create a new order, and process payments.
  """

  @timeout 30_000

  @doc """
  Starts a transactor process for the given `order_id`.

  ## Parameters
  - `order_id`: The unique identifier for the order.

  ## Returns
  - `{:ok, pid}` if the transactor is started successfully.
  - `{:error, reason}` if there is an issue starting the transactor.
  """
  def start(order_id, replicas) do
    ImtOrder.OrderTransactor.Supervisor.start_transactor(order_id, replicas)
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
  def start_transactor(order_id, replicas) do
    case DynamicSupervisor.start_child(__MODULE__, {ImtOrder.OrderTransactor.Server, {order_id, replicas}}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
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

  @timeout 10_000

  @doc """
  Starts the GenServer for the given `order_id`.

  ## Returns
  - `{:ok, pid}` if the server is started successfully.
  """
  def start_link({order_id, replicas}) do
    GenServer.start_link(__MODULE__, {order_id, replicas}, name: :"#{order_id}_transactor")
  end

  @doc """
  Initializes the GenServer state with the order ID.
  """
  def init({order_id, replicas}) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Starting transactor for order #{order_id}")

    Enum.each(replicas, fn replica ->
      if replica != Node.self() do
        Node.monitor(replica, true)
      end
    end)

    {:ok, %{id: order_id, order: nil, replicas: replicas}}
  end

  @doc """
  Handles the creation of a new order.

  ## Returns
  - `:ok` if the order is created successfully.
  - `{:error, reason}` if the order has already been processed.
  """
  def handle_call({:new, order}, _from, %{order: nil} = state) do
    state = Map.put(state, :order, order)
    {:reply, :ok, state, {:continue, :process_order}}
  end

  def handle_call({:new, order}, _from, state) do
    order = Map.merge(state.order, order)
    state = Map.put(state, :order, order)
    {:reply, :ok, state, {:continue, :process_order}}
  end

  @doc """
  Handles payment processing for an order.

  ## Returns
  - `:ok` if the payment is processed successfully.
  - `{:error, reason}` if the order is not found.
  """
  def handle_call({:payment, %{"transaction_id" => transaction_id}}, _from, %{order: nil} = state) do
    Logger.warning("[OrderTransactor] Node #{Node.self}: Order #{state[:id]} payment received without order")
    state = Map.put(state, :order, %{"transaction_id" => transaction_id})
    {:reply, :ok, state, {:continue, :sync}}
  end

  def handle_call({:payment, %{"transaction_id" => transaction_id}}, _from, state) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state[:id]} payment received")
    {:reply, :ok, state, {:continue, {:process_payment, transaction_id}}}
  end

  def handle_continue(:process_order, %{order: order} = state) do
    {:ok, order} = Impl.process_order(order)
    case Map.get(order, "transaction_id") do
      nil ->
        state = Map.put(state, :order, order)
        {:noreply, state, {:continue, :sync}}
      _ ->
        Logger.warning("[OrderTransactor] Node #{Node.self}: Order #{state[:id]} transaction already processed")
        {:noreply, state, {:continue, :process_delivery}}
    end
  end

  def handle_continue({:process_payment, transaction_id}, %{order: order} = state) do
    {:ok, order} = Impl.process_payments(order, transaction_id)
    state = Map.put(state, :order, order)
    {:noreply, state, {:continue, :process_delivery}}
  end

  @doc """
  Processes order delivery asynchronously with retries.

  ## Returns
  - `{:stop, :normal, state}` when processing completes, regardless of success or failure.
  """
  def handle_continue(:process_delivery, %{order: order} = state) do
    case Impl.process_delivery(order, @retires) do
      {:ok, _} ->
        Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state[:id]} process delivery successful")
        {:noreply, state, @timeout}
        #{:stop, :normal, %{id: order_id, order: order}}
      {:error, _} ->
        Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state[:id]} process delivery failed")
        {:noreply, state, {:continue, :process_delivery}}
        #{:stop, :normal, %{id: order_id, order: order}}
    end
  end

  def handle_continue(:sync, %{order: order, replicas: replicas} = state) do
    Impl.sync_nodes(order, replicas)
    {:noreply, state}
  end

  def handle_cast({:sync, order}, state) do
    state = Map.put(state, :order, order)
    Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state.id} synchronized")
    {:noreply, state}
  end

  def handle_cast(:shutdown, state) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state.id} shutting down")
    {:stop, :normal, state}
  end

  def handle_info(:timeout, state) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state.id} processed successfully")
    {:stop, :normal, state}
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Node #{node} is up")
    state = Impl.update_replicas(state, node, :add)
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Node #{node} is up")
    state = Impl.update_replicas(state, node, :remove)
    {:noreply, state}
  end

  @doc """
  Ensures the order state is saved upon termination.
  """
  def terminate(_, %{id: order_id, order: order, replicas: replicas}) do
    Impl.sync_nodes(order, replicas)
    case Impl.is_leader(replicas) do
      true ->
        Impl.shutdown_replicas(replicas, order_id)
        Logger.info("[OrderTransactor] Node #{Node.self}: Order #{order_id} is leader, writing to database")
        MicroDb.HashTable.put("orders", order_id, order)
      false ->
        Logger.info("[OrderTransactor] Node #{Node.self}: Order #{order_id} not leader, skipping write")
    end
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

    # Test with less writes to the database
    #MicroDb.HashTable.put("orders", order["id"], order)

    {:ok, order}
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
  def process_payments(order, transaction_id) do
    order = order |> Map.put("transaction_id", transaction_id)
    # Test with less writes to the database
    #MicroDb.HashTable.put("orders", order["id"], order)
    {:ok, order}
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
          {:halt, {:ok, "Order #{order["id"]} process delivery request sent"}}

        _ ->
          # Calculate exponential backoff delay
          delay = :math.pow(2, attempt - 1) * 100
          :timer.sleep(trunc(delay))

          # Halt on the last attempt, otherwise continue retrying
          if attempt == max_retries do
            {:halt, {:error, "Order #{order["id"]} process delivery request failed"}}
          else
            {:cont, :error}
          end
      end
    end)
  end

  def sync_nodes(order, replicas) do
    nodes = replicas -- [Node.self]
    Enum.each(nodes, fn node ->
      GenServer.cast({:"#{order["id"]}_transactor", node}, {:sync, order})
    end)
  end

  def is_leader(replicas) do
    case Enum.find(replicas, &Node.ping(&1) == :pong) do
      nil ->
        false
      leader ->
        Node.self() == leader
    end
  end

  def shutdown_replicas(replicas, order_id) do
    Enum.each(replicas, fn replica ->
      if replica != Node.self() do
        GenServer.cast({:"#{order_id}_transactor", replica}, :shutdown)
      end
    end)
  end

  def update_replicas(state, node, :add) do
    %{state | replicas: Enum.uniq([node | state.replicas])}
  end

  def update_replicas(state, node, :remove) do
    %{state | replicas: Enum.filter(state.replicas, &(&1 != node))}
  end
end
