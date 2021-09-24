# file - path to file on client,
# filename - full filename (including relative path) client needs for the file on server
{args, _, _} =
  System.argv()
  |> OptionParser.parse(
    aliases: [f: :file, h: :host, p: :port],
    strict: [file: :string, filename: :string, host: :string, port: :integer]
  )

local_file_path = Keyword.get(args, :file, :no_file_in_args)

if local_file_path == :no_file_in_args do
  raise "No file in args"
end

host = Keyword.get(args, :host, "localhost") |> to_charlist()
port = Keyword.get(args, :port, 4040)

add_padding_f = fn data, expecting_size ->
  padding_size = expecting_size - byte_size(data)
  padding = :binary.copy(<<0>>, padding_size)
  padding <> data
end

encode_filename_size_f = fn filename ->
  filename
  |> byte_size()
  |> :binary.encode_unsigned()
  |> add_padding_f.(2)
end

encode_data_size_f = fn file ->
  file
  |> byte_size()
  |> :binary.encode_unsigned()
  |> add_padding_f.(40)
end

retrieve_filename_f = fn file_path ->
  file_path
  |> Path.split()
  |> List.last()
end

with {:ok, data} <- File.read(local_file_path),
     {:ok, socket} <- :gen_tcp.connect(host, port, [:binary, active: false]),
     filename = Keyword.get(args, :filename, retrieve_filename_f.(local_file_path)),
     :ok <- :gen_tcp.send(socket, encode_filename_size_f.(filename)),
     :ok <- :gen_tcp.send(socket, encode_data_size_f.(data)),
     :ok <- :gen_tcp.send(socket, filename),
     :ok <- :gen_tcp.send(socket, data),
     {:ok, <<status>>} <- :gen_tcp.recv(socket, 1) do
  if status == 1 do
    IO.puts("SUCCESS")
  else
    IO.puts("FAILURE")
  end
else
  {:error, error} ->
    IO.puts("Some error has occured: #{inspect(error)}")
end
