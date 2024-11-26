defmodule ImtOrder.Utils do
  @moduledoc """
  Utility functions for working with node and hostname information.

  This module provides helper functions to determine if the current node
  is the "console" node and to retrieve the hostname of the current node.
  """

  @doc """
  Checks if the current node is the "console" node.

  ## Returns
  - `true` if the current node is the "console" node.
  - `false` otherwise.

  ## Example
      iex> ImtOrder.Utils.is_console()
      false
  """
  def is_console() do
    DistMix.nodei() == 4
  end

  @doc """
  Retrieves the hostname of the current node.

  ## Returns
  - A string representing the hostname.

  ## Example
      iex> ImtOrder.Utils.get_hostname()
      "localhost"
  """
  def get_hostname() do
    [_, hostname] = Node.self() |> Atom.to_string() |> String.split("@")
    hostname
  end

  def get_port() do
    {_host, port} = Application.get_env(:imt_order, :http)
    port
  end
end
