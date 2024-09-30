defmodule Alarm do
  @moduledoc """
  The `Alarm` module provides a high-level interface for interacting with an alarm system.

  It allows clients to:

  - Start an Alarm server (`start/0`).
  - Register new devices with the server (`register/2`).
  - Set alarms for those devices with custom conditions (`set_alarm/3`).
  - Search for devices based on specific criteria (`search/2`).
  - Add data to devices, which can trigger alarms if conditions are met (`add_data/3`).

  This module communicates with the `Alarm.Server`, a GenServer process that manages
  device registrations, alarm settings, and data processing. Clients interact with the
  server using the functions provided in this module.

  Each alarm is tied to a device and is triggered based on a filter function that evaluates
  device data when new information is added. If the alarm is triggered, the client process
  that set the alarm will receive a notification.
  """

  @doc """
  Starts the Alarm server and returns its process ID (pid).

  This function initializes the `Alarm.Server` GenServer process, which will handle
  device registrations, alarm settings, and data updates.

  ## Examples

      iex> pid = Alarm.start()
      #PID<0.123.0>

  The returned PID can be used to interact with the Alarm server through other functions
  in this module.
  """
  def start do
    {:ok, pid} = GenServer.start(Alarm.Server, nil)
    pid  # Return the PID of the started GenServer.
  end

  @doc """
  Registers a new device in the Alarm server.

  Accepts the pid of the Alarm server and a map of device information. This information
  can include the device's name, location, and any other metadata relevant to the device.

  Returns the unique device ID assigned by the server.

  ## Parameters

  - `pid`: The PID of the running Alarm server.
  - `infos`: A map of device information (e.g., name, type, location).

  ## Examples

      iex> Alarm.register(pid, %{name: "TempSensor", location: "Room 1"})
      1

  The returned value is the device's unique ID, which can be used to interact with the device.
  """
  def register(pid, infos) do
    GenServer.call(pid, {:register, infos})
  end

  @doc """
  Sets an alarm on a device with a given name and filter function.

  Accepts the pid of the Alarm server, the name of the alarm, and a filter function
  (`filter_fun`). The filter function is used to determine whether the alarm should
  be triggered when data is added to the device.

  The calling process (i.e., `self()`) is registered to receive notifications if
  the alarm is triggered.

  ## Parameters

  - `pid`: The PID of the running Alarm server.
  - `name`: The name of the alarm.
  - `filter_fun`: A function that takes two arguments: the device ID and the data,
    and returns `true` if the alarm condition is met.

  ## Examples

      iex> Alarm.set_alarm(pid, :high_temp_alarm, fn(id, data) -> data[:temperature] > 30 end)
      :ok

  The alarm will be triggered when the temperature exceeds 30, and the process that
  set the alarm will receive a notification.
  """
  def set_alarm(pid, name, filter_fun) do
    GenServer.call(pid, {:set_alarm, self(), name, filter_fun})
  end

  @doc """
  Searches for devices in the Alarm server that match a given filter function.

  Accepts the pid of the Alarm server and a filter function that specifies the
  search criteria. The filter function is applied to the device information
  to find matching devices.

  Returns a list of matching devices.

  ## Parameters

  - `pid`: The PID of the running Alarm server.
  - `filter_fun`: A function that takes the device's information (a map) and returns
    `true` if the device matches the search criteria.

  ## Examples

      iex> Alarm.search(pid, fn infos -> infos[:location] == "Room 1" end)
      [{1, %{name: "TempSensor", location: "Room 1"}}]

  This example searches for devices located in "Room 1" and returns a list of
  matching devices.
  """
  def search(pid, filter_fun) do
    GenServer.call(pid, {:search, filter_fun})
  end

  @doc """
  Adds data to a device in the Alarm server.

  Accepts the pid of the Alarm server, the ID of the device, and the data to be added.
  Data can be any key-value map, and if the data matches a condition set by an alarm,
  the alarm will be triggered.

  This function sends an asynchronous message to the server, so it does not wait
  for a reply.

  ## Parameters

  - `pid`: The PID of the running Alarm server.
  - `device_id`: The ID of the device to add data to.
  - `data`: A map containing the data to be added to the device.

  ## Examples

      iex> Alarm.add_data(pid, 1, %{temperature: 35})
      :ok

  If there are any alarms set on the device for high temperature, they will be triggered
  when the data is added.
  """
  def add_data(pid, device_id, data) do
    GenServer.cast(pid, {:data, device_id, data})
  end
end
