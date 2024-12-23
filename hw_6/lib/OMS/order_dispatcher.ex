defmodule ImtOrder.OrderDispatcher do
  @moduledoc """
  Provides a public API for managing the dispatching of order transactors.

  This module serves as a wrapper around the `OrderDispatcher.Server` to start transactors for orders.
  """
  @timeout 10_000

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

  def start(node, order_id) do
    GenServer.call({ImtOrder.OrderDispatcher.Server, node}, {:start_transactor, order_id}, @timeout)
  end
end

defmodule ImtOrder.OrderDispatcher.Server do
  @moduledoc """
  GenServer responsible for managing the dispatching of transactors across nodes.

  This server maintains the state of available nodes and the mapping of orders to transactors.
  """

  use GenServer
  alias ImtOrder.OrderDispatcher.Impl

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
    {:ok, %{ring: nil} |> Impl.init_ring()}
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
    case Impl.start_transactor(state, order_id) do
      {:ok, node, updated_state} ->
        {:reply, {:ok, node}, updated_state}

      {:error, updated_state} ->
        {:reply, {:error, "Failed to start transactor"}, updated_state}
    end
  end

  def handle_call({:start_transactor, order_id}, _from, state) do
    case ImtOrder.OrderTransactor.start(order_id) do
      {:ok, _} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end

defmodule ImtOrder.OrderDispatcher.Impl do
  @moduledoc """
  Implements the core logic for dispatching transactors across nodes.

  This module contains helper functions for hashing order IDs, updating node lists,
  and starting transactors on appropriate nodes.
  """

  require Logger
  alias ImtOrder.OrderDispatcher

  @doc """
  Determines the node on which to place a transactor for a given `order_id`.

  Uses consistent hashing to select a node from the list of available nodes.

  ## Parameters
  - `state`: The current state of the dispatcher.
  - `order_id`: The unique identifier for the order.

  ## Returns
  - The selected node for the transactor.
  """
  def get_node(state, order_id) do
    HashRing.key_to_node(state[:ring], order_id)
  end

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
      :"imt_order_#{4+i}@127.0.0.1"
    end |> Enum.reduce(HashRing.new(), fn node, ring -> HashRing.add_node(ring, node) end)
    %{state | ring: ring}
  end

  @doc """
  Starts a transactor for a given `order_id` and updates the state.

  If the transactor already exists, it returns the associated node. Otherwise,
  it selects a node and starts the transactor using `OrderManager.start/2`.

  ## Parameters
  - `state`: The current state of the dispatcher.
  - `order_id`: The unique identifier for the order.

  ## Returns
  - `{:ok, node, updated_state}` if the transactor is successfully started.
  - `{:error, updated_state}` if the transactor could not be started.
  """
  def start_transactor(state, order_id) do
    node = state |> get_node(order_id)

    case node == Node.self() do
      true ->
        case ImtOrder.OrderTransactor.start(order_id) do
          {:ok, _} ->
            Logger.info("[OrderDispatcher] Node #{node} for order #{order_id}")
            {:ok, node, state}
          {:error, _} ->
            Logger.error("[OrderDispatcher] Failed to start transactor on node #{node}")
            {:error, state}
        end
      false ->
        case OrderDispatcher.start(node, order_id) do
          :ok ->
            Logger.info("[OrderDispatcher] Node #{node} for order #{order_id}")
            {:ok, node, state}
          {:error, _} ->
            Logger.error("[OrderDispatcher] Failed to start transactor on node #{node}")
            {:error, state}
        end
    end
  end
end
