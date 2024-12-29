defmodule ImtOrder.OrderDispatcher do
  @moduledoc """
  Provides a public API for managing the dispatching of order transactors.

  This module serves as a wrapper around the `OrderDispatcher.Server` to start transactors for orders.
  """
  @timeout 30_000

  @doc """
  Starts a transactor for a given `order_id`.

  This function delegates the call to the `OrderDispatcher.Server`.

  ## Parameters
  - `order_id`: The unique identifier for the order.

  ## Returns
  - `{:ok, node}` if the transactor was successfully started on a node.
  - `{:error, reason}` if there was an issue starting the transactor.
  """
  def start(order_id) do
    GenServer.call(ImtOrder.OrderDispatcher.Server, {:start, order_id}, @timeout)
  end

  def sync(node, transactors) do
    GenServer.cast({ImtOrder.OrderDispatcher.Server, node}, {:sync, transactors})
  end

  def delete(order_id) do
    GenServer.cast(ImtOrder.OrderDispatcher.Server, {:delete, order_id})
  end
end

defmodule ImtOrder.OrderDispatcher.Server do
  @moduledoc """
  GenServer responsible for managing the dispatching of transactors across nodes.

  This server maintains the state of available nodes and the mapping of orders to transactors.
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
  Initializes the state of the dispatcher.

  The initial state includes:
  - `nodes`: A list of available nodes.
  - `index`: An index counter for internal tracking.

  ## Returns
  - `{:ok, state}` with the initial state.
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

  def handle_info({:nodeup, node}, state) do
    Logger.info("[OrderDispatcher] Node #{Node.self}: Node #{node} is up")
    state = Impl.update_ring(state, node, :add)
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.info("[OrderDispatcher] Node #{Node.self}: Node #{node} is up")
    state = Impl.update_ring(state, node, :remove)
    {:noreply, state}
  end

  @doc """
  Handles the `:start` call to create a transactor for an order.

  Delegates the creation logic to `OrderDispatcher.Impl.start_transactor/2`.

  ## Parameters
  - `{:start, order_id}`: A tuple containing the `:start` action and the `order_id`.
  - `_from`: The client information (not used).
  - `state`: The current state of the server.

  ## Returns
  - `{:reply, {:ok, node}, updated_state}` if the transactor is successfully started.
  - `{:reply, {:error, reason}, updated_state}` if the transactor could not be started.
  """
  def handle_call({:start, order_id}, _from, state) do
    case Impl.start(state, order_id) do
      {:ok, node, updated_state} ->
        {:reply, {:ok, node}, updated_state, {:continue, :sync}}
      {:error, updated_state} ->
        {:reply, {:error, "Failed to start transactor"}, updated_state, {:continue, :sync}}
    end
  end

  def handle_cast({:sync, transactors}, state) do
    transactors = Map.merge(state.transactors, transactors)
    Logger.info("[OrderDispatcher] Syncing transactors")
    {:noreply, %{state | transactors: transactors}}
  end

  def handle_cast({:delete, order_id}, state) do
    transactors = Map.delete(state.transactors, order_id)
    Logger.info("[OrderDispatcher] Deleting transactor for order #{order_id}")
    {:noreply, %{state | transactors: transactors}, {:continue, :sync}}
  end

  def handle_continue(:sync, state) do
    Impl.sync_transactors(state)
    {:noreply, state}
  end
end

defmodule ImtOrder.OrderDispatcher.Impl do
  @moduledoc """
  Implements the core logic for dispatching transactors across nodes.

  This module contains helper functions for hashing order IDs, updating node lists,
  and starting transactors on appropriate nodes.
  """

  require Logger
  alias ImtOrder.OrderTransactor
  alias ImtOrder.OrderDispatcher

  @replicas 2

  @doc """
  Updates the list of available nodes in the dispatcher's state.

  This function retrieves the current node and all connected nodes.

  ## Parameters
  - `state`: The current state of the dispatcher.

  ## Returns
  - The updated state with the new list of nodes.
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

  defp handle_new_transactor(state, order_id, replicas) do
    replicas = HashRing.key_to_nodes(state[:ring], order_id, replicas)
    results = start_replicas(order_id, replicas)

    state = %{state | transactors: Map.put(state.transactors, order_id, replicas)}
    select_first_healthy_node(results, state, order_id)
  end

  defp ensure_replicas_healthy(state, order_id, replicas) do
    results = start_replicas(order_id, replicas)
    select_first_healthy_node(results, state, order_id)
  end

  defp start_replicas(order_id, replicas) do
    Enum.map(replicas, fn replica ->
      if replica == Node.self() do
        start_transactor_locally(order_id, replicas)
      else
        start_transactor_remotely(replica, order_id, replicas)
      end
    end)
  end

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

  defp start_transactor_remotely(node, order_id, replicas) do
    case OrderTransactor.start(node, order_id, replicas) do
      {:ok, _pid} ->
        Logger.info("[OrderDispatcher] Transactor started on remote node #{node} for order #{order_id}")
        {:ok, node}
      {:error, reason} ->
        Logger.error("[OrderDispatcher] Failed to start transactor on remote node #{node}: #{inspect(reason)}")
        {:error, reason}
    end
  end

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

  def sync_transactors(state) do
    HashRing.nodes(state[:ring])
    |> Enum.reject(&(&1 == Node.self()))
    |> Enum.each(fn node -> OrderDispatcher.sync(node, state.transactors) end)
  end

  def update_ring(state, node, :add) do
    ring = state[:ring] |> HashRing.add_node(node)
    %{state | ring: ring}
  end

  def update_ring(state, node, :remove) do
    ring = state[:ring] |> HashRing.remove_node(node)
    %{state | ring: ring}
  end
end
