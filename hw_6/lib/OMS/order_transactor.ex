defmodule ImtOrder.OrderTransactor do
  @moduledoc """
  Provides a public API for managing order transactions.

  This module defines functions to start an order transactor, create a new order, and process payments.
  """

  @timeout 30_000


  @doc """
  Starts a transactor process for the given `order_id` on the current node.

  ## Parameters
  - `order_id`: The unique identifier for the order.
  - `replicas`: A list of nodes for replication.

  ## Returns
  - `{:ok, pid}` if the transactor is started successfully.
  - `{:error, reason}` on failure.
  """
  def start(order_id, replicas) do
    ImtOrder.OrderTransactor.Supervisor.start_transactor(order_id, replicas)
  end

  @doc """
  Starts a transactor process for the given `order_id` on a remote node.

  ## Parameters
  - `node`: The target remote node.
  - `order_id`: The unique identifier for the order.
  - `replicas`: A list of nodes for replication.

  ## Returns
  - `{:ok, pid}` if the transactor is started successfully.
  - `{:error, reason}` on failure.
  """
  def start(node, order_id, replicas) do
    :rpc.call(node, ImtOrder.OrderTransactor.Supervisor, :start_transactor, [order_id, replicas], @timeout)
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
  - `replicas`: A list of nodes for replication.

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
  GenServer that manages the lifecycle and operations of a specific order.

  Responsibilities:
  - Handling order creation, payment processing, and delivery.
  - Managing state synchronization across replicas.
  - Monitoring node up/down events.
  """

  use GenServer, restart: :transient
  require Logger
  alias ImtOrder.OrderDispatcher
  alias ImtOrder.OrderTransactor.Impl

  @retires 3

  @timeout 10_000

  @doc """
  Starts the GenServer for the given `order_id` and replicas.

  ## Parameters
  - `{order_id, replicas}`: A tuple containing the order ID and the list of replicas.

  ## Returns
  - `{:ok, pid}` if the server starts successfully.
  """
  def start_link({order_id, replicas}) do
    GenServer.start_link(__MODULE__, {order_id, replicas}, name: :"#{order_id}_transactor")
  end

  @doc """
  Initializes the GenServer state with the order ID and replicas.

  - Monitors all replica nodes except the local node.
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

  ## Parameters
  - `order`: A map containing the order details.

  ## Returns
  - `:ok` on success.
  - Updates the state with the new order details.
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

  @doc """
  Handles the continuation of order processing after the `:new` event.

  - Calls `Impl.process_order/1` to perform order-specific operations such as selecting a store and saving the order.
  - Checks whether a transaction ID exists in the processed order.
    - If no transaction ID is present, the order is saved to the state, and synchronization is triggered.
    - If a transaction ID already exists, it proceeds directly to the delivery process.

  ## Parameters
  - `:process_order`: The continuation trigger for order processing.
  - `state`: The current GenServer state, which includes the `order`.

  ## Returns
  - `{:noreply, state, {:continue, :sync}}` to synchronize the state across replicas if no transaction ID is found.
  - `{:noreply, state, {:continue, :process_delivery}}` to proceed with the delivery process if a transaction ID is already present.
  """
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

  @doc """
  Handles the continuation of payment processing after a `:payment` event.

  - Calls `Impl.process_payments/2` to process the payment for the order, including updating the order with the transaction ID.
  - Updates the state with the processed order.
  - Triggers the next step, which is the delivery process.

  ## Parameters
  - `{:process_payment, transaction_id}`: The continuation trigger for payment processing, containing the transaction ID.
  - `state`: The current GenServer state, which includes the `order`.

  ## Returns
  - `{:noreply, state, {:continue, :process_delivery}}` to proceed with the delivery process.
  """
  def handle_continue({:process_payment, transaction_id}, %{order: order} = state) do
    {:ok, order} = Impl.process_payments(order, transaction_id)
    state = Map.put(state, :order, order)
    {:noreply, state, {:continue, :process_delivery}}
  end

  @doc """
  Processes the delivery of an order asynchronously with retries.

  - Calls `Impl.process_delivery/2` to perform the delivery with a retry mechanism.
  - Logs the outcome of the delivery attempt.
  - If delivery succeeds, the state transitions to a timeout-based stop.
  - If delivery fails, it continues the delivery process for retry.

  ## Parameters
  - `:process_delivery`: The continuation trigger for delivery processing.
  - `state`: The current GenServer state, including the `order`.

  ## Returns
  - `{:noreply, state, @timeout}` if delivery is successful, allowing the process to terminate naturally.
  - `{:noreply, state, {:continue, :process_delivery}}` if delivery fails, triggering another retry.
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

  @doc """
  Synchronizes the state of an order across replicas.

  - Calls `Impl.sync_nodes/2` to update all replicas with the current order state.

  ## Parameters
  - `:sync`: The continuation trigger for synchronization.
  - `state`: The current GenServer state, including the `order` and `replicas`.

  ## Returns
  - `{:noreply, state}` after synchronization is completed.
  """
  def handle_continue(:sync, %{order: order, replicas: replicas} = state) do
    Impl.sync_nodes(order, replicas)
    {:noreply, state}
  end

  @doc """
  Handles a cast message to synchronize the order state.

  - Updates the local state with the synchronized order.
  - Logs the synchronization event.

  ## Parameters
  - `{sync, order}`: The synchronization data containing the order details.
  - `state`: The current GenServer state.

  ## Returns
  - `{:noreply, state}` after updating the state with the synchronized order.
  """
  def handle_cast({:sync, order}, state) do
    state = Map.put(state, :order, order)
    Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state.id} synchronized")
    {:noreply, state}
  end

  @doc """
  Handles a cast message to shut down the process.

  - Logs the shutdown event.
  - Stops the GenServer gracefully.

  ## Parameters
  - `:shutdown`: The shutdown command.
  - `state`: The current GenServer state.

  ## Returns
  - `{:stop, :normal, state}` to terminate the GenServer process.
  """
  def handle_cast(:shutdown, state) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state.id} shutting down")
    {:stop, :normal, state}
  end


  @doc """
  Handles a timeout event.

  - Logs that the order has been processed successfully.
  - Stops the GenServer process gracefully.
  - Allows all callbacks to run before termination.

  ## Parameters
  - `:timeout`: The timeout trigger.
  - `state`: The current GenServer state.

  ## Returns
  - `{:stop, :normal, state}` to terminate the process.
  """
  def handle_info(:timeout, state) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Order #{state.id} processed successfully")
    {:stop, :normal, state}
  end

  @doc """
  Handles a `:nodeup` event to update the replicas list.

  - Adds the node to the list of replicas.
  - Logs the node-up event.

  ## Parameters
  - `{:nodeup, node}`: The node-up event with the node identifier.
  - `state`: The current GenServer state.

  ## Returns
  - `{:noreply, state}` with the updated replicas.
  """
  def handle_info({:nodeup, node}, state) do
    Logger.info("[OrderTransactor] Node #{Node.self}: Node #{node} is up")
    state = Impl.update_replicas(state, node, :add)
    {:noreply, state}
  end

  @doc """
  Handles a `:nodedown` event to update the replicas list.

  - Removes the node from the list of replicas.
  - Logs the node-down event.

  ## Parameters
  - `{:nodedown, node}`: The node-down event with the node identifier.
  - `state`: The current GenServer state.

  ## Returns
  - `{:noreply, state}` with the updated replicas.
  """
  def handle_info({:nodedown, node}, state) do
    Logger.error("[OrderTransactor] Node #{Node.self}: Node #{node} is down")
    state = Impl.update_replicas(state, node, :remove)
    {:noreply, state}
  end

  @doc """
  Ensures the order state is saved and replicas are cleaned up upon termination.

  - Synchronizes the state with replicas.
  - If the current node is the leader, it writes the order to the database and deletes it from the dispatcher.
  - If the current node is not the leader, skips writing to the database.
  """
  def terminate(_, %{id: order_id, order: order, replicas: replicas}) do
    Impl.sync_nodes(order, replicas)
    case Impl.is_leader(replicas) do
      true ->
        Impl.shutdown_replicas(replicas, order_id)
        Logger.info("[OrderTransactor] Node #{Node.self}: Order #{order_id} is leader, writing to database")
        MicroDb.HashTable.put("orders", order_id, order)
        OrderDispatcher.delete(order_id)
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

  # URL of the WMS service
  @url "http://localhost:9091"

  @doc """
  Processes the creation of an order.

  - Determines the store with sufficient stock for the requested products.
  - Sends an HTTP request to notify an external service about the new order.
  - Updates the order details with the selected store.

  ## Parameters
  - `order`: A map containing the order details, including product IDs and quantities.

  ## Returns
  - `{:ok, order}` on success, with the updated order containing the selected store.
  """
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

  - Updates the order with the provided transaction ID.
  - Prepares the order for the delivery process.

  ## Parameters
  - `order`: The current order details as a map.
  - `transaction_id`: The identifier for the payment transaction.

  ## Returns
  - `{:ok, order}` with the updated order containing the transaction ID.
  """
  def process_payments(order, transaction_id) do
    order = order |> Map.put("transaction_id", transaction_id)
    # Test with less writes to the database
    #MicroDb.HashTable.put("orders", order["id"], order)
    {:ok, order}
  end

  @doc """
  Handles the delivery process with retries and exponential backoff.

  - Attempts to send an HTTP request to process the delivery.
  - Retries on failure, applying exponential backoff between attempts.

  ## Parameters
  - `order`: A map containing the order details.
  - `max_retries`: The maximum number of retry attempts.

  ## Returns
  - `{:ok, message}` if the delivery is successful.
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

  @doc """
  Synchronizes the order state across all replicas.

  - Sends the current order details to all replicas except the local node.

  ## Parameters
  - `order`: A map containing the current order details.
  - `replicas`: A list of nodes participating in the replication.
  """
  def sync_nodes(order, replicas) do
    nodes = replicas -- [Node.self]
    Enum.each(nodes, fn node ->
      GenServer.cast({:"#{order["id"]}_transactor", node}, {:sync, order})
    end)
  end

  @doc """
  Determines if the current node is the leader among the replicas.

  - The leader is the first reachable node in the list of replicas.

  ## Parameters
  - `replicas`: A list of nodes participating in the replication.

  ## Returns
  - `true` if the current node is the leader.
  - `false` otherwise.
  """
  def is_leader(replicas) do
    case Enum.find(replicas, &Node.ping(&1) == :pong) do
      nil ->
        false
      leader ->
        Node.self() == leader
    end
  end

  @doc """
  Shuts down all replicas for a specific order, except the local node.

  - Sends a `:shutdown` message to all other replicas.

  ## Parameters
  - `replicas`: A list of nodes participating in the replication.
  - `order_id`: The unique identifier of the order.
  """
  def shutdown_replicas(replicas, order_id) do
    Enum.each(replicas, fn replica ->
      if replica != Node.self() do
        GenServer.cast({:"#{order_id}_transactor", replica}, :shutdown)
      end
    end)
  end

  @doc """
  Updates the list of replicas in the state.

  - Ensures the node is not duplicated in the replicas list.

  ## Parameters
  - `state`: The current state containing the `replicas` list.
  - `node`: The node to add or remove from the list.
  - `:add` or `:remove`: The operation to perform.

  ## Returns
  - Updated state with the node added to the `replicas` list.
  """
  def update_replicas(state, node, :add) do
    %{state | replicas: Enum.uniq([node | state.replicas])}
  end

  def update_replicas(state, node, :remove) do
    %{state | replicas: Enum.filter(state.replicas, &(&1 != node))}
  end
end
