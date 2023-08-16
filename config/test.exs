import Config

config :nebulex_adapters_ecto, Nebulex.Adapters.EctoTest.Cache,
  stats: true,
  repo: Nebulex.Adapters.EctoTest.Repo,
  table: "cache_table",
  max_amount: 1000,
  gc_timeout: 1000

config :logger, level: :info
