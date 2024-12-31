defmodule ImtOrder.OrderDispatcher do
  @moduledoc """
  Provides a public API for managing the dispatching of order transactors.

  This module interacts with the `OrderDispatcher.Server` to manage the lifecycle of transactors
  (e.g., starting, synchronizing, and deleting) in a distributed environment.
  """
  @timeout 30_000

  @doc """
  Starts a transactor for a given `order_id`.

  Delegates the call to `OrderDispatcher.Server`.

  ## Parameters
  - `order_id`: The unique identifier for the order.

  ## Returns
  - `{:ok, node}` if successful.
  - `{:error, reason}` on failure.
  """
  def start(order_id) do
    GenServer.call(ImtOrder.OrderDispatcher.Server, {:start, order_id}, @timeout)
  end

  @doc """
  Synchronizes transactors with a remote node.

  ## Parameters
  - `node`: The remote node to synchronize with.
  - `transactors`: The transactor data to sync.
  """
  def sync(node, transactors) do
    GenServer.cast({ImtOrder.OrderDispatcher.Server, node}, {:sync, transactors})
  end

  @doc """
  Deletes a transactor for a given `order_id`.

  ## Parameters
  - `order_id`: The unique identifier of the order whose transactor should be deleted.
  """
  def delete(order_id) do
    GenServer.cast(ImtOrder.OrderDispatcher.Server, {:delete, order_id})
  end
end

defmodule ImtOrder.OrderDispatcher.Server do
  @moduledoc """
  Manages the state and dispatching of order transactors across nodes.

  This `GenServer` is responsible for:
  - Maintaining the `HashRing` of nodes.
  - Managing transactor assignments and synchronization.
  - Handling node up/down events to maintain system consistency.
  """

  use GenServer
  alias ImtOrder.OrderDispatcher.Impl
  require Logger

  @doc """
  Starts the `OrderDispatcher.Server` GenServer.

  ## Returns
  - `{:ok, pid}` if the server starts successfully.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Initializes the dispatcher state and sets up node monitoring.

  - Initializes the `HashRing`.
  - Monitors all nodes in the ring.

  ## Returns
  - `{:ok, state}` with the initialized state.
  """
  def init(_) do
    state = %{ring: nil, transactors: %{}} |> Impl.init_ring()

    # Monitor all nodes in the ring
    HashRing.nodes(state[:ring])
    |> Enum.reject(&(&1 == Node.self()))
    |> Enum.each(fn dispatcher ->
      Node.monitor(dispatcher, true)
    end)

    {:ok, state}
  end

  @doc """
  Handles `:nodeup` events to add a node to the ring.
  """
  def handle_info({:nodeup, node}, state) do
    Logger.info("[OrderDispatcher] Node #{Node.self}: Node #{node} is up")
    state = Impl.update_ring(state, node, :add)
    {:noreply, state}
  end

  @doc """
  Handles `:nodedown` events to remove a node from the ring.
  """
  def handle_info({:nodedown, node}, state) do
    Logger.error("[OrderDispatcher] Node #{Node.self}: Node #{node} is down")
    state = Impl.update_ring(state, node, :remove)
    {:noreply, state}
  end

  @doc """
  Starts a transactor for an order by delegating to `Impl.start`.

  ## Returns
  - `{:reply, {:ok, node}, updated_state}` on success.
  - `{:reply, {:error, reason}, updated_state}` on failure.
  """
  def handle_call({:start, order_id}, _from, state) do
    case Impl.start(state, order_id) do
      {:ok, node, updated_state} ->
        {:reply, {:ok, node}, updated_state, {:continue, :sync}}
      {:error, updated_state} ->
        {:reply, {:error, "Failed to start transactor"}, updated_state, {:continue, :sync}}
    end
  end

  @doc """
  Synchronizes transactors from a remote node.
  """
  def handle_cast({:sync, transactors}, state) do
    transactors = Map.merge(state.transactors, transactors)
    Logger.info("[OrderDispatcher] Syncing transactors")
    {:noreply, %{state | transactors: transactors}}
  end

  @doc """
  Deletes a transactor for an order and updates the state.
  """
  def handle_cast({:delete, order_id}, state) do
    transactors = Map.delete(state.transactors, order_id)
    Logger.info("[OrderDispatcher] Deleting transactor for order #{order_id}")
    {:noreply, %{state | transactors: transactors}, {:continue, :sync}}
  end

  @doc """
  Synchronizes the state across all nodes.
  """
  def handle_continue(:sync, state) do
    Impl.sync_transactors(state)
    {:noreply, state}
  end
