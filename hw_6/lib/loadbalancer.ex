defmodule LoadBalancer do
  use Supervisor
  require Logger
  def start_link(init_arg) do Supervisor.start_link(__MODULE__,init_arg,name: __MODULE__) end
  def init(_) do
    {_ip, port} = _http_config = Application.fetch_env!(:imt_order, :http)
    nb_instances = (Application.fetch_env!(:imt_order, :nodes) |> Enum.count) - 4
    Logger.info("[#{Node.self}] [LoadBalancer] Started Load Balancer on #{port}")
    instances=for i<-1..nb_instances do {{127,0,0,1},9092+i} end
    Logger.info("[#{Node.self}] [LoadBalancer] Will redirect to #{inspect instances}")
    Supervisor.init([
        {LoadBalancer.RoundRobin,instances},
        {LoadBalancer.Proxy.Listener, port: port, ip: {127,0,0,1}, checkout_mod: LoadBalancer.RoundRobin}
      ] , strategy: :one_for_one)
  end
end

defmodule LoadBalancer.RoundRobin do
  use GenServer
  def start_link(backends) do GenServer.start_link(__MODULE__, backends, name: __MODULE__) end
  def init(backends) do {:ok,{backends,[]}} end
  def handle_call(:checkout,_,{[h],acc}) do {:reply,h,{Enum.reverse([h|acc]),[]}} end
  def handle_call(:checkout,_,{[h|t],acc}) do {:reply,h,{t,[h|acc]}} end
  def checkout do GenServer.call(__MODULE__,:checkout) end
end

defmodule LoadBalancer.Proxy do
  use GenServer
  defmodule Listener do
    require Logger
    use GenServer
    def start_link(init_arg) do GenServer.start_link(__MODULE__, init_arg, name: __MODULE__) end
    def init(opts) do
      acceptor_num = opts[:acceptor_num] || 100
      {:ok,listen_sock} = :gen_tcp.listen(opts[:port], [:binary,active: true,ip: opts[:ip] || :any])
      for _<-1..acceptor_num do spawn_link(fn->acceptor(listen_sock,opts[:checkout_mod]) end) end
      spawn_link(fn->
        Process.flag(:trap_exit,true)
        receive do
          {:EXIT,_,:normal}->
            :gen_tcp.close(listen_sock)
            :ok
          {:EXIT,_,:shutdown}->
            :gen_tcp.close(listen_sock)
            :ok
          {:EXIT,_,r}->
            :gen_tcp.close(listen_sock)
            msg = "[#{__MODULE__}] - Got an exception #{Exception.format_exit(r)}"
            Logger.error(msg)
        end
      end)
      {:ok,[]}
    end
    def acceptor(listen_s,checkout_mod) do
      {:ok,s} = :gen_tcp.accept(listen_s)
      {:ok,pid} = GenServer.start(LoadBalancer.Proxy,{s,checkout_mod.checkout()})
      :ok = :gen_tcp.controlling_process(s,pid)
      acceptor(listen_s,checkout_mod)
    end
  end

  @tcp_timeout 5000
  def init({s,{ip,port}=backend}=args) do
    {:ok, backend_s} = case :gen_tcp.connect(ip, port, [:binary, packet: 0, active: true]) do
      {:error, err} ->
        IO.puts "Error while trying to connect to: #{inspect {ip,port}}:   #{inspect err}"
        :timer.sleep(:timer.seconds(5))
        init(args)
      {:ok, b} -> {:ok, b}
    end
    {:ok,%{backend: backend,s: s, backend_s: backend_s},@tcp_timeout}
  end
  # proxy frontend data to backend
  def handle_info({:tcp,s,data},%{s: s}=state) do
    :ok = :gen_tcp.send(state.backend_s,data)
    {:noreply,state,@tcp_timeout}
  end
  # proxy backend data to frontend
  def handle_info({:tcp,s,data},%{backend_s: s}=state) do
    :ok = :gen_tcp.send(state.s,data)
    {:noreply,state,@tcp_timeout}
  end

  # Frontend TCP connection died and closed... close backend TCP socket and stop
  def handle_info({tcp_die,s},%{s: s}=state) when tcp_die in [:tcp_closed,:tcp_error] do
    :gen_tcp.close(state.backend_s)
    {:stop,:normal,state}
  end
  # Backend TCP connection died and closed... close frontend TCP socket and stop
  def handle_info({tcp_die,s},%{backend_s: s}=state) when tcp_die in [:tcp_closed,:tcp_error] do
    :gen_tcp.close(state.s)
    {:stop,:normal,state}
  end

  # No
  def handle_info(:timeout,state) do
    :gen_tcp.close(state.s)
    :gen_tcp.close(state.backend_s)
    {:stop,:normal,state}
  end
end
