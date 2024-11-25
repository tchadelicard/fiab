defmodule ImtOrder.Stats.API do
  use API.Exceptions
  use Plug.Router
  require Logger
  plug :match
  plug :dispatch

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