end

defmodule ImtOrder.OrderDispatcher.Impl do
  @moduledoc """
  Core logic for managing order transactors in a distributed system.

  Responsibilities:
  - Initializing and updating the `HashRing`.
  - Assigning transactors to nodes.
  - Handling node additions and removals.
  """

  require Logger
  alias ImtOrder.OrderTransactor
  alias ImtOrder.OrderDispatcher

  @replicas 2

  @doc """
  Initializes the `HashRing` with available nodes.

  ## Parameters
  - `state`: The initial state.

  ## Returns
  - Updated state with the `HashRing` initialized.
  """
  def init_ring(state) do
    nodes = Enum.count(Application.get_env(:distmix, :nodes)) - 5
    ring = for i <- 0..nodes do
      :"imt_order_#{4 + i}@127.0.0.1"
    end
    |> Enum.reduce(HashRing.new(), fn node, ring -> HashRing.add_node(ring, node) end)

    %{state | ring: ring}
  end

  @doc """
  Starts a transactor for a given `order_id` and updates the state.

  ## Parameters
  - `state`: The current state of the dispatcher.
  - `order_id`: The unique identifier for the order.
  - `replicas`: The number of nodes on which transactors should be started.

  ## Returns
  - `{:ok, node, updated_state}` if the transactor is successfully started.
  - `{:error, updated_state}` if the transactor could not be started.
  """
  def start(state, order_id, replicas \\ @replicas) do
    case Map.get(state.transactors, order_id) do
      nil -> handle_new_transactor(state, order_id, replicas)
      existing_replicas -> ensure_replicas_healthy(state, order_id, existing_replicas)
    end
  end

  @doc """
  Handles the creation of a new transactor for an order.

  - Determines the replicas (nodes) for the given `order_id` using the `HashRing`.
  - Starts transactors on the selected replicas.
  - Updates the state with the new replicas and transactor mapping.
  - Selects the first healthy node from the results to handle the order.

  ## Parameters
  - `state`: The current state of the dispatcher.
  - `order_id`: The unique identifier of the order.
  - `replicas`: The number of replicas to create.

  ## Returns
  - `{:ok, node, updated_state}` on success.
  - `{:error, updated_state}` if no healthy node is found.
  """
  defp handle_new_transactor(state, order_id, replicas) do
    replicas = HashRing.key_to_nodes(state[:ring], order_id, replicas)
    results = start_replicas(order_id, replicas)

    state = %{state | transactors: Map.put(state.transactors, order_id, replicas)}
    select_first_healthy_node(results, state, order_id)
  end

  @doc """
  Ensures that existing replicas for an order are healthy.

  - Attempts to start transactors on the existing replicas.
  - Selects the first healthy node to handle the order.

  ## Parameters
  - `state`: The current state of the dispatcher.
  - `order_id`: The unique identifier of the order.
  - `replicas`: The list of existing replicas.

  ## Returns
  - `{:ok, node, updated_state}` if a healthy node is found.
  - `{:error, updated_state}` if no healthy node is available.
  """
  defp ensure_replicas_healthy(state, order_id, replicas) do
    results = start_replicas(order_id, replicas)
    select_first_healthy_node(results, state, order_id)
  end

  @doc """
  Starts transactors on a list of replicas (nodes).

  - Determines whether to start the transactor locally or remotely based on the node.
  - Collects the results of the start attempts for all replicas.

  ## Parameters
  - `order_id`: The unique identifier of the order.
  - `replicas`: The list of nodes where replicas should be created.

  ## Returns
  - A list of results for each replica, e.g., `{:ok, node}` or `{:error, reason}`.
  """
  defp start_replicas(order_id, replicas) do
    Enum.map(replicas, fn replica ->
      if replica == Node.self() do
        start_transactor_locally(order_id, replicas)
      else
        start_transactor_remotely(replica, order_id, replicas)
      end
    end)
  end

  @doc """
  Starts a transactor for the given order locally on the current node.

  - Logs success or failure of the operation.

  ## Parameters
  - `order_id`: The unique identifier of the order.
  - `replicas`: The list of nodes where replicas are being created.

  ## Returns
  - `{:ok, Node.self()}` if the transactor is successfully started locally.
  - `{:error, reason}` if the operation fails.
  """
  defp start_transactor_locally(order_id, replicas) do
    case OrderTransactor.start(order_id, replicas) do
      {:ok, _pid} ->
        Logger.info("[OrderDispatcher] Transactor started locally on #{Node.self()} for order #{order_id}")
        {:ok, Node.self()}
      {:error, reason} ->
        Logger.error("[OrderDispatcher] Failed to start transactor locally on #{Node.self()}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Starts a transactor for the given order on a remote node.

  - Logs success or failure of the operation.

  ## Parameters
  - `node`: The remote node where the transactor should be started.
  - `order_id`: The unique identifier of the order.
  - `replicas`: The list of nodes where replicas are being created.

  ## Returns
  - `{:ok, node}` if the transactor is successfully started on the remote node.
  - `{:error, reason}` if the operation fails.
  """
  defp start_transactor_remotely(node, order_id, replicas) do
    case OrderTransactor.start(node, order_id, replicas) do
      {:ok, _pid} ->
        Logger.info("[OrderDispatcher] Transactor started on remote node #{node} for order #{order_id}")
        {:ok, node}
      {:error, reason} ->
        Logger.error("[OrderDispatcher] Failed to start transactor on remote node #{node}: #{inspect(reason)}")
        {:error, reason}
      {:badrpc, :nodedown} ->
        Logger.error("[OrderDispatcher] Failed to start transactor on remote node #{node}: Node is down")
        {:error, :nodedown}
    end
  end

  @doc """
  Selects the first healthy node from the results of transactor creation.

  - Logs and returns the first successful node.
  - Returns an error if no healthy node is found.

  ## Parameters
  - `results`: A list of results from transactor creation attempts.
  - `state`: The current state of the dispatcher.
  - `order_id`: The unique identifier of the order.

  ## Returns
  - `{:ok, healthy_node, state}` if a healthy node is found.
  - `{:error, state}` if no healthy node is available.
  """
  defp select_first_healthy_node(results, state, order_id) do
    case Enum.find(results, fn {:ok, _node} -> true; _ -> false end) do
      {:ok, healthy_node} ->
        Logger.info("[OrderDispatcher] First healthy node is #{inspect(healthy_node)} for order #{order_id}")
        {:ok, healthy_node, state}
      nil ->
        Logger.error("[OrderDispatcher] No healthy nodes available for order #{order_id}")
        {:error, state}
    end
  end

  @doc """
  Synchronizes transactors across all nodes except the current one.
  """
  def sync_transactors(state) do
    HashRing.nodes(state[:ring])
    |> Enum.reject(&(&1 == Node.self()))
    |> Enum.each(fn node -> OrderDispatcher.sync(node, state.transactors) end)
  end

  @doc """
  Updates the `HashRing` by adding or removing a node.

  ## Parameters
  - `state`: Current state.
  - `node`: The node to add or remove.
  - `operation`: `:add` or `:remove`.

  ## Returns
  - Updated state with the modified ring.
  """
  def update_ring(state, node, :add) do
    ring = state[:ring] |> HashRing.add_node(node)
    %{state | ring: ring}
  end

  def update_ring(state, node, :remove) do
    ring = state[:ring] |> HashRing.remove_node(node)
    %{state | ring: ring}
  end
end
