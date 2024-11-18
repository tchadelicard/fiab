defmodule ImtOrder.StatsAsDb do
  def find_bisec(file, id_bin) do
    {id, ""} = Integer.parse(id_bin)
    f = File.open!(file)
    {:ok, file_info} = :file.read_file_info(file)
    vals = bisec(f, id, 0, elem(file_info, 1))
    :ok = File.close(f)
    vals
  end

  # start of file case
  def bisec(f, id, 0, max) when max < 6 do
    {:ok, _} = :file.position(f, {:bof, 0})
    data = IO.binread(f, 30)
    [before, _bin |_rest] = String.split(data,"\n", parts: 3)
    [line_id_bin | rest] = String.split(before, ",")
    {line_id, ""} = Integer.parse(line_id_bin)
    case line_id do
      ^id -> rest
      _ -> {:error, "not found"}
    end
  end

  def bisec(f, id, min, max) do
    split_pos = min + div(max - min, 2)
    {:ok, _} = :file.position(f, {:bof, split_pos})
    data = IO.binread(f, 30)
    [before, bin |_rest] = String.split(data,"\n", parts: 3)
    case bin do
      ""-> # edge case : eof
      bisec(f, id, min, split_pos)
      _->
        [line_id_bin | rest] = String.split(bin, ",")
        {line_id, ""} = Integer.parse(line_id_bin)
        case line_id do
          ^id -> rest
          line_id when line_id < id -> bisec(f, id, split_pos + byte_size(before) + byte_size(bin), max)
          _ -> bisec(f, id, min, split_pos)
        end
    end
  end

  def find_enum(file,id_bin) do
    File.stream!(file) |> Enum.find_value(fn line->
      case line |> String.trim_trailing("\n") |> String.split(",") do
        [^id_bin|rest]->rest
        _-> nil
      end
    end)
  end
end
