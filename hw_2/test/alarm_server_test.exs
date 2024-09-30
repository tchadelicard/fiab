defmodule AlarmServerTest do
  use ExUnit.Case
  alias Alarm.Server

  setup do
    {:ok, pid} = GenServer.start(Server, nil)
    %{pid: pid}
  end

  describe "init/1" do
    test "initializes with empty state", %{pid: pid} do
      state = GenServer.call(pid, :status)
      assert state == {%{}, %{}, %{}}
    end
  end

  describe "register/2" do
    test "registers a new device", %{pid: pid} do
      device_id = GenServer.call(pid, {:register, %{name: "TempSensor"}})
      assert device_id == 1
    end

    test "registers multiple devices", %{pid: pid} do
      device_id_1 = GenServer.call(pid, {:register, %{name: "TempSensor"}})
      device_id_2 = GenServer.call(pid, {:register, %{name: "HumiditySensor"}})
      assert device_id_1 == 1
      assert device_id_2 == 2
    end
  end

  describe "set_alarm/3" do
    test "sets a new alarm", %{pid: pid} do
      result = GenServer.call(pid, {:set_alarm, self(), :high_temp, fn _, data -> data[:temperature] > 30 end})
      assert result == :ok
    end

    test "returns an error when setting duplicate alarm names", %{pid: pid} do
      GenServer.call(pid, {:set_alarm, self(), :high_temp, fn _, data -> data[:temperature] > 30 end})
      result = GenServer.call(pid, {:set_alarm, self(), :high_temp, fn _, data -> data[:temperature] > 30 end})
      assert result == :error
    end
  end

  describe "search/2" do
    test "finds devices matching criteria", %{pid: pid} do
      GenServer.call(pid, {:register, %{name: "TempSensor", location: "Room 1"}})
      result = GenServer.call(pid, {:search, fn infos -> infos[:location] == "Room 1" end})
      assert result == [{1, %{name: "TempSensor", location: "Room 1"}}]
    end

    test "returns empty when no devices match", %{pid: pid} do
      GenServer.call(pid, {:register, %{name: "TempSensor", location: "Room 1"}})
      result = GenServer.call(pid, {:search, fn infos -> infos[:location] == "Room 2" end})
      assert result == []
    end
  end

  describe "data/3" do
    test "adds data to a device and triggers alarm when conditions are met", %{pid: pid} do
      device_id = GenServer.call(pid, {:register, %{name: "TempSensor"}})
      GenServer.call(pid, {:set_alarm, self(), :high_temp, fn _, data -> data[:temperature] > 30 end})
      GenServer.cast(pid, {:data, device_id, %{temperature: 35}})
      :timer.sleep(100)
      assert_received {:alarm, :high_temp, ^device_id, %{temperature: 35}}
    end

    test "does not trigger alarm when conditions are not met", %{pid: pid} do
      device_id = GenServer.call(pid, {:register, %{name: "TempSensor"}})
      GenServer.call(pid, {:set_alarm, self(), :high_temp, fn _, data -> data[:temperature] > 30 end})
      GenServer.cast(pid, {:data, device_id, %{temperature: 25}})
      :timer.sleep(100)
      refute_received {:alarm, :high_temp, ^device_id, %{temperature: 25}}
    end
  end
end
