defmodule ImtOrder.Stats.API do
  @moduledoc """
  HTTP API for retrieving product statistics.

  This module defines routes using `Plug.Router` and interacts with the
  `ImtOrder.StatsToDb` module to fetch statistics for specific products.
  """

  use API.Exceptions # Handles custom exceptions for API requests.
  use Plug.Router # Provides routing for HTTP requests.
  require Logger

  # Match incoming requests to defined routes and dispatch them to handlers.
  plug :match
  plug :dispatch

  @doc """
  Endpoint for retrieving statistics for a given product.

  GET `/stats/:product`

  - Returns 200 with the product statistics in JSON format if found.
  - Returns 404 with an error message in JSON format if not found or an error occurs.
  """
  get "/stats/:product" do
    product = String.to_integer(conn.params["product"])

    case ImtOrder.StatsToDb.get(product) do
      {:ok, stats} ->
        conn
        |> send_resp(200, Poison.encode!(stats))
        |> halt()

      {:error, error} ->
        conn
        |> send_resp(404, Poison.encode!(error))
        |> halt()
    end
  end
end
