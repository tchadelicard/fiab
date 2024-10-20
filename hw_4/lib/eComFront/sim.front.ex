# in this file : all module for frontend simulation :
# send commit order queries... and stat queries
defmodule ReqSender do
  use GenServer

  def start_link(opts) do GenServer.start_link(__MODULE__, opts, name: __MODULE__) end

  def init(opts) do
    Process.send_after(self(), :stop, opts[:duration])
    Process.send_after(self(), :send_req, 0)

    todo =
      opts[:todo]
      |> Enum.map(fn {c, fun} -> List.duplicate(fun, c) end)
      |> Enum.concat

    {:ok,
      %{id: 0, c: 0,
      parent: opts[:parent], running: true,
      req_interval: div(1000, opts[:rate] || 10),
      todo: todo}}
  end

  def handle_info(:send_req, %{running: false} = state) do {:noreply, state} end
  def handle_info(:send_req, %{running: true, id: id} = state) do
    sender = self()
    fun = Enum.random(state.todo)

    Task.start(fn ->
      fun.(id)
      send(sender,:req_done)
    end)

    Process.send_after(self(), :send_req, state.req_interval)

    {:noreply, %{state | c: state.c + 1, id: state.id + 1}}
  end
  def handle_info(:req_done, state) do {:noreply, maybe_end(%{state | c: state.c - 1})} end
  def handle_info(:stop, state) do {:noreply, maybe_end(%{state | running: false})} end

  def maybe_end(%{running: false, c: 0, parent: _parent} = state) do :init.stop() ; state end
  def maybe_end(%{c: c} = state) when rem(c, 10000) == 0 do IO.write(:stderr, ".") ; state end
  def maybe_end(state) do state end
end

defmodule Req do
  @url 'http://localhost:9090/'

  def get_req_ko400(id, path, logfile) do
    ts = :erlang.system_time(:milli_seconds)

    {time,{ok?,other}} = :timer.tc(fn ->
      case :httpc.request('#{@url}#{path}') do
        {:ok,{{_,code,_},_,_}} when code < 400-> {:ok,code}
        {:ok,{{_,code,_},_,_}}-> {:ko,code}
        {:error,reason}-> {:ko,"#{inspect reason}"}
      end
    end)

    IO.write(logfile,"#{id},#{ts},#{String.replace(path,",","-")},#{div(time,1000)},#{ok?},#{other}\n")
  end

  def post_random_order(req_id, logfile) do
    order =
      Poison.encode!(%{
        id: "#{req_id}",
        products: [
          %{id: :rand.uniform(1000), quantity: :rand.uniform(5)},
          %{id: :rand.uniform(1000), quantity: :rand.uniform(5)}
        ]
      })

    ts = :erlang.system_time(:milli_seconds)

    Task.start(fn ->
      {time, {ok?, other}} =
        :timer.tc(fn ->
          case :httpc.request(:post, {'#{@url}/order', [], 'application/json', order}, [], []) do
            {:ok, {{_, code, _}, _, _}} when code < 400 -> {:ok, code}
            {:ok, {{_ ,code, _}, _, _}} -> {:ko, code}
            {:error, reason} -> {:ko, "#{inspect reason}"}
          end
        end)

      IO.write(logfile, "#{req_id},#{ts},/order,#{div(time, 1000)},#{ok?},#{other}\n")
    end)

    Task.start(fn ->
      :timer.sleep(2_000 + (:rand.uniform(16) * 125)) # le paiement arrive après la commande
      post_payment(req_id, logfile)
    end)
  end

  def post_payment(order_id, logfile) do
    transaction = Poison.encode!(%{transaction_id: :rand.uniform(10_000)})
    ts = :erlang.system_time(:milli_seconds)

    {time, {ok?, other}} =
      :timer.tc(fn ->
        case :httpc.request(:post, {'#{@url}/order/#{order_id}/payment-callback', [], 'application/json', transaction}, [], []) do
          {:ok, {{_, code, _}, _, _}} when code < 400 -> {:ok, code}
          {:ok, {{_, code, _}, _, _}}-> {:ko, code}
          {:error, reason} -> {:ko, "#{inspect reason}"}
        end
      end)

    IO.write(logfile, "#{900000000 + order_id},#{ts},/order/#{order_id}/payment-callback',#{div(time, 1000)},#{ok?},#{other}\n")
  end
end

defmodule ImtSim.EComFront do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    logfile = File.open!("data/stats.csv",[:write])

    children = [
      {
        ReqSender,
        parent: self(),
        rate: 1,
        duration: :timer.seconds(30),
        todo: [
          {10, &Req.get_req_ko400(&1, "/aggregate-stats/#{:rand.uniform(1000)}", logfile)},
          {2, &Req.post_random_order(&1, logfile)},
        ]
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
