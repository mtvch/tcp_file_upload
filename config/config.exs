use Mix.Config

config :tfu,
  printing_stats_delay: 3 * 1000

config :logger, :console, metadata: [:pid]
