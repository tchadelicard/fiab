defmodule Alarm.Impl do
  @moduledoc """
  The `Alarm.Impl` module contains the implementation logic for managing devices,
  storing data, setting alarms, searching for devices, and triggering alarms.

  This module is used internally by the `Alarm.Server` GenServer to handle the core
  operations related to devices and alarms.
  """

  @doc """
  Registers a new device in the system.

  Takes the `:register` message, a map of `infos` describing the device (e.g., name, location),
  and the current list of registered devices. It assigns a new unique device ID by calculating
  the current size of the device map and adding 1.

  Returns a tuple with the new device ID and the updated device map.

  ## Parameters
  - `{:register, infos}`: The register message tuple containing device information.
  - `devices`: A map of currently registered devices.

  ## Examples

      iex> Alarm.Impl.register({:register, %{name: "Sensor", location: "Room 1"}}, %{})
      {1, %{1 => %{name: "Sensor", location: "Room 1"}}}

  """
  def register({:register, infos}, devices) do
    # Assign a new device ID by calculating the current map size + 1
    new_device_id = Kernel.map_size(devices) + 1
    # Add the new device info to the map with the new ID
    new_devices = Map.put(devices, new_device_id, infos)
    {new_device_id, new_devices}
  end

  @doc """
  Adds new data to a device if the device ID exists.

  Takes a `:data` message containing a device ID and its data, a map of `current_devices`
  to check if the device exists, and a `current_data` map that holds all previous data for devices.

  If the device exists, it appends the new data to the existing data list for that device.

  Returns the updated data map.

  ## Parameters
  - `{:data, id, data}`: The data message containing the device ID and its associated data.
  - `current_devices`: A map of all registered devices.
  - `current_data`: A map of data that has already been recorded for the devices.

  ## Examples

      iex> Alarm.Impl.data({:data, 1, %{temperature: 25}}, %{1 => %{name: "Sensor"}}, %{})
      %{1 => [%{temperature: 25}]}

  """
  def data({:data, id, data}, current_devices, current_data) do
    if Map.has_key?(current_devices, id) do
      # Append the new data to the existing data list for the device
      updated_data = Map.get(current_data, id, []) ++ [data]
      # Update the current_data map with the new data
      new_data = Map.put(current_data, id, updated_data)
      new_data
    else
      # If the device ID is not found, return the current data without changes
      current_data
    end
  end

  @doc """
  Sets an alarm for a device by adding a new alarm to the `current_alarms` map.

  The alarm is defined by a `name`, a process `pid` (to send alerts to), and a `filter_fun`
  (a function that determines when the alarm should trigger based on incoming data).

  If an alarm with the same name already exists, it returns an error tuple. Otherwise,
  it adds the alarm to the current alarms and returns the updated alarm map.

  ## Parameters
  - `{:set_alarm, pid, name, filter_fun}`: The set alarm message with the process PID, alarm name, and filter function.
  - `current_alarms`: A map of existing alarms.

  ## Examples

      iex> Alarm.Impl.set_alarm({:set_alarm, self(), :high_temp, fn(id, data) -> data[:temperature] > 30 end}, %{})
      {:ok, %{high_temp: {self(), fn(id, data) -> data[:temperature] > 30 end}}}

  """
  def set_alarm({:set_alarm, pid, name, filter_fun}, current_alarms) do
    if Map.has_key?(current_alarms, name) do
      # Return error if an alarm with the same name already exists
      {:error, current_alarms}
    else
      # Add the new alarm to the map and return the updated alarms map
      new_alarms = Map.put(current_alarms, name, {pid, filter_fun})
      {:ok, new_alarms}
    end
  end

  @doc """
  Searches for devices that match the provided filter function.

  The `filter_fun` is applied to the information of each registered device, and it
  returns a list of devices that satisfy the filter criteria.

  ## Parameters
  - `{:search, filter_fun}`: The search message containing the filter function.
  - `current_devices`: A map of currently registered devices.

  ## Examples

      iex> Alarm.Impl.search({:search, fn infos -> infos[:location] == "Room 1" end}, %{1 => %{name: "Sensor", location: "Room 1"}})
      [{1, %{name: "Sensor", location: "Room 1"}}]

  """
  def search({:search, filter_fun}, current_devices) do
    # Filter devices based on the provided filter function
    devices = Enum.filter(current_devices, fn {_, infos} -> filter_fun.(infos) end)
    devices
  end

  @doc """
  Checks and sends alarms if any are triggered based on the incoming data.

  Takes a `:data` message and the map of `current_alarms`. It checks all active alarms,
  and if any of them are triggered (based on the alarm's filter function), it sends
  a notification to the process (PID) that registered the alarm.

  ## Parameters
  - `{:data, id, data}`: The data message containing the device ID and data.
  - `current_alarms`: A map of current alarms.

  ## Examples

      iex> Alarm.Impl.check_and_send_alarms({:data, 1, %{temperature: 35}}, %{high_temp: {self(), fn(_, data) -> data[:temperature] > 30 end}})
      # Sends {:alarm, :high_temp, 1, %{temperature: 35}} to self()

  """
  def check_and_send_alarms({:data, id, data}, current_alarms) do
    # Find alarms that are triggered by the new data
    triggered_alarms = check_alarms({:data, id, data}, current_alarms)

    # Send a message to the process for each triggered alarm
    Enum.each(triggered_alarms, fn {name, {pid, _}} ->
      send(pid, {:alarm, name, id, data})
    end)
  end

  @doc """
  Checks all alarms and returns a list of those that are triggered.

  The `filter_fun` for each alarm is applied to the incoming data. If the function
  returns `true`, the alarm is considered triggered, and it is included in the result.

  ## Parameters
  - `{:data, id, data}`: The data message containing the device ID and data.
  - `current_alarms`: A map of current alarms.

  ## Examples

      iex> Alarm.Impl.check_alarms({:data, 1, %{temperature: 35}}, %{high_temp: {self(), fn(_, data) -> data[:temperature] > 30 end}})
      [high_temp: {self(), fn(_, data) -> data[:temperature] > 30 end}]

  """
  def check_alarms({:data, id, data}, current_alarms) do
    # Filter and return the alarms that are triggered based on the incoming data
    Enum.filter(current_alarms, fn {_, {_, filter_fun}} ->
      filter_fun.(id, data)
    end)
  end
end
