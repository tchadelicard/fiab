defmodule Alarm.Server do
  @moduledoc """
  The `Alarm.Server` module implements a GenServer responsible for managing the registration of devices,
  handling alarms, and processing device data. It delegates most of the logic to the `Alarm.Impl` module
  but manages the state and communication as a GenServer.

  The server state is structured as a tuple: `{devices, data, alarms}`:
  - `devices`: A map of registered devices with their information.
  - `data`: A map of the data associated with each device.
  - `alarms`: A map of alarms, each linked to a device and its trigger condition.

  This server handles synchronous (`call`) and asynchronous (`cast`) requests.
  """

  use GenServer
  alias Alarm.Impl

  @doc """
  Initializes the GenServer state with three empty maps:
  - One for registered devices (`devices`).
  - One for the data associated with each device (`data`).
  - One for alarms associated with the devices (`alarms`).

  Returns the initial state, which is a tuple of three empty maps: `{:ok, {%{}, %{}, %{}}}`.
  """
  def init(_) do
    {:ok, {%{}, %{}, %{}}}
  end

  @doc """
  Handles synchronous `call` requests. Supports multiple types of requests:

  - `:status`: Retrieves the current state of the server.
  - `{:register, infos}`: Registers a new device with the provided information.
  - `{:set_alarm, pid, name, filter_fun}`: Sets an alarm for a device with a specified trigger function.
  - `{:search, filter_fun}`: Searches for devices that match a given filter function.

  Returns appropriate responses depending on the type of request.
  """
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:register, infos}, _from, {current_devices, current_data, current_alarms}) do
    {new_device_id, updated_devices} = Impl.register({:register, infos}, current_devices)
    {:reply, new_device_id, {updated_devices, current_data, current_alarms}}
  end

  def handle_call({:set_alarm, pid, name, filter_fun}, _from, {current_devices, current_data, current_alarms}) do
    {status, updated_alarms} = Impl.set_alarm({:set_alarm, pid, name, filter_fun}, current_alarms)
    {:reply, status, {current_devices, current_data, updated_alarms}}
  end

  def handle_call({:search, filter_fun}, _from, {current_devices, current_data, current_alarms}) do
    search_result = Impl.search({:search, filter_fun}, current_devices)
    {:reply, search_result, {current_devices, current_data, current_alarms}}
  end

  @doc """
  Handles asynchronous `cast` requests. Specifically supports the following:

  - `{:data, id, data}`: Adds data to a device and checks if any alarms are triggered based on the new data.

  The data is added to the device's history, and alarms are checked. If an alarm is triggered, the registered
  process for that alarm is notified.

  The state is updated with the new data and alarm checks.
  """
  def handle_cast({:data, id, data}, {current_devices, current_data, current_alarms}) do
    updated_data = Impl.data({:data, id, data}, current_devices, current_data)
    Impl.check_and_send_alarms({:data, id, data}, current_alarms)
    {:noreply, {current_devices, updated_data, current_alarms}}
  end
end
