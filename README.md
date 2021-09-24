# TFU
Simple application that uploads files from clients over TCP.


## Starting application
```
iex -S mix
```
to start server on port 4040.

You can change port through environment variables.
```
PORT=4000 iex -S mix
```
Will start server on port 4000.

File `client.exs` implements an example of a client.

```
elixir client.exs -f path_to_file
```
Starts a client that connects to localhost.

If server is running on a different machine, pass it's ip address and port through `-h` and `-p` options.
```
elixir client.exs -f ~/Downloads/file.txt -h 192.168.0.1 -p 4000
```
