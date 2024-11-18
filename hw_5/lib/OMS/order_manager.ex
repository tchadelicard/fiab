defmodule ImtOrder.OrderManager do
  @moduledoc """
  Provides an API for starting `OrderTransactor` processes on a specific node.

  This module acts as a wrapper around the `OrderManager.Server` to handle the initialization and management
  of `OrderTransactor` processes.
  """

  @doc """
  Sends a synchronous call to the `OrderManager.Server` to start a transactor for the given `order_id`.

  ## Parameters
  - `node`: The node where the transactor should be started.
  - `order_id`: The unique identifier for the order.

  ## Returns
  - `:ok` if the transactor is started successfully.
  - `{:error, reason}` if there was an issue starting the transactor.
  """
  def start(node, order_id) do
    GenServer.call({ImtOrder.OrderManager.Server, node}, {:start, order_id})
  end
end

defmodule ImtOrder.OrderManager.Server do
  @moduledoc """
  GenServer responsible for managing the startup of `OrderTransactor` processes locally.

  This server periodically attempts to connect to the main "console" node and allows starting
  `OrderTransactor` processes upon request.
  """

  use GenServer

  @doc """
  Starts the `OrderManager.Server` GenServer.

  ## Returns
  - `{:ok, pid}` if the server starts successfully.
  """
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Initializes the state and schedules an immediate attempt to connect to the main "console" node.

  ## Returns
  - `{:ok, state}` with the initial state (`nil`).
  """
  def init(_) do
    Process.send_after(self(), :connect, 0)
    {:ok, nil}
  end

  @doc """
  Handles periodic connection attempts to the main "console" node.

  This function uses the hostname to build the "console" node's name and retries the connection
  every second.

  ## Parameters
  - `:connect`: The message triggering the connection attempt.
  - `state`: The current state (unused).

  ## Returns
  - `{:noreply, state}` to indicate no state change.
  """
  def handle_info(:connect, state) do
    Node.connect(:"console@#{ImtOrder.Utils.get_hostname()}")
    Process.send_after(self(), :connect, 1000)
    {:noreply, state}
  end

  @doc """
  Handles requests to start a transactor for a specific `order_id`.

  This function delegates the creation of the transactor to the `ImtOrder.OrderTransactor.start/1` function.

  ## Parameters
  - `{:start, order_id}`: A tuple containing the `:start` action and the `order_id`.
  - `_from`: The client information (unused).
  - `state`: The current state.

  ## Returns
  - `{:reply, :ok, state}` if the transactor is started successfully.
  - `{:reply, {:error, reason}, state}` if starting the transactor fails.
  """
  def handle_call({:start, order_id}, _from, state) do
    case ImtOrder.OrderTransactor.start(order_id) do
      {:ok, _} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end
end
