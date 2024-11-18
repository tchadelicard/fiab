defmodule API.Exceptions do
    defmacro __using__(_opts) do
      quote location: :keep do @before_compile API.Exceptions end
    end

    defmacro __before_compile__(_) do
      quote location: :keep do
        require Logger
        defoverridable [call: 2]
        def call(conn, opts) do
          try do
            super(conn, opts)
          rescue
            reason ->
              kind = :error
              stack = __STACKTRACE__
              reason = Exception.normalize(kind, reason, stack)
              status = case kind do x when x in [:error,:throw]-> Plug.Exception.status(reason); _-> 500 end
              case Exception.exception?(reason) do
                true ->
                  Logger.error("[#{__MODULE__} - #{Node.self}] #{Exception.format(kind,reason,stack)}")
                false ->
                  Logger.error("[#{__MODULE__} - #{Node.self}] Exit - #{Exception.format(kind,reason,stack)}")
              end
              :erlang.raise kind,reason,stack
          catch
            kind, reason ->
              stack = __STACKTRACE__
              reason = Exception.normalize(kind, reason, stack)
              status = case kind do x when x in [:error,:throw]-> Plug.Exception.status(reason); _-> 500 end

              case Exception.exception?(reason) do
                true ->
                  Logger.error("[#{__MODULE__} - #{Node.self}] #{Exception.format(kind,reason,stack)}")

                false ->
                  Logger.error("[#{__MODULE__} - #{Node.self}] Exit - #{Exception.format(kind,reason,stack)}")
              end
              :erlang.raise kind,reason,stack
          end
        end
      end
  end
end
