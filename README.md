# TFU
Simple application that uploads files from clients over TCP.


## Starting application
```
iex -S mix
```
to start server on port 4040.

you can change through environment variables.
E.g.
```
PORT=4000 iex -S mix
```
to start server on port 4000.

`client.exs` file is an examle client implementation.

```
elixir client.exs -f path_to_file
```
to start client that connects to localhost.

If server is running on a different machine, pass it's ip address and port through `-h` and `-p` options.
E.g.
```
elixir client.exs -f ~/Downloads/file.txt -h 192.168.0.1 -p 4000
```