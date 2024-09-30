defmodule AlarmImplTest do
  use ExUnit.Case

  alias Alarm.Impl

  describe "register/2" do
    test "successfully registers a new device" do
      {device_id, devices} = Impl.register({:register, %{name: "TempSensor"}}, %{})
      assert device_id == 1
      assert Map.get(devices, 1) == %{name: "TempSensor"}
    end

    test "registers multiple devices and assigns correct IDs" do
      {device_id_1, devices_1} = Impl.register({:register, %{name: "TempSensor"}}, %{})
      {device_id_2, devices_2} = Impl.register({:register, %{name: "HumiditySensor"}}, devices_1)
      assert device_id_1 == 1
      assert device_id_2 == 2
      assert Map.get(devices_2, 2) == %{name: "HumiditySensor"}
    end
  end

  describe "data/3" do
    test "adds data to a registered device" do
      current_devices = %{1 => %{name: "TempSensor"}}
      current_data = %{}
      updated_data = Impl.data({:data, 1, %{temperature: 25}}, current_devices, current_data)
      assert updated_data == %{1 => [%{temperature: 25}]}
    end

    test "does not add data to an unregistered device" do
      current_devices = %{1 => %{name: "TempSensor"}}
      current_data = %{}
      updated_data = Impl.data({:data, 2, %{temperature: 25}}, current_devices, current_data)
      assert updated_data == %{}  # Data should remain unchanged
    end
  end

  describe "set_alarm/3" do
    test "successfully sets a new alarm" do
      current_alarms = %{}
      {status, updated_alarms} = Impl.set_alarm({:set_alarm, self(), :high_temp, fn _, data -> data[:temperature] > 30 end}, current_alarms)
      assert status == :ok
      assert Map.has_key?(updated_alarms, :high_temp)
    end

    test "fails to set an alarm with the same name" do
      current_alarms = %{high_temp: {self(), fn _, data -> data[:temperature] > 30 end}}
      {status, updated_alarms} = Impl.set_alarm({:set_alarm, self(), :high_temp, fn _, data -> data[:temperature] > 30 end}, current_alarms)
      assert status == :error
      assert updated_alarms == current_alarms  # No changes should be made
    end
  end

  describe "search/2" do
    test "successfully finds matching devices" do
      devices = %{1 => %{name: "TempSensor", location: "Room 1"}, 2 => %{name: "HumiditySensor", location: "Room 2"}}
      result = Impl.search({:search, fn infos -> infos[:location] == "Room 1" end}, devices)
      assert result == [{1, %{name: "TempSensor", location: "Room 1"}}]
    end

    test "returns an empty list when no devices match" do
      devices = %{1 => %{name: "TempSensor", location: "Room 1"}, 2 => %{name: "HumiditySensor", location: "Room 2"}}
      result = Impl.search({:search, fn infos -> infos[:location] == "Room 3" end}, devices)
      assert result == []
    end
  end

  describe "check_and_send_alarms/2" do
    test "triggers alarms when conditions are met" do
      alarms = %{high_temp: {self(), fn _, data -> data[:temperature] > 30 end}}
      send(self(), {:data, 1, %{temperature: 35}})
      Impl.check_and_send_alarms({:data, 1, %{temperature: 35}}, alarms)
      assert_received {:alarm, :high_temp, 1, %{temperature: 35}}
    end

    test "does not trigger alarms when conditions are not met" do
      alarms = %{high_temp: {self(), fn _, data -> data[:temperature] > 30 end}}
      Impl.check_and_send_alarms({:data, 1, %{temperature: 25}}, alarms)
      refute_received {:alarm, :high_temp, 1, %{temperature: 25}}
    end
  end
end
