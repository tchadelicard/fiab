defmodule MicroDb.HashTable do

  def hash(key) do
    key = :crypto.hash(:sha,:erlang.term_to_binary(key)) |> Base.encode16(case: :lower)
    <<hashstart::binary-size(2),hashrest::binary>> = key
    {hashstart,hashrest}
  end

  def put(db,key,val) do
    {hashstart,hashrest} = hash(key)
    case File.write("data/#{db}/#{hashstart}/#{hashrest}",:erlang.term_to_binary(val)) do
      {:error, :enoent}->
        File.mkdir_p!("data/#{db}/#{hashstart}")
        File.write!("data/#{db}/#{hashstart}/#{hashrest}", :erlang.term_to_binary(val))
        :ok
      :ok-> :ok
    end
  end

  def get(db,key) do
    {hashstart,hashrest} = hash(key)
    case File.read("data/#{db}/#{hashstart}/#{hashrest}") do
      {:error,_}-> nil
      {:ok,bin}-> :erlang.binary_to_term(bin)
    end
  end

end
