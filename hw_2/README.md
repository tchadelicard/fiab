# Homework 2

This Elixir project implements an alarm system server. The project contains two main modules: `Alarm.Server` and `Alarm.Impl`. The `Alarm.Server` is a GenServer responsible for managing the registration of devices, setting alarms, adding device data, and processing alarms. The `Alarm.Impl` module contains the core logic for handling devices, alarms, and data processing. Clients can register devices, set alarms with custom trigger conditions, and send data that might trigger alarms.

## Project Structure

```
├── README.md                 # Project documentation
├── example.exs               # Example script demonstrating usage of the alarm system
├── lib/                      # Source files for Alarm Server and implementation
│   ├── alarm.ex              # Client API to interact with the Alarm.Server
│   ├── impl.ex               # Core logic for handling devices, alarms, and data processing
│   └── server.ex             # Alarm GenServer for managing devices and alarms
├── mix.exs                   # Mix project file
└── test/                     # Unit tests for each module
    ├── alarm_impl_test.exs   # Tests for Alarm.Impl module
    ├── alarm_server_test.exs # Tests for Alarm.Server module
    └── test_helper.exs       # Test helper
```

## Usage

### 1. Run the project in `iex`

You can use the project interactively by launching the Elixir shell (`iex`):

```bash
iex -S mix
```

Now, you can interact with the `Alarm` module to register devices, set alarms, and send data:

```elixir
# Start the Alarm server
pid = Alarm.start()

# Register a new device
device_id = Alarm.register(pid, %{name: "TempSensor", location: "Room 1"})

# Set an alarm for when the temperature exceeds 30
Alarm.set_alarm(pid, :high_temp_alarm, fn(_id, data) -> data[:temperature] > 30 end)

# Add data that will trigger the alarm
Alarm.add_data(pid, device_id, %{temperature: 35})

# You should receive an alarm message in the process that set the alarm
```

### 2. Run Unit Tests

The project includes unit tests for the `Alarm.Impl` and `Alarm.Server` modules. To run the tests, use the following command:

```bash
mix test
```

This will execute all the test cases in the `test/` directory and display the results.

### 3. Running the Complete Example Script

The file `example.exs` contains a complete example script that demonstrates how to start the alarm system, register devices, set alarms, and send data. You can run this script directly from the terminal:

```bash
mix run example.exs
```

This script includes:

- Registering multiple devices.
- Setting alarms for each device with different conditions.
- Adding data that triggers some alarms and not others.
- Testing the search functionality to find devices by specific criteria.

It's a helpful demonstration of how the alarm system operates in practice.

## Examples

### Registering a Device

```elixir
# Start the server
pid = Alarm.start()

# Register a device with some metadata
device_id = Alarm.register(pid, %{name: "HumiditySensor", location: "Room 2"})

# Returns a unique device ID
# device_id == 1
```

### Setting Alarms

```elixir
# Set an alarm for high temperature (triggered if temperature > 30)
Alarm.set_alarm(pid, :high_temp_alarm, fn(_id, data) -> data[:temperature] > 30 end)

# Set another alarm for low humidity (triggered if humidity < 20)
Alarm.set_alarm(pid, :low_humidity_alarm, fn(_id, data) -> data[:humidity] < 20 end)
```

### Adding Data and Triggering Alarms

```elixir
# Add data to the registered device (temperature and humidity)
Alarm.add_data(pid, device_id, %{temperature: 35, humidity: 15})

# This will trigger both the high temperature and low humidity alarms,
# sending a message to the process that set the alarm.
```

## Credits

The tests, README, and example script were created with the assistance of ChatGPT.
