import Config

config :nebulex_adapters_ecto, Nebulex.Adapters.EctoTest.Cache,
  stats: true,
  repo: Nebulex.Adapters.EctoTest.Repo,
  table: "cache_table",
  max_amount: 1000,
  gc_timeout: 1000

config :nebulex_adapters_ecto, Nebulex.Adapters.Ecto.DifferentTimestampTest.Cache,
  stats: true,
  table: "cache_table",
  timestamp_mfa: {Function, :identity, [123]},
  repo: Nebulex.Adapters.EctoTest.Repo,
  max_amount: 1000,
  gc_timeout: 1000

config :logger, level: :info

config :nebulex_adapters_ecto, Nebulex.Adapters.EctoTest.Repo,
  database: "nebulex_adapters_ecto_repo",
  password: System.fetch_env!("POSTGRES_PASSWORD"),
  hostname: System.fetch_env!("POSTGRES_HOST"),
  username: System.fetch_env!("POSTGRES_USER"),
  port: System.fetch_env!("POSTGRES_PORT")

config :nebulex_adapters_ecto, ecto_repos: [Nebulex.Adapters.EctoTest.Repo]
