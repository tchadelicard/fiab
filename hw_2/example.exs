defmodule AlarmTest do
  alias Alarm

  def run do
    # Start the Alarm.Server using the Alarm API
    pid = Alarm.start()

    # Register multiple devices
    IO.puts("Registering devices...")

    device_1 = Alarm.register(pid, %{name: "EnvSensor", location: "Room 1", type: :environment})
    device_2 = Alarm.register(pid, %{name: "PowerSensor", location: "Room 2", type: :power})
    device_3 = Alarm.register(pid, %{name: "LightSensor", location: "Room 3", type: :light})

    IO.puts("Devices registered: #{device_1}, #{device_2}, #{device_3}")

    # Set alarms for different devices
    IO.puts("Setting alarms...")

    # Set alarm for device_1 (EnvSensor) when temperature exceeds 25 or humidity drops below 30
    Alarm.set_alarm(pid, :env_alarm, fn(_id, data) ->
      (Map.has_key?(data, :temperature) && data[:temperature] > 25) or
      (Map.has_key?(data, :humidity) && data[:humidity] < 30)
    end)

    # Set alarm for device_2 (PowerSensor) when power consumption exceeds 500W
    Alarm.set_alarm(pid, :high_power_alarm, fn(_id, data) ->
      Map.has_key?(data, :power_consumption) && data[:power_consumption] > 500
    end)

    # Set alarm for device_3 (LightSensor) when light intensity exceeds 1000 lumens
    Alarm.set_alarm(pid, :bright_light_alarm, fn(_id, data) ->
      Map.has_key?(data, :light_intensity) && data[:light_intensity] > 1000
    end)

    IO.puts("Alarms set.")

    # Add some complex data (some will trigger alarms, some will not)
    IO.puts("Adding data to devices...")

    # EnvSensor (Device 1) data
    Alarm.add_data(pid, device_1, %{temperature: 20, humidity: 40}) # No alarm
    Alarm.add_data(pid, device_1, %{temperature: 30, humidity: 25}) # Triggers env_alarm (temperature = 30, humidity = 25)

    # PowerSensor (Device 2) data
    Alarm.add_data(pid, device_2, %{power_consumption: 400})  # No alarm (power = 400W)
    Alarm.add_data(pid, device_2, %{power_consumption: 600})  # Triggers high_power_alarm (power = 600W)

    # LightSensor (Device 3) data
    Alarm.add_data(pid, device_3, %{light_intensity: 900})   # No alarm (light = 900 lumens)
    Alarm.add_data(pid, device_3, %{light_intensity: 1200})  # Triggers bright_light_alarm (light = 1200 lumens)

    # Wait for a moment to allow alarms to be processed
    :timer.sleep(1000)

    # Receive alarm messages
    IO.puts("Checking for triggered alarms...")
    receive_alarm()

    # Test the search function to find devices with specific criteria
    IO.puts("Searching for devices located in 'Room 1'...")

    search_result = Alarm.search(pid, fn infos -> infos[:location] == "Room 1" end)
    IO.inspect(search_result, label: "Devices found in Room 1")

    IO.puts("Searching for devices of type :power...")

    search_result = Alarm.search(pid, fn infos -> infos[:type] == :power end)
    IO.inspect(search_result, label: "Devices of type :power")

    IO.puts("Test complete.")
  end

  # Function to handle received alarms
  defp receive_alarm do
    receive do
      {:alarm, name, id, data} ->
        IO.puts("Alarm triggered: #{name} for device #{id} with data: #{inspect(data)}")
        receive_alarm() # Continue receiving alarms
    after
      5000 ->
        IO.puts("No more alarms received.")
    end
  end
end

# Start the test
AlarmTest.run()
